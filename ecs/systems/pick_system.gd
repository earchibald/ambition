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


## Marches the camera ray until it meets terrain — the side of a solid tile, or the floor surface
## of an open one. Shared by the aim vector and the debug cursor readout so both agree.
##
## Deliberately NOT `pick()`: the DDA registers a hit only on SOLID tiles, so over open floor it
## reports nothing, which is useless for "where on the ground am I pointing".
func ground_hit(origin: Vector3, direction: Vector3, chunk: ChunkData) -> Dictionary:
	var out: Dictionary = {"hit": false, "point": origin, "tile": Vector2i(-1, -1)}
	var travelled: float = 0.0
	while travelled < MAX_PICK_DIST_M:
		var point: Vector3 = origin + direction * travelled
		var tile: Vector2i = chunk.world_to_tile(point)
		if chunk.in_bounds(tile.x, tile.y):
			var solid: bool = chunk.is_solid(tile.x, tile.y)
			var surface: float = (
				WALL_TOP_M if solid else chunk.height_at(tile.x, tile.y)
			)
			if point.y <= surface:
				return {"hit": true, "point": point, "tile": tile}
		travelled += GROUND_MARCH_STEP_M
	return out


func counters() -> Dictionary:
	return {
		"picks_attempted": picks_attempted,
		"picks_hit_entity": picks_hit_entity,
		"picks_hit_tile": picks_hit_tile,
	}
