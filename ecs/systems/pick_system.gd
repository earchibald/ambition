## Crosshair and mouse picking. Pure math through the SpatialHash and tile_map.
##
## No Godot physics raycasts, no Area3D. The camera is a viewer node; the ray math is ECS-side.
class_name PickSystem
extends RefCounted

const MAX_PICK_DIST_M: float = 30.0
const INTERACT_DIST_M: float = 2.5
const MELEE_REACH_M: float = 2.0

## Quarter-tile sampling for the ground march: finer than the smallest arena feature, and 120
## samples cost nothing next to the systems that run every Micro tick.
const GROUND_MARCH_STEP_M: float = 0.25

## Must match TerrainView.WALL_HEIGHT_M. Kept as a literal because `ecs/` may not depend on
## `viewer/` — the dependency only ever points the other way.
const WALL_TOP_M: float = 2.4

## Below this vertical component a ray is treated as level: it meets the ground plane either
## never, or so far away that the intersection is numerically worthless.
const HORIZON_EPSILON: float = 0.0001

## Inside this radius the cursor is effectively on top of the actor, and the direction between
## them is numerically meaningless.
const MIN_AIM_RADIUS_M: float = 0.05

## How far from the cursor's ground point an entity may be and still be considered "pointed at".
## Roughly one and a half tiles: forgiving enough that a 0.6 m box seen from 14 m up is easy to
## select, tight enough that it stays unambiguous in a crowd.
const CURSOR_SNAP_RADIUS_M: float = 1.6

var picks_attempted: int = 0
var picks_hit_entity: int = 0
var picks_hit_tile: int = 0


## Returns { entity_handle, tile, distance, hit_tile }.
func pick(
	origin: Vector3, direction: Vector3, hash: SpatialHash, chunk: ChunkData
) -> Dictionary:
	picks_attempted += 1
	var raw: Dictionary = hash.query_ray(origin, direction, MAX_PICK_DIST_M, chunk)
	var entity_row: int = raw["entity"]
	var out: Dictionary = {
		"entity_handle": EH.INVALID,
		"tile": raw["tile"],
		"distance": raw["t"],
		"hit_tile": raw["hit_tile"],
	}
	if entity_row >= 0:
		out["entity_handle"] = ECSManager.handle_of(entity_row)
		picks_hit_entity += 1
	elif raw["hit_tile"]:
		picks_hit_tile += 1
	return out


## Melee target selection: nearest entity inside reach and inside the swing arc. Uses the hash
## directly rather than a ray, because a swing is a volume, not a line.
func melee_target(attacker_row: int, swing_dir: Vector3, hash: SpatialHash) -> int:
	var origin: Vector3 = ECSManager.position_of(attacker_row)
	var candidates: PackedInt32Array = hash.query_radius(origin, MELEE_REACH_M)
	var best_row: int = -1
	var best_distance: float = INF
	var facing: Vector3 = swing_dir.normalized()

	for i in candidates.size():
		var row: int = candidates[i]
		if row == attacker_row:
			continue
		var body: BodyComponent = ECSManager.bodies.get(row)
		if body == null or not body.is_alive():
			continue
		var to_target: Vector3 = ECSManager.position_of(row) - origin
		var flat := Vector3(to_target.x, 0.0, to_target.z)
		if flat.length() < 0.001:
			continue
		# 120-degree swing arc.
		if facing.length() > 0.001 and rad_to_deg(facing.angle_to(flat.normalized())) > 60.0:
			continue
		var distance: float = flat.length()
		if distance < best_distance:
			best_distance = distance
			best_row = row
	if best_row < 0:
		return EH.INVALID
	return ECSManager.handle_of(best_row)


## Context-sensitive interact target for the 'E' router.
##
## Reach is measured from the ACTOR, never from the ray origin. That distinction was the whole
## bug: the ray starts at the camera, which sits ~14 m behind and above the player, so comparing
## the ray's own travel distance against a 2.5 m reach could never pass and `E` did nothing at
## all, on any object, ever.
##
## Cursor first, then proximity. Pointing at a thing should take that thing; standing next to one
## thing and pointing at the sky should still take it.
func interact_target(
	actor_row: int, origin: Vector3, direction: Vector3, hash: SpatialHash, chunk: ChunkData
) -> int:
	var actor_position: Vector3 = ECSManager.position_of(actor_row)
	var under_cursor: int = pick(origin, direction, hash, chunk)["entity_handle"]
	if EH.is_valid(under_cursor):
		var row: int = ECSManager.resolve(under_cursor)
		# The actor must be excluded explicitly. A camera ray aimed at the player's feet hits the
		# PLAYER first, at distance zero, so without this every `E` press targets yourself.
		if row >= 0 and row != actor_row:
			if actor_position.distance_to(ECSManager.position_of(row)) <= INTERACT_DIST_M:
				return under_cursor
	return nearest_within_reach(actor_row, actor_position, hash)


## The entity nearest to where the cursor is pointing, within a forgiving radius.
##
## Selection USED to demand an exact ray-AABB intersection. A villager is a 0.6 m box seen from
## 14 m up, so the target on screen is a few pixels and the ray had to thread it — reported from
## play as "the hitbox seems very very finicky", which is exactly what an exact-hit test feels
## like at this camera distance.
##
## Pointing NEAR a thing is unambiguous to a human, so it should be unambiguous here.
##
## Deliberately does NOT use the ray pick. `GridDDA` works in chunk-LOCAL tiles and so takes a
## ChunkData rather than the sampler, which means the ray path cannot cross a chunk seam; making
## it sampler-based is a real refactor and is not what this fix is about. Proximity to the ground
## point is both simpler and strictly more forgiving, which is the whole requirement.
##
## The tradeoff, stated plainly: pointing at a wall with a villager standing behind it will still
## select the villager. For a debug inspector at a 1.6 m radius that is the right trade — this
## chooses "always selects what you meant" over "never selects through cover".
func cursor_target(
	origin: Vector3, direction: Vector3, hash: SpatialHash, sampler: TileSampler, exclude: int
) -> int:
	var ground: Dictionary = cursor_ground(origin, direction, sampler)
	if not ground["hit"]:
		return EH.INVALID
	var at: Vector3 = ground["point"]

	var candidates: PackedInt32Array = hash.query_radius(at, CURSOR_SNAP_RADIUS_M)
	var best_row: int = -1
	var best_distance: float = INF
	for i in candidates.size():
		var row: int = candidates[i]
		if row == exclude:
			continue
		# Compared on the FLAT plane. A villager is 1.8 m tall and the cursor point is on the
		# floor, so a 3D distance would rank a small item above the person standing beside it.
		var to: Vector3 = ECSManager.position_of(row) - at
		var flat: float = Vector2(to.x, to.z).length()
		# Standing INSIDE a footprint beats being merely near one, so a big entity you are
		# clearly pointing at is never lost to a small one a few centimetres closer.
		var bounds: BoundsComponent = ECSManager.bounds.get(row)
		if bounds != null and flat <= bounds.max_horizontal_extent():
			flat = -1.0
		if flat <= CURSOR_SNAP_RADIUS_M and flat < best_distance:
			best_distance = flat
			best_row = row
	return EH.INVALID if best_row < 0 else ECSManager.handle_of(best_row)


## Nearest other entity inside interaction reach, regardless of where the camera points.
func nearest_within_reach(actor_row: int, actor_position: Vector3, hash: SpatialHash) -> int:
	var candidates: PackedInt32Array = hash.query_radius(actor_position, INTERACT_DIST_M)
	var best_row: int = -1
	var best_distance: float = INF
	for i in candidates.size():
		var row: int = candidates[i]
		if row == actor_row:
			continue
		var distance: float = actor_position.distance_to(ECSManager.position_of(row))
		# The hash returns whole CELLS, so a candidate can be well outside the radius. Nearest is
		# not the same as near: without this the reach rule vanishes and `E` grabs across a room.
		if distance <= INTERACT_DIST_M and distance < best_distance:
			best_distance = distance
			best_row = row
	if best_row < 0:
		return EH.INVALID
	return ECSManager.handle_of(best_row)


## The flat direction a camera ray implies, from `from`. Always defined, and CONTINUOUS across
## every case — which is the entire point.
##
## The previous version marched the terrain and, whenever the march found nothing, fell back to a
## hard-coded `+Z`. The march fails for every ray that reaches the horizon or outruns its 30 m
## budget, which is most of the upper half of the screen, so sweeping the cursor past the player
## made the aim SNAP to a fixed direction instead of continuing to rotate.
##
## Two cases, and they meet exactly:
##   * A descending ray meets the horizontal plane through `from` analytically. No marching, no
##     distance cap, no terrain dependency.
##   * A level or rising ray has no intersection at all. Its horizontal HEADING is used instead,
##     which is precisely the limit the intersection point approaches as the ray nears the
##     horizon — so the two cases agree in the limit and there is no discontinuity anywhere.
##
## Returns `Vector3.ZERO` only when the answer is genuinely undefined: a ray straight down onto
## the actor itself. Callers hold their previous aim rather than inventing one.
static func aim_direction(from: Vector3, origin: Vector3, direction: Vector3) -> Vector3:
	var heading := Vector3(direction.x, 0.0, direction.z)
	if heading.length() < HORIZON_EPSILON:
		# Straight down. There is no horizontal component to fall back on.
		return Vector3.ZERO
	heading = heading.normalized()

	if direction.y < -HORIZON_EPSILON:
		var distance: float = (from.y - origin.y) / direction.y
		if distance > 0.0:
			var point: Vector3 = origin + direction * distance
			var flat := Vector3(point.x - from.x, 0.0, point.z - from.z)
			# Under the cursor-on-top-of-the-actor radius the direction is numerically
			# meaningless and would jitter wildly; the ray's heading is the stable answer.
			if flat.length() > MIN_AIM_RADIUS_M:
				return flat.normalized()
	return heading


## Where the cursor is pointing ON THE GROUND, anywhere on screen.
##
## `ground_hit` MARCHES, and its budget is `MAX_PICK_DIST_M` (30 m) because that is the right
## limit for reaching things. The camera sits 14.2 m from the player, so a 30 m march covers only
## about 16 m of ground past them — and the readout said "not over the world" across most of the
## visible screen, which is ludicrous when you are plainly pointing at a floor tile.
##
## Marching further is the wrong fix twice over: a 250 m march is a thousand samples, and every
## sample asks the grid for a tile, which GENERATES chunks. Waving the mouse would populate the
## world.
##
## Instead this solves it analytically. A downward ray meets a horizontal plane exactly, in one
## division. Take the plane through y=0, read the tile it lands on, and if that tile turns out to
## be raised or sunken, re-solve against the plane at ITS height. Two iterations converge for the
## ledge and the pit; flat ground — which is nearly everything — is exact on the first.
func cursor_ground(origin: Vector3, direction: Vector3, sampler: TileSampler) -> Dictionary:
	var miss: Dictionary = {"hit": false, "point": origin}
	if direction.y > -HORIZON_EPSILON:
		# Level or rising: it never meets the ground at all.
		return miss

	var plane_y: float = 0.0
	var point: Vector3 = origin
	for _refinement in 3:
		var distance: float = (plane_y - origin.y) / direction.y
		if distance <= 0.0:
			return miss
		point = origin + direction * distance
		if not sampler.contains_world(point):
			return miss
		var surface: float = sampler.height_at_world(point)
		if absf(surface - plane_y) < 0.01:
			return {"hit": true, "point": point}
		plane_y = surface
	# Three refinements without settling means the ray is skimming across a staircase of
	# elevations. The last sample is still the best answer available, and it is a tile.
	return {"hit": true, "point": point}


## Marches the camera ray until it meets terrain.
##
## SUPERSEDED for cursor work by `cursor_ground`, which solves the same thing analytically and is
## not capped at 30 m. Kept because a march is the only way to answer "what is the FIRST solid
## thing along this ray", which a plane solve cannot do — but do not reach for it to find where
## the mouse is pointing.
##
## Original doc follows.
##
## Marches the camera ray until it meets terrain — the side of a solid tile, or the floor surface
## of an open one. Shared by the aim vector and the debug cursor readout so both agree.
##
## Deliberately NOT `pick()`: the DDA registers a hit only on SOLID tiles, so over open floor it
## reports nothing, which is useless for "where on the ground am I pointing".
func ground_hit(origin: Vector3, direction: Vector3, sampler: TileSampler) -> Dictionary:
	var out: Dictionary = {"hit": false, "point": origin}
	var travelled: float = 0.0
	while travelled < MAX_PICK_DIST_M:
		var point: Vector3 = origin + direction * travelled
		if sampler.contains_world(point):
			var solid: bool = sampler.solid_at_world(point)
			var surface: float = WALL_TOP_M if solid else sampler.height_at_world(point)
			if point.y <= surface:
				return {"hit": true, "point": point}
		travelled += GROUND_MARCH_STEP_M
	return out


func counters() -> Dictionary:
	return {
		"picks_attempted": picks_attempted,
		"picks_hit_entity": picks_hit_entity,
		"picks_hit_tile": picks_hit_tile,
	}
