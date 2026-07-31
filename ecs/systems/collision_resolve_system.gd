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

# --- Observability ---
var movers_processed: int = 0
var substeps_run: int = 0
var tile_collisions: int = 0
var entity_collisions: int = 0


## Integrates velocity into position for every mover, then resolves. Columns are fetched once,
## outside the loop, per the ADR-19 facade contract.
func run(delta: float, chunk: ChunkData, hash: SpatialHash) -> void:
	movers_processed = 0
	substeps_run = 0
	tile_collisions = 0
	entity_collisions = 0

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

		# Loose items fall; creatures are kept on the heightmap by the step/drop rule.
		if loose != null:
			velocity.y -= WorldConstants.GRAVITY_MPS2 * delta

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
				position, velocity, bounds, sub_delta, chunk, row, hash
			)
			position = outcome["position"]
			velocity = outcome["velocity"]

		px[row] = position.x
		py[row] = position.y
		pz[row] = position.z
		vx[row] = velocity.x
		vy[row] = velocity.y
		vz[row] = velocity.z

		if loose != null:
			loose.update_rest(velocity.length())
		movers_processed += 1


## One substep: axis-ordered tile resolve, then entity resolve, then depenetration.
func _resolve_substep(
	position: Vector3,
	velocity: Vector3,
	bounds: BoundsComponent,
	delta: float,
	chunk: ChunkData,
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
		if _blocked(attempt, bounds, chunk):
			velocity[axis] = 0.0
			tile_collisions += 1
		else:
			resolved = attempt

	# REQUIRED: forbid the diagonal slip. If both axes moved but the shared diagonal corner is
	# solid, an axis-separated resolve would have squeezed through the vertex.
	if resolved.x != position.x and resolved.z != position.z:
		var corner := Vector3(resolved.x, resolved.y, resolved.z)
		if _diagonal_gap(position, corner, bounds, chunk):
			resolved.z = position.z
			velocity.z = 0.0
			tile_collisions += 1

	# 2.5D step/drop against the heightmap. Loose items are excluded: they fall under gravity
	# rather than being snapped to the ground plane.
	if not ECSManager.loose_items.has(row):
		resolved = _apply_step_and_drop(resolved, position, bounds, chunk, velocity)

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
func _blocked(centre: Vector3, bounds: BoundsComponent, chunk: ChunkData) -> bool:
	var min_tile: Vector2i = chunk.world_to_tile(centre - bounds.half_extents)
	var max_tile: Vector2i = chunk.world_to_tile(centre + bounds.half_extents)
	for y in range(min_tile.y, max_tile.y + 1):
		for x in range(min_tile.x, max_tile.x + 1):
			if chunk.is_solid(x, y):
				return true
	return false


## Detects the pathological case of two diagonally-placed solids with open cells between them.
func _diagonal_gap(
	from: Vector3, to: Vector3, bounds: BoundsComponent, chunk: ChunkData
) -> bool:
	var a: Vector2i = chunk.world_to_tile(Vector3(to.x, from.y, from.z))
	var b: Vector2i = chunk.world_to_tile(Vector3(from.x, from.y, to.z))
	if not chunk.in_bounds(a.x, a.y) or not chunk.in_bounds(b.x, b.y):
		return false
	# Both orthogonal neighbours solid while the target corner is open == a vertex squeeze.
	return chunk.is_solid(a.x, a.y) and chunk.is_solid(b.x, b.y) and not _blocked(to, bounds, chunk)


## Steps up small ledges freely and snaps down small drops. Larger drops become a fall, which
## ActionResolutionSystem converts to damage using the same kinetic-energy model as melee.
func _apply_step_and_drop(
	resolved: Vector3,
	previous: Vector3,
	bounds: BoundsComponent,
	chunk: ChunkData,
	velocity: Vector3
) -> Vector3:
	var tile: Vector2i = chunk.world_to_tile(resolved)
	if not chunk.in_bounds(tile.x, tile.y):
		return previous
	var ground: float = chunk.height_at(tile.x, tile.y)
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
	}
