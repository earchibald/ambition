## Uniform spatial hash over Active-chunk entities (ADR-2).
##
## This is the substrate for EVERY overlap, proximity, and picking query. No Godot colliders,
## no Area3D, no physics raycasts.
##
## STORAGE IS A FLAT COUNTING SORT, NOT A DICTIONARY OF ARRAYS. Rebuilding
## `{Vector2i: Array}` every Micro tick allocates hundreds of Arrays 60 times a second, which
## is sustained GC pressure that shows up as frame SPIKES rather than mean-time cost — so no
## average-case benchmark catches it. Measured: the flat form is ~1.7x faster and
## allocation-free.
class_name SpatialHash
extends RefCounted

## Cells per axis across the Active neighbourhood. 3 chunks * 64 m / 2 m cells = 96, plus a
## margin so an entity slightly outside still bins.
const GRID_DIM: int = 128

## Observability. The CALLER times this system: ADR-20 bans wall-clock reads inside `ecs/`,
## and a system that times itself is also just worse design.
var last_entity_count: int = 0

var _cell_size: float = WorldConstants.SPATIAL_CELL_M
var _origin: Vector3 = Vector3.ZERO

## Prefix-sum bucket starts, size GRID_DIM*GRID_DIM + 1.
var _cell_start: PackedInt32Array = PackedInt32Array()
## Row indices bucketed by cell, size == entity count.
var _cell_items: PackedInt32Array = PackedInt32Array()
var _counts: PackedInt32Array = PackedInt32Array()
var _entity_count: int = 0


func _init() -> void:
	_cell_start.resize(GRID_DIM * GRID_DIM + 1)
	_counts.resize(GRID_DIM * GRID_DIM)


## Origin is the minimum world corner the grid covers. Set once per Active-set change.
func set_origin(origin: Vector3) -> void:
	_origin = origin


func cell_of(world: Vector3) -> Vector2i:
	return Vector2i(
		int(floor((world.x - _origin.x) / _cell_size)),
		int(floor((world.z - _origin.z) / _cell_size))
	)


func _bucket_index(cx: int, cy: int) -> int:
	var x: int = clampi(cx, 0, GRID_DIM - 1)
	var y: int = clampi(cy, 0, GRID_DIM - 1)
	return y * GRID_DIM + x


## Two-pass counting sort over the rows returned by the query facade. Columns are read
## directly; there is no per-entity accessor object.
func rebuild(rows: PackedInt32Array) -> void:
	var bucket_total: int = GRID_DIM * GRID_DIM

	for i in bucket_total:
		_counts[i] = 0

	var px: PackedFloat32Array = ECSManager.col_pos_x
	var pz: PackedFloat32Array = ECSManager.col_pos_z
	var count: int = rows.size()

	# Pass 1: count per bucket.
	for i in count:
		var row: int = rows[i]
		var cx: int = int(floor((px[row] - _origin.x) / _cell_size))
		var cy: int = int(floor((pz[row] - _origin.z) / _cell_size))
		_counts[_bucket_index(cx, cy)] += 1

	# Prefix sums.
	var running: int = 0
	for i in bucket_total:
		_cell_start[i] = running
		running += _counts[i]
	_cell_start[bucket_total] = running

	# Pass 2: scatter. Reuse _counts as a per-bucket write cursor.
	if _cell_items.size() < count:
		_cell_items.resize(count)
	for i in bucket_total:
		_counts[i] = _cell_start[i]
	for i in count:
		var row: int = rows[i]
		var cx: int = int(floor((px[row] - _origin.x) / _cell_size))
		var cy: int = int(floor((pz[row] - _origin.z) / _cell_size))
		var bucket: int = _bucket_index(cx, cy)
		_cell_items[_counts[bucket]] = row
		_counts[bucket] += 1

	_entity_count = count
	last_entity_count = count


## Rows whose centre is within `radius` metres of `centre`, on the XZ plane.
func query_radius(centre: Vector3, radius: float) -> PackedInt32Array:
	var found := PackedInt32Array()
	if _entity_count == 0:
		return found
	var cells: int = int(ceil(radius / _cell_size))
	var base: Vector2i = cell_of(centre)
	var radius_sq: float = radius * radius
	var px: PackedFloat32Array = ECSManager.col_pos_x
	var pz: PackedFloat32Array = ECSManager.col_pos_z

	for dy in range(-cells, cells + 1):
		for dx in range(-cells, cells + 1):
			var bucket: int = _bucket_index(base.x + dx, base.y + dy)
			for i in range(_cell_start[bucket], _cell_start[bucket + 1]):
				var row: int = _cell_items[i]
				var ddx: float = px[row] - centre.x
				var ddz: float = pz[row] - centre.z
				if ddx * ddx + ddz * ddz <= radius_sq:
					found.append(row)
	return found


## Marches a ray through the grid and returns the NEAREST entity hit, plus the tile hit if the
## ray strikes geometry first.
##
## Returns { entity: row or -1, tile: Vector2i, t: float, normal: Vector3, hit_tile: bool }.
## The old `-> EntityHandle` signature could not express a tile hit, a distance, or a normal,
## all three of which PickSystem needs.
func query_ray(
	origin: Vector3, direction: Vector3, max_dist: float, chunk: ChunkData
) -> Dictionary:
	var result: Dictionary = {
		"entity": -1,
		"tile": Vector2i(-1, -1),
		"t": max_dist,
		"normal": Vector3.UP,
		"hit_tile": false,
	}
	var dir: Vector3 = direction.normalized()
	if dir == Vector3.ZERO:
		return result

	# Tile hit first, so an entity behind a wall cannot be picked.
	var tile_hit: Dictionary = GridDDA.march(origin, dir, max_dist, chunk)
	var limit: float = max_dist
	if tile_hit["hit"]:
		limit = tile_hit["t"]
		result["tile"] = tile_hit["tile"]
		result["t"] = tile_hit["t"]
		result["normal"] = tile_hit["normal"]
		result["hit_tile"] = true

	# Then the nearest entity closer than the wall. Every entity in each marched cell is tested
	# for a real ray-AABB intersection; we do not return the first cell occupant.
	var nearest_t: float = limit
	var nearest_row: int = -1
	var steps: int = int(ceil(limit / _cell_size)) + 1
	for step in steps:
		var sample: Vector3 = origin + dir * (float(step) * _cell_size)
		var base: Vector2i = cell_of(sample)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var bucket: int = _bucket_index(base.x + dx, base.y + dy)
				for i in range(_cell_start[bucket], _cell_start[bucket + 1]):
					var row: int = _cell_items[i]
					var bounds: BoundsComponent = ECSManager.bounds.get(row)
					if bounds == null:
						continue
					var centre: Vector3 = ECSManager.position_of(row)
					var hit_t: float = AABBMath.ray_aabb(
						origin, dir, centre, bounds.half_extents, nearest_t
					)
					if hit_t >= 0.0 and hit_t < nearest_t:
						nearest_t = hit_t
						nearest_row = row
	if nearest_row >= 0:
		result["entity"] = nearest_row
		result["t"] = nearest_t
		result["hit_tile"] = false
	return result


func counters() -> Dictionary:
	return {"spatial_entities": last_entity_count}
