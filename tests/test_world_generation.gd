## World generation and the tile sampler (Sprint 2 Step 2).
extends GutTest

const SEED: int = 4242

var grid: WorldGrid


func before_each() -> void:
	grid = WorldGrid.new(SEED)


## A chunk must be a pure function of (seed, chunk_id). Drawing from a shared RNG stream instead
## would make contents depend on the ORDER chunks were visited, so the same cave would differ
## depending on which corridor you walked down first — and ADR-1's promise that unvisited content
## regenerates from its seed would simply be false.
func test_a_chunk_is_the_same_however_you_reach_it() -> void:
	var target := Vector3i(2, -3, -1)

	var direct: ChunkData = FloorGenerator.generate(target, SEED)
	# Generate a pile of unrelated chunks first, to advance any shared stream that might exist.
	for i in 10:
		FloorGenerator.generate(Vector3i(i, i * 3, -2), SEED)
	var after_detour: ChunkData = FloorGenerator.generate(target, SEED)

	assert_eq(
		direct.tile_map, after_detour.tile_map, "visit order cannot change a chunk's contents"
	)


func test_different_chunks_differ_and_different_seeds_differ() -> void:
	var a: ChunkData = FloorGenerator.generate(Vector3i(0, 0, -1), SEED)
	var b: ChunkData = FloorGenerator.generate(Vector3i(1, 0, -1), SEED)
	var c: ChunkData = FloorGenerator.generate(Vector3i(0, 0, -1), SEED + 1)
	assert_ne(a.tile_map, b.tile_map, "neighbouring chunks are not clones")
	assert_ne(a.tile_map, c.tile_map, "a different world seed builds a different chunk")


## Axis factors must not alias, or transposed coordinates hash to the same chunk.
func test_transposed_coordinates_are_not_the_same_chunk() -> void:
	var a: ChunkData = FloorGenerator.generate(Vector3i(1, 2, -1), SEED)
	var b: ChunkData = FloorGenerator.generate(Vector3i(2, 1, -1), SEED)
	assert_ne(a.tile_map, b.tile_map, "(1,2) and (2,1) are different places")


## Every chunk opens the middle of all four edges, at the same coordinate, so neighbours join
## without either side inspecting the other.
func test_every_chunk_opens_its_four_edge_gates() -> void:
	for chunk_id in [Vector3i(0, 0, -1), Vector3i(3, 7, -2), Vector3i(-2, 1, 0)]:
		var chunk: ChunkData = FloorGenerator.generate(chunk_id, SEED)
		var gate: int = FloorGenerator.EDGE_GATE
		var last: int = WorldConstants.CHUNK_TILES - 1
		assert_false(chunk.is_solid(0, gate), "%s west gate open" % chunk_id)
		assert_false(chunk.is_solid(last, gate), "%s east gate open" % chunk_id)
		assert_false(chunk.is_solid(gate, 0), "%s north gate open" % chunk_id)
		assert_false(chunk.is_solid(gate, last), "%s south gate open" % chunk_id)


## Connectivity is guaranteed BY CONSTRUCTION — rooms are chained and the gates are corridored to
## the centre — so a flood fill from one gate must reach all three others. A floor with an
## unreachable exit is unplayable and the failure is silent without this.
func test_all_four_gates_are_mutually_reachable() -> void:
	var gate: int = FloorGenerator.EDGE_GATE
	var last: int = WorldConstants.CHUNK_TILES - 1
	for chunk_id in [Vector3i(0, 0, -1), Vector3i(5, -4, -3), Vector3i(-1, 2, -2)]:
		var chunk: ChunkData = FloorGenerator.generate(chunk_id, SEED)
		var reached: Dictionary = _flood(chunk, Vector2i(0, gate))
		for target in [Vector2i(last, gate), Vector2i(gate, 0), Vector2i(gate, last)]:
			assert_true(
				reached.has(target), "%s: gate %s is reachable from the west gate" % [chunk_id, target]
			)


## The village must exist in memory the instant boot finishes: Pre-Warm runs AI pathfinding
## across it, and pathing into a chunk that does not exist yet is a crash, not a stall.
func test_the_village_is_generated_synchronously_and_dungeons_are_not() -> void:
	grid.generate_village()
	for chunk_id in grid.village_chunk_ids():
		assert_true(grid.has_chunk(chunk_id), "village chunk %s is resident" % chunk_id)
		assert_eq(
			grid.chunk_at(chunk_id).state,
			ECSEnums.LoD.SIMULATED,
			"and is ready for Pre-Warm rather than paying full Active cost"
		)
	assert_false(grid.has_chunk(Vector3i(0, 0, -3)), "a dungeon floor costs nothing until asked")


func test_a_dungeon_chunk_generates_on_demand() -> void:
	grid.generate_village()
	var before: int = grid.chunks_generated
	var chunk: ChunkData = grid.chunk_at(Vector3i(0, 0, -3))
	assert_not_null(chunk, "asking for a dungeon chunk produces one")
	assert_eq(grid.chunks_generated, before + 1, "exactly one chunk was generated")
	assert_eq(grid.chunk_at(Vector3i(0, 0, -3)), chunk, "and asking again reuses it")


# --- The tile sampler ----------------------------------------------------------------------

## THE reason the sampler exists. Sprint 1 handed collision a single ChunkData, so a position one
## metre past the chunk edge produced an out-of-range tile that read as solid and stopped the
## mover dead on the seam.
func test_the_grid_resolves_positions_beyond_one_chunk() -> void:
	grid.generate_village()
	var beyond: Vector3 = Vector3(WorldConstants.CHUNK_SIZE_M + 5.0, 0.0, 5.0)

	var lone: ChunkData = grid.chunk_at(Vector3i.ZERO)
	assert_false(lone.contains_world(beyond), "a lone chunk cannot answer for its neighbour")
	assert_true(lone.solid_at_world(beyond), "and conservatively calls the outside solid")

	assert_true(grid.contains_world(beyond), "the grid always can")
	assert_eq(
		grid.chunk_id_for(beyond, 0), Vector3i(1, 0, 0), "and resolves it to the right chunk"
	)


func test_negative_coordinates_resolve_to_the_correct_chunk() -> void:
	# Integer truncation rounds toward zero, so -0.5 would land in chunk 0 rather than -1. The
	# whole west and north half of the world depends on this being a floor, not a truncation.
	assert_eq(grid.chunk_id_for(Vector3(-0.5, 0.0, -0.5), 0), Vector3i(-1, -1, 0))
	assert_eq(grid.chunk_id_for(Vector3(-64.5, 0.0, 0.5), 0), Vector3i(-2, 0, 0))


func test_the_sampler_agrees_with_the_chunk_it_delegates_to() -> void:
	grid.generate_village()
	var chunk: ChunkData = grid.chunk_at(Vector3i.ZERO)
	for tile in [Vector2i(1, 1), Vector2i(32, 32), Vector2i(20, 45)]:
		var world: Vector3 = chunk.tile_to_world(tile.x, tile.y)
		assert_eq(
			grid.solid_at_world(world),
			chunk.is_solid(tile.x, tile.y),
			"grid and chunk agree on solidity at %s" % tile
		)


# --- Spatial anchors -------------------------------------------------------------------------

func test_every_faction_gets_a_distinct_anchor() -> void:
	RNGService.reseed_all(SEED)
	var generator := DAGGenerator.new()
	generator.run_history_generation()
	var factions: Array[DAGNode] = generator.active_factions()
	grid.assign_anchors(factions)

	var seen: Dictionary = {}
	for node in factions:
		assert_true(node.has_anchor(), "%s was given an anchor" % node.name)
		assert_false(seen.has(node.anchor_chunk_id), "%s does not share an anchor" % node.name)
		seen[node.anchor_chunk_id] = true


## The GESTALT FIX from the roadmap, stated as an assertion: nobody spawns at the origin by
## accident. The village is there ON PURPOSE, and everyone else is somewhere else.
func test_only_the_village_anchors_at_the_origin() -> void:
	RNGService.reseed_all(SEED)
	var generator := DAGGenerator.new()
	generator.run_history_generation()
	var factions: Array[DAGNode] = generator.active_factions()
	grid.assign_anchors(factions)

	for node in factions:
		if node.tags.has(&"SurfaceVillage"):
			assert_eq(node.anchor_chunk_id, Vector3i.ZERO, "the village owns the origin")
		else:
			assert_ne(node.anchor_chunk_id, Vector3i.ZERO, "%s is elsewhere" % node.name)
		assert_eq(
			node.anchor_chunk_id.z, node.home_floor, "%s is anchored on its own floor" % node.name
		)


func test_assigning_anchors_twice_does_not_move_anyone() -> void:
	RNGService.reseed_all(SEED)
	var generator := DAGGenerator.new()
	generator.run_history_generation()
	var factions: Array[DAGNode] = generator.active_factions()
	grid.assign_anchors(factions)
	var first: Array = factions.map(func(n: DAGNode) -> Vector3i: return n.anchor_chunk_id)
	grid.assign_anchors(factions)
	var second: Array = factions.map(func(n: DAGNode) -> Vector3i: return n.anchor_chunk_id)
	assert_eq(second, first, "re-running anchor assignment is idempotent")


## The renderer must draw the whole visible neighbourhood, not just the chunk the player stands
## in. Drawing only `active_chunk` was correct for one room and wrong for a village of nine: the
## other eight were invisible, so the world ended in a cliff two steps from spawn.
func test_the_renderer_draws_more_than_the_players_own_chunk() -> void:
	GameLoopManager.set_physics_process(false)
	World.boot_scenario(World.SCENARIO_WORLD, SEED)
	var terrain: TerrainView = TerrainView.new()
	add_child_autofree(terrain)
	assert_gt(terrain.visible_chunks().size(), 1, "the neighbours are drawn too")
	GameLoopManager.set_physics_process(true)


## It must draw only chunks that ALREADY exist. Asking the grid would generate the entire
## neighbourhood purely to render it, which is the opposite of streaming.
func test_the_renderer_does_not_generate_chunks_just_to_draw_them() -> void:
	GameLoopManager.set_physics_process(false)
	World.boot_scenario(World.SCENARIO_WORLD, SEED)
	var terrain: TerrainView = TerrainView.new()
	add_child_autofree(terrain)
	var before: int = World.grid.chunks_generated
	terrain.visible_chunks()
	assert_eq(World.grid.chunks_generated, before, "rendering generated nothing new")
	GameLoopManager.set_physics_process(true)


## Breadth-first flood over open tiles, returning every tile reached.
func _flood(chunk: ChunkData, start: Vector2i) -> Dictionary:
	var seen: Dictionary = {}
	if chunk.is_solid(start.x, start.y):
		return seen
	var queue: Array[Vector2i] = [start]
	seen[start] = true
	while not queue.is_empty():
		var here: Vector2i = queue.pop_back()
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = here + step
			if seen.has(next) or not chunk.in_bounds(next.x, next.y):
				continue
			if chunk.is_solid(next.x, next.y):
				continue
			seen[next] = true
			queue.append(next)
	return seen
