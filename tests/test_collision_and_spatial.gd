## SpatialHash, grid DDA, and CollisionResolveSystem (Sprint 1 gate).
extends GutTest

var chunk: ChunkData
var hash: SpatialHash
var collision: CollisionResolveSystem
var spawned: PackedInt64Array = PackedInt64Array()


func before_each() -> void:
	chunk = TestArena.build(Vector3i.ZERO)
	hash = SpatialHash.new()
	hash.set_origin(Vector3(-64.0, 0.0, -64.0))
	collision = CollisionResolveSystem.new()
	spawned = PackedInt64Array()


func after_each() -> void:
	for i in spawned.size():
		ECSManager.destroy_entity(spawned[i])


func _spawn(position: Vector3, extents: Vector3 = Vector3(0.3, 0.9, 0.3)) -> int:
	var handle: int = ECSManager.allocate_entity()
	var row: int = EH.index_of(handle)
	ECSManager.set_position(row, position)
	ECSManager.add_component_bit(row, ComponentMask.POSITION)
	ECSManager.bounds[row] = BoundsComponent.new(extents)
	ECSManager.add_component_bit(row, ComponentMask.BOUNDS)
	spawned.append(handle)
	return handle


func _rebuild() -> void:
	ECSManager.flush_structural_changes()
	hash.rebuild(ECSManager.query(ComponentMask.SPATIAL))


func test_spatial_hash_finds_entities_in_radius() -> void:
	var a: int = _spawn(Vector3(10.0, 0.9, 10.0))
	_spawn(Vector3(10.5, 0.9, 10.0))
	_spawn(Vector3(40.0, 0.9, 40.0))
	_rebuild()
	var near: PackedInt32Array = hash.query_radius(Vector3(10.0, 0.9, 10.0), 2.0)
	assert_eq(near.size(), 2, "only the two nearby entities are returned")
	assert_true(near.has(EH.index_of(a)), "the query includes the entity at the centre")


func test_spatial_hash_excludes_distant_entities() -> void:
	_spawn(Vector3(10.0, 0.9, 10.0))
	_spawn(Vector3(50.0, 0.9, 50.0))
	_rebuild()
	var near: PackedInt32Array = hash.query_radius(Vector3(10.0, 0.9, 10.0), 3.0)
	assert_eq(near.size(), 1, "the far entity is excluded")


func test_dda_detects_a_wall() -> void:
	# The arena has an interior wall at tile x=24.
	var from: Vector3 = chunk.tile_to_world(10, 10) + Vector3(0.0, 1.0, 0.0)
	var to: Vector3 = chunk.tile_to_world(40, 10) + Vector3(0.0, 1.0, 0.0)
	assert_false(
		GridDDA.has_line_of_sight(from, to, chunk), "the interior wall blocks line of sight"
	)


func test_dda_sees_through_the_doorway() -> void:
	var from: Vector3 = chunk.tile_to_world(10, TestArena.DOORWAY_Y) + Vector3(0.0, 1.0, 0.0)
	var to: Vector3 = chunk.tile_to_world(40, TestArena.DOORWAY_Y) + Vector3(0.0, 1.0, 0.0)
	assert_true(GridDDA.has_line_of_sight(from, to, chunk), "the doorway is a clear line")


func test_ray_aabb_hits_and_misses_correctly() -> void:
	var centre := Vector3(5.0, 0.0, 0.0)
	var half := Vector3(0.5, 0.5, 0.5)
	var hit: float = AABBMath.ray_aabb(Vector3.ZERO, Vector3.RIGHT, centre, half, 100.0)
	assert_almost_eq(hit, 4.5, 0.01, "the ray enters the box at 4.5 m")
	var miss: float = AABBMath.ray_aabb(Vector3.ZERO, Vector3.UP, centre, half, 100.0)
	assert_eq(miss, -1.0, "a ray pointing away misses")


func test_mover_is_stopped_by_a_wall() -> void:
	# Start just west of the interior wall, moving east into it.
	var start: Vector3 = chunk.tile_to_world(22, 10) + Vector3(0.0, 0.9, 0.0)
	var handle: int = _spawn(start)
	var row: int = EH.index_of(handle)
	ECSManager.set_velocity(row, Vector3(6.0, 0.0, 0.0))
	_rebuild()
	# Counters are per-tick and reset on every run(), so accumulate across the sweep. Reading
	# them after the loop would only see the final, already-stopped tick.
	var total_tile_hits: int = 0
	for _i in 60:
		collision.run(1.0 / 60.0, chunk, hash)
		total_tile_hits += collision.tile_collisions
	var final_x: float = ECSManager.position_of(row).x
	assert_lt(final_x, chunk.tile_to_world(24, 10).x, "the mover never passes into the wall")
	assert_gt(total_tile_hits, 0, "a tile collision was recorded")


## THE TUNNELING GUARD. A projectile at 50 m/s travels 0.833 m per Micro tick, further than a
## small AABB, so without substepping it passes clean through geometry.
func test_fast_mover_does_not_tunnel_through_a_wall() -> void:
	var start: Vector3 = chunk.tile_to_world(20, 10) + Vector3(0.0, 0.9, 0.0)
	var handle: int = _spawn(start, Vector3(0.1, 0.1, 0.1))
	var row: int = EH.index_of(handle)
	ECSManager.set_velocity(row, Vector3(50.0, 0.0, 0.0))
	_rebuild()
	var total_substeps: int = 0
	for _i in 30:
		collision.run(1.0 / 60.0, chunk, hash)
		total_substeps += collision.substeps_run
	assert_lt(
		ECSManager.position_of(row).x,
		chunk.tile_to_world(24, 10).x + 1.0,
		"a 50 m/s mover is still stopped by the wall"
	)
	# 50 m/s over 1/60 s is 0.833 m, which needs ceil(0.833 / 0.125) = 7 substeps per tick.
	assert_gt(total_substeps, 6, "substepping actually engaged for a fast mover")


func test_mover_slides_along_a_wall_instead_of_sticking() -> void:
	var start: Vector3 = chunk.tile_to_world(23, 10) + Vector3(0.0, 0.9, 0.0)
	var handle: int = _spawn(start)
	var row: int = EH.index_of(handle)
	# Diagonally into the wall: the blocked axis stops, the free axis keeps moving.
	ECSManager.set_velocity(row, Vector3(4.0, 0.0, 4.0))
	_rebuild()
	var before_z: float = ECSManager.position_of(row).z
	for _i in 30:
		collision.run(1.0 / 60.0, chunk, hash)
	assert_gt(ECSManager.position_of(row).z, before_z + 0.3, "the mover slid along the wall")


func test_entity_vs_entity_collision_pushes_apart() -> void:
	# Entity-vs-entity was specified NOWHERE, which meant nothing could ever be hit.
	var a: int = _spawn(Vector3(10.0, 0.9, 10.0))
	var b: int = _spawn(Vector3(10.2, 0.9, 10.0))
	var row_a: int = EH.index_of(a)
	var row_b: int = EH.index_of(b)
	ECSManager.set_velocity(row_a, Vector3(1.0, 0.0, 0.0))
	_rebuild()
	var total_entity_hits: int = 0
	for _i in 10:
		collision.run(1.0 / 60.0, chunk, hash)
		total_entity_hits += collision.entity_collisions
		_rebuild()
	var separation: float = ECSManager.position_of(row_a).distance_to(ECSManager.position_of(row_b))
	assert_gt(separation, 0.2, "overlapping entities were separated")
	assert_gt(total_entity_hits, 0, "an entity collision was recorded")


func test_mover_steps_up_a_small_ledge() -> void:
	var start: Vector3 = chunk.tile_to_world(39, 45) + Vector3(0.0, 0.9, 0.0)
	var handle: int = _spawn(start)
	var row: int = EH.index_of(handle)
	ECSManager.set_velocity(row, Vector3(2.0, 0.0, 0.0))
	_rebuild()
	for _i in 60:
		collision.run(1.0 / 60.0, chunk, hash)
	assert_gt(
		ECSManager.position_of(row).y,
		start.y + 0.2,
		"the mover climbed onto the %.1f m ledge" % TestArena.LEDGE_HEIGHT_M
	)


func test_query_ray_returns_the_nearest_entity_not_the_first_found() -> void:
	_spawn(Vector3(20.0, 0.9, 5.0), Vector3(0.5, 0.5, 0.5))
	var near: int = _spawn(Vector3(10.0, 0.9, 5.0), Vector3(0.5, 0.5, 0.5))
	_rebuild()
	var result: Dictionary = hash.query_ray(
		Vector3(2.0, 0.9, 5.0), Vector3.RIGHT, 40.0, chunk
	)
	assert_eq(result["entity"], EH.index_of(near), "the closer entity wins")
