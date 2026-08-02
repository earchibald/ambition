## Stairs and floor transitions.
##
## Until this existed, dungeon floors generated on demand and nothing could reach them: the whole
## world below the surface was unreachable, so everything about it was untestable.
extends GutTest

const SEED: int = 4141


func before_each() -> void:
	GameLoopManager.set_physics_process(false)
	World.boot_scenario(World.SCENARIO_WORLD, SEED)


func after_all() -> void:
	GameLoopManager.set_physics_process(true)


func _stand_on(tile: Vector2i) -> void:
	var ground: Vector3 = World.active_chunk.tile_to_world(tile.x, tile.y)
	ECSManager.set_position(0, Vector3(ground.x, ground.y + 0.9, ground.z))


# --- Generation -------------------------------------------------------------------------------

## The surface has a way DOWN and no way up; the deepest floor has a way up and no way down.
## Otherwise the stairwell either dead-ends or opens onto a floor nobody lives on.
func test_each_floor_gets_the_stairs_its_depth_allows() -> void:
	var surface: ChunkData = World.grid.chunk_at(Vector3i(0, 0, 0))
	assert_true(_is_stairs(surface, FloorGenerator.STAIR_DOWN_TILE), "the surface goes down")
	assert_false(_is_stairs(surface, FloorGenerator.STAIR_UP_TILE), "and nowhere up")

	var deepest: ChunkData = World.grid.chunk_at(
		Vector3i(0, 0, FloorGenerator.DEEPEST_FLOOR)
	)
	assert_true(_is_stairs(deepest, FloorGenerator.STAIR_UP_TILE), "the bottom goes up")
	assert_false(_is_stairs(deepest, FloorGenerator.STAIR_DOWN_TILE), "and no deeper")

	var middle: ChunkData = World.grid.chunk_at(Vector3i(0, 0, -2))
	assert_true(_is_stairs(middle, FloorGenerator.STAIR_UP_TILE), "a middle floor goes up")
	assert_true(_is_stairs(middle, FloorGenerator.STAIR_DOWN_TILE), "and down")


## THE CARVE-ORDER TRAP. `_carve_corridor` writes TILE_OPEN over everything it touches, so
## carving after placing erased the stairs it was carving toward. The transition kept working
## because it keys on tile POSITION, so the tile silently reverted to plain floor and nothing
## complained — the map and the cursor readout were simply wrong.
func test_the_stair_tiles_survive_the_corridor_carving() -> void:
	for floor_index in range(0, FloorGenerator.DEEPEST_FLOOR - 1, -1):
		var chunk: ChunkData = World.grid.chunk_at(Vector3i(0, 0, floor_index))
		if floor_index > FloorGenerator.DEEPEST_FLOOR:
			assert_true(
				_is_stairs(chunk, FloorGenerator.STAIR_DOWN_TILE),
				"floor %d keeps its down-stair tile" % floor_index
			)


## A stairwell inside a wall is one nobody can stand on, and it reads as the stairs being broken.
func test_the_ground_around_a_stairwell_is_walkable() -> void:
	for floor_index in [0, -1, -3]:
		var chunk: ChunkData = World.grid.chunk_at(Vector3i(0, 0, floor_index))
		for tile in [FloorGenerator.STAIR_DOWN_TILE, FloorGenerator.STAIR_UP_TILE]:
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					assert_false(
						chunk.is_solid(tile.x + dx, tile.y + dy),
						"floor %d: %s+(%d,%d) is standable" % [floor_index, tile, dx, dy]
					)


func test_stairs_only_exist_on_the_landing_chunk() -> void:
	var neighbour: ChunkData = World.grid.chunk_at(Vector3i(1, 0, -1))
	assert_false(
		_is_stairs(neighbour, FloorGenerator.STAIR_DOWN_TILE),
		"an ordinary chunk has no stairwell"
	)


# --- Using them --------------------------------------------------------------------------------

func test_standing_on_a_stair_is_detected() -> void:
	_stand_on(FloorGenerator.STAIR_DOWN_TILE)
	assert_eq(World.stairs_under(0), -1, "the down-stair leads down")
	_stand_on(Vector2i(10, 10))
	assert_eq(World.stairs_under(0), 0, "ordinary floor leads nowhere")


func test_descending_and_climbing_back_returns_you_to_the_surface() -> void:
	_stand_on(FloorGenerator.STAIR_DOWN_TILE)
	for _step in 5:
		assert_true(World.change_floor(-1), "another floor down")
	assert_eq(World.player_chunk_id.z, FloorGenerator.DEEPEST_FLOOR, "reached the bottom")
	assert_false(World.change_floor(-1), "and cannot go deeper")

	for _step in 5:
		assert_true(World.change_floor(1), "another floor up")
	assert_eq(World.player_chunk_id.z, 0, "back on the surface")
	assert_false(World.change_floor(1), "and cannot climb into the sky")


## Arriving on the stair you left by puts you on a tile that sends you straight back.
func test_you_arrive_at_the_opposite_stair() -> void:
	_stand_on(FloorGenerator.STAIR_DOWN_TILE)
	World.change_floor(-1)
	var tile: Vector2i = World.active_chunk.world_to_tile(ECSManager.position_of(0))
	assert_eq(tile, FloorGenerator.STAIR_UP_TILE, "descending lands you on the way back up")


## The SAMPLER must move with the player. Collision and picking resolve terrain through it, and a
## frame spent sampling the old floor while standing on the new one is a frame inside a wall.
func test_the_terrain_sampler_follows_you_between_floors() -> void:
	_stand_on(FloorGenerator.STAIR_DOWN_TILE)
	World.change_floor(-1)
	assert_eq(World.grid.current_floor, -1, "the grid answers for the new floor")
	assert_eq(World.player_chunk_id.z, -1, "and so does the player's chunk id")
	assert_eq(World.active_chunk.chunk_id.z, -1, "and the active chunk")


func test_the_players_recorded_floor_moves_with_them() -> void:
	_stand_on(FloorGenerator.STAIR_DOWN_TILE)
	World.change_floor(-1)
	assert_eq(ECSManager.chunk_id_of(0).z, -1, "the ECS knows which floor you are on")


# --- The floor-stacking hazard -------------------------------------------------------------------

## FLOORS STACK AT THE SAME WORLD X AND Z. The floor index lives in `chunk_id.z`, not in the Y
## coordinate, so an entity upstairs can occupy the identical world position as one downstairs.
## The spatial hash is 2D and cannot tell them apart, so without a floor filter a villager on the
## surface collides with you underground, is picked by your cursor, and is perceived through rock.
func test_the_spatial_query_is_filtered_by_floor() -> void:
	var villagers: Array[int] = FactionPlanner.members_of(1)
	assert_gt(villagers.size(), 0, "the village has people")

	var upstairs: PackedInt32Array = ECSManager.rows_on_floor(ComponentMask.SPATIAL, 0)
	assert_gt(upstairs.size(), 1, "the surface is populated")

	var downstairs: PackedInt32Array = ECSManager.rows_on_floor(ComponentMask.SPATIAL, -1)
	for row in downstairs:
		assert_eq(ECSManager.chunk_id_of(row).z, -1, "only floor -1 entities are returned")
	assert_false(
		upstairs.has(villagers[0]) and downstairs.has(villagers[0]),
		"nobody is on two floors at once"
	)


## After descending, the surface crowd must not be in your collision neighbourhood.
func test_the_surface_crowd_is_left_behind_when_you_descend() -> void:
	_stand_on(FloorGenerator.STAIR_DOWN_TILE)
	World.change_floor(-1)
	var here: PackedInt32Array = ECSManager.rows_on_floor(
		ComponentMask.SPATIAL, World.player_chunk_id.z
	)
	for row in here:
		assert_eq(
			ECSManager.chunk_id_of(row).z, -1, "everything queryable underground IS underground"
		)


func _is_stairs(chunk: ChunkData, tile: Vector2i) -> bool:
	return chunk.tile_map[WorldConstants.cell_index(tile.x, tile.y)] == ChunkData.TILE_STAIRS
