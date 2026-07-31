## Crosshair and mouse picking. Pure math through the SpatialHash and tile_map.
##
## No Godot physics raycasts, no Area3D. The camera is a viewer node; the ray math is ECS-side.
class_name PickSystem
extends RefCounted

const MAX_PICK_DIST_M: float = 30.0
const INTERACT_DIST_M: float = 2.5
const MELEE_REACH_M: float = 2.0

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
func interact_target(
	origin: Vector3, direction: Vector3, hash: SpatialHash, chunk: ChunkData
) -> int:
	var result: Dictionary = pick(origin, direction, hash, chunk)
	if float(result["distance"]) > INTERACT_DIST_M:
		return EH.INVALID
	return result["entity_handle"]


func counters() -> Dictionary:
	return {
		"picks_attempted": picks_attempted,
		"picks_hit_entity": picks_hit_entity,
		"picks_hit_tile": picks_hit_tile,
	}
