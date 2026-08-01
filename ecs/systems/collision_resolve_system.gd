## Swept-AABB collision against the chunk tile_map, plus entity-vs-entity (ADR-2).
##
## This replaces `move_and_slide` entirely. No CharacterBody3D, no RigidBody3D, no colliders.
##
## The original spec said only "sweep the AABB via grid-DDA and slide/stop". Everything below
## marked REQUIRED was absent from it, and each absence is a real defect:
##   * SUBSTEPPING — a projectile at the Sprint 5 cap of 50 m/s moves 0.833 m per Micro tick,
##     further than a rat's entire AABB, so it would pass clean through without substeps.
##   * ENTITY-vs-ENTITY — specified NOWHERE, which means no projectile could ever hit anything.
##   * AXIS ORDER — resolving X and Z independently in one pass makes a 0.4 m half-extent mover
##     either stick or penetrate in a 1.0 m corridor.
##   * DIAGONAL GAPS — with two diagonal solids, an axis-separated resolve slips through the
##     shared vertex.
##   * 2.5D STEP/DROP — "use the heightmap" with no step or drop constant is not a rule.
class_name CollisionResolveSystem
extends RefCounted

## Largest half-extent any entity is expected to have, used to bound entity-vs-entity queries.
## Humanoids are 0.3; this leaves headroom without inflating the search radius.
const MAX_OTHER_EXTENT_M: float = 0.6

## How far a mover's feet may sit above the floor and still count as standing on it. Slack is
## needed because the step/drop snap and the gravity integration meet at slightly different
## values; without it a walking creature flickers between grounded and airborne every frame.
const GROUNDED_EPSILON_M: float = 0.02

## Landings drained by GameLoopManager each Micro tick: [{row, speed}]. This system does not
## apply damage — ActionResolutionSystem owns the energy model for both falls and melee.
var landings: Array = []

# --- Observability ---
var movers_processed: int = 0
var substeps_run: int = 0
var tile_collisions: int = 0
var entity_collisions: int = 0
var airborne_movers: int = 0


## Integrates velocity into position for every mover, then resolves. Columns are fetched once,
## outside the loop, per the ADR-19 facade contract.
func run(delta: float, sampler: TileSampler, hash: SpatialHash) -> void:
	movers_processed = 0
	substeps_run = 0
	tile_collisions = 0
	entity_collisions = 0
	airborne_movers = 0
	landings.clear()

	var rows: PackedInt32Array = ECSManager.query(ComponentMask.MOVER)
	var px: PackedFloat32Array = ECSManager.col_pos_x
	var py: PackedFloat32Array = ECSManager.col_pos_y
	var pz: PackedFloat32Array = ECSManager.col_pos_z
	var vx: PackedFloat32Array = ECSManager.col_vel_x
	var vy: PackedFloat32Array = ECSManager.col_vel_y
	var vz: PackedFloat32Array = ECSManager.col_vel_z

	for i in rows.size():
		var row: int = rows[i]
		var loose: LooseItemComponent = ECSManager.loose_items.get(row)
		if loose != null and loose.resting:
			continue

		var bounds: BoundsComponent = ECSManager.bounds[row]
		var velocity := Vector3(vx[row], vy[row], vz[row])
		var start := Vector3(px[row], py[row], pz[row])
		var was_airborne: bool = false
		var impact_speed: float = 0.0

		if loose != null:
			velocity.y -= WorldConstants.GRAVITY_MPS2 * delta
		else:
			# CREATURES FALL TOO. Previously only loose items had gravity, so walking off the
			# 2.5 m pit edge left the mover at its old height and the step/drop rule simply held
			# it there — a drop was indistinguishable from a step, and `resolve_fall` had no
			# caller anywhere. Gravity is what turns the pit back into a pit.
			was_airborne = _is_airborne(start, bounds, sampler)
			velocity = _apply_creature_gravity(delta, velocity, was_airborne)
			impact_speed = maxf(0.0, -velocity.y)

		# Persist the post-gravity velocity BEFORE the at-rest early-out below. Skipping this
		# leaves stale downward speed in the column for a mover that has come to rest.
		vx[row] = velocity.x
		vy[row] = velocity.y
		vz[row] = velocity.z

		var speed: float = velocity.length()
		if speed <= 0.0:
			if loose != null:
				loose.update_rest(0.0)
			continue

		# REQUIRED: substep so fast movers cannot tunnel.
		var travel: float = speed * delta
		var substeps: int = maxi(1, int(ceil(travel / WorldConstants.SUBSTEP_MAX_M)))
		var sub_delta: float = delta / float(substeps)
		var position := Vector3(px[row], py[row], pz[row])

		for _s in substeps:
			substeps_run += 1
			var outcome: Dictionary = _resolve_substep(
				position, velocity, bounds, sub_delta, sampler, row, hash
			)
			position = outcome["position"]
			velocity = outcome["velocity"]

		# Detect the landing by the AIRBORNE -> GROUNDED transition across the whole frame, not
		# by reading velocity next frame. The substep resolve legitimately zeroes vertical
		# velocity when it snaps a mover onto the floor, so by the next frame the impact speed
		# is already gone and the landing is invisible. The transition is the reliable signal.
		if loose == null and was_airborne and not _is_airborne(position, bounds, sampler):
			landings.append({"row": row, "speed": impact_speed})
			velocity.y = 0.0

		px[row] = position.x
		py[row] = position.y
		pz[row] = position.z
		vx[row] = velocity.x
		vy[row] = velocity.y
		vz[row] = velocity.z

		if loose != null:
			loose.update_rest(velocity.length())
		movers_processed += 1


## True when a creature's feet are clear of the floor beneath it.
##
## Slack is needed because the step/drop snap and the gravity integration meet at slightly
## different values; without it a walking creature flickers grounded/airborne every frame.
func _is_airborne(position: Vector3, bounds: BoundsComponent, sampler: TileSampler) -> bool:
	if not sampler.contains_world(position):
		return false
	var ground: float = sampler.height_at_world(position)
	return position.y - bounds.half_extents.y > ground + GROUNDED_EPSILON_M


## Accelerates a creature downward while airborne, and zeroes its descent once grounded.
##
## Grounding MUST zero `velocity.y`. Without it a creature standing still accumulates downward
## speed forever, and the first 0.1 m step it takes reports as a fatal fall.
func _apply_creature_gravity(delta: float, velocity: Vector3, airborne: bool) -> Vector3:
	if airborne:
		airborne_movers += 1
		velocity.y -= WorldConstants.GRAVITY_MPS2 * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0
	return velocity


## One substep: axis-ordered tile resolve, then entity resolve, then depenetration.
func _resolve_substep(
	position: Vector3,
	velocity: Vector3,
	bounds: BoundsComponent,
	delta: float,
	sampler: TileSampler,
	row: int,
	hash: SpatialHash
) -> Dictionary:
	var desired: Vector3 = position + velocity * delta

	# REQUIRED: resolve the LARGER horizontal component first, re-test, then the smaller.
	# Built explicitly: a ternary yields an untyped Array, which cannot be assigned to
	# Array[int] and would abort this function at runtime.
	var order: Array[int] = []
	if absf(velocity.x) >= absf(velocity.z):
		order.append(0)
		order.append(2)
	else:
		order.append(2)
		order.append(0)
	var resolved: Vector3 = position

	for axis in order:
		var attempt: Vector3 = resolved
		attempt[axis] = desired[axis]
		if _blocked(attempt, bounds, sampler):
			velocity[axis] = 0.0
			tile_collisions += 1
		else:
			resolved = attempt

	# REQUIRED: forbid the diagonal slip. If both axes moved but the shared diagonal corner is
	# solid, an axis-separated resolve would have squeezed through the vertex.
	if resolved.x != position.x and resolved.z != position.z:
		var corner := Vector3(resolved.x, resolved.y, resolved.z)
		if _diagonal_gap(position, corner, bounds, sampler):
			resolved.z = position.z
			velocity.z = 0.0
			tile_collisions += 1

	# VERTICAL INTEGRATION. The axis loop above resolves X and Z only. Without this line nothing
	# ever moves on Y: a falling body accumulated downward velocity forever while its position
	# stayed put, so the 2.5 m pit could not be entered and a dropped item hung in the air. The
	# horizontal axes are resolved separately because they slide along walls; Y does not slide,
	# it is caught by the heightmap below.
	resolved.y = desired.y

	# 2.5D step/drop against the heightmap. Loose items are excluded: they fall under gravity and
	# come to rest on the floor rather than being snapped up onto ledges.
	if ECSManager.loose_items.has(row):
		if sampler.contains_world(resolved):
			var floor_y: float = sampler.height_at_world(resolved) + bounds.half_extents.y
			if resolved.y <= floor_y:
				resolved.y = floor_y
				velocity.y = 0.0
	else:
		resolved = _apply_step_and_drop(resolved, position, bounds, sampler, velocity)

	# REQUIRED: entity-vs-entity. Without this nothing can ever be hit.
	if hash != null:
		# Radius is the mover's own reach plus a generous allowance for the largest plausible
		# other entity. Padding by a whole spatial cell instead scans 5x5 cells rather than 3x3,
		# which measured as ~4x the candidate count for no correctness benefit.
		var radius: float = bounds.max_horizontal_extent() + MAX_OTHER_EXTENT_M
		var candidates: PackedInt32Array = hash.query_radius(resolved, radius)
		for c in candidates.size():
			var other: int = candidates[c]
			if other == row:
				continue
			var other_bounds: BoundsComponent = ECSManager.bounds.get(other)
			if other_bounds == null:
				continue
			# Loose items pass through each other; creatures do not interpenetrate.
			if ECSManager.loose_items.has(row) and ECSManager.loose_items.has(other):
				continue
			var other_pos: Vector3 = ECSManager.position_of(other)
			if not AABBMath.overlaps(
				resolved, bounds.half_extents, other_pos, other_bounds.half_extents
			):
				continue
			var push: Vector3 = AABBMath.min_translation(
				resolved, bounds.half_extents, other_pos, other_bounds.half_extents
			)
			resolved += push * (1.0 + WorldConstants.SLIDE_EPSILON_M)
			entity_collisions += 1

	return {"position": resolved, "velocity": velocity}


## True if the AABB footprint at `centre` overlaps any solid tile.
func _blocked(centre: Vector3, bounds: BoundsComponent, sampler: TileSampler) -> bool:
	# Sampled in WORLD space, stepping a tile at a time and always including the far corner.
	# Tile-index loops cannot cross a chunk seam: the indices are chunk-local, so a footprint
	# straddling two chunks produced out-of-range tiles that read as solid and walled the mover
	# in at the boundary.
	var low: Vector3 = centre - bounds.half_extents
	var high: Vector3 = centre + bounds.half_extents
	var x: float = low.x
	while true:
		var z: float = low.z
		while true:
			if sampler.solid_at_world(Vector3(x, centre.y, z)):
				return true
			if z >= high.z:
				break
			z = minf(z + WorldConstants.TILE_SIZE_M, high.z)
		if x >= high.x:
			break
		x = minf(x + WorldConstants.TILE_SIZE_M, high.x)
	return false


## Detects the pathological case of two diagonally-placed solids with open cells between them.
func _diagonal_gap(
	from: Vector3, to: Vector3, bounds: BoundsComponent, sampler: TileSampler
) -> bool:
	var side_a := Vector3(to.x, from.y, from.z)
	var side_b := Vector3(from.x, from.y, to.z)
	# Both orthogonal neighbours solid while the target corner is open == a vertex squeeze.
	return (
		sampler.solid_at_world(side_a)
		and sampler.solid_at_world(side_b)
		and not _blocked(to, bounds, sampler)
	)


## Steps up small ledges freely and snaps down small drops. Larger drops become a fall, which
## ActionResolutionSystem converts to damage using the same kinetic-energy model as melee.
func _apply_step_and_drop(
	resolved: Vector3,
	previous: Vector3,
	bounds: BoundsComponent,
	sampler: TileSampler,
	velocity: Vector3
) -> Vector3:
	if not sampler.contains_world(resolved):
		return previous
	var ground: float = sampler.height_at_world(resolved)
	var feet: float = resolved.y - bounds.half_extents.y
	var rise: float = ground - feet

	if rise > WorldConstants.STEP_UP_MAX_M:
		# Too tall to step onto: treat as a wall.
		return previous
	if rise > 0.0:
		return Vector3(resolved.x, ground + bounds.half_extents.y, resolved.z)
	var drop: float = -rise
	if drop <= WorldConstants.AUTO_DROP_MAX_M and velocity.y <= 0.0:
		return Vector3(resolved.x, ground + bounds.half_extents.y, resolved.z)
	return resolved


func counters() -> Dictionary:
	return {
		"movers_processed": movers_processed,
		"substeps_run": substeps_run,
		"tile_collisions": tile_collisions,
		"entity_collisions": entity_collisions,
		"airborne_movers": airborne_movers,
	}
