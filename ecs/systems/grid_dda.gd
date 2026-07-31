## Amanatides-Woo grid traversal over a chunk's tile_map. Used by picking, line of sight, and
## collision. Pure math — never a Godot raycast.
class_name GridDDA
extends RefCounted


## Marches until a solid tile is hit or `max_dist` is exhausted.
## Returns { hit: bool, tile: Vector2i, t: float, normal: Vector3 }.
static func march(
	origin: Vector3, dir: Vector3, max_dist: float, chunk: ChunkData
) -> Dictionary:
	var result: Dictionary = {
		"hit": false, "tile": Vector2i(-1, -1), "t": max_dist, "normal": Vector3.UP
	}
	var tile: Vector2i = chunk.world_to_tile(origin)
	var step_x: int = 1 if dir.x >= 0.0 else -1
	var step_y: int = 1 if dir.z >= 0.0 else -1
	var size: float = WorldConstants.TILE_SIZE_M

	# Distance along the ray to the next grid line on each axis.
	var t_delta_x: float = INF if absf(dir.x) < 0.000001 else absf(size / dir.x)
	var t_delta_y: float = INF if absf(dir.z) < 0.000001 else absf(size / dir.z)

	var origin_x: float = float(chunk.chunk_id.x) * WorldConstants.CHUNK_SIZE_M
	var origin_z: float = float(chunk.chunk_id.y) * WorldConstants.CHUNK_SIZE_M
	var local_x: float = origin.x - origin_x
	var local_z: float = origin.z - origin_z

	var next_x: float = INF
	if t_delta_x != INF:
		var boundary_x: float = (float(tile.x) + (1.0 if step_x > 0 else 0.0)) * size
		next_x = absf((boundary_x - local_x) / dir.x)
	var next_y: float = INF
	if t_delta_y != INF:
		var boundary_y: float = (float(tile.y) + (1.0 if step_y > 0 else 0.0)) * size
		next_y = absf((boundary_y - local_z) / dir.z)

	var travelled: float = 0.0
	# Bound the loop by the diagonal so a degenerate direction cannot spin forever.
	var max_steps: int = int(max_dist / size) * 2 + 4
	for _step in max_steps:
		if chunk.is_solid(tile.x, tile.y):
			result["hit"] = true
			result["tile"] = tile
			result["t"] = travelled
			return result
		if next_x < next_y:
			travelled = next_x
			if travelled > max_dist:
				break
			tile.x += step_x
			next_x += t_delta_x
			result["normal"] = Vector3(-float(step_x), 0.0, 0.0)
		else:
			travelled = next_y
			if travelled > max_dist:
				break
			tile.y += step_y
			next_y += t_delta_y
			result["normal"] = Vector3(0.0, 0.0, -float(step_y))
	return result


## True when nothing solid blocks the segment. This is the line-of-sight primitive; steam and
## smoke are handled by the caller as attenuating blockers.
static func has_line_of_sight(
	from: Vector3, to: Vector3, chunk: ChunkData
) -> bool:
	var delta: Vector3 = to - from
	var distance: float = delta.length()
	if distance <= 0.001:
		return true
	var hit: Dictionary = march(from, delta / distance, distance, chunk)
	return not hit["hit"]


## Tiles crossed by a segment, for summing per-tile sound attenuation.
static func tiles_along(from: Vector3, to: Vector3, chunk: ChunkData) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var delta: Vector3 = to - from
	var distance: float = delta.length()
	if distance <= 0.001:
		return out
	var dir: Vector3 = delta / distance
	var steps: int = int(distance / WorldConstants.TILE_SIZE_M) + 1
	var last := Vector2i(-9999, -9999)
	for i in steps + 1:
		var sample: Vector3 = from + dir * (float(i) * WorldConstants.TILE_SIZE_M)
		var tile: Vector2i = chunk.world_to_tile(sample)
		if tile != last:
			out.append(tile)
			last = tile
	return out
