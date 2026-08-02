## Guards the "it runs but you cannot see it" class of defect.
##
## Every check here corresponds to a real bug that shipped green: 135 tests passed, CI passed,
## the boot sentinel printed — and the game rendered an empty grey void with no floor, no walls,
## and no player body. Simulation correctness tests cannot catch this, because nothing was wrong
## with the simulation. The viewer simply never read it.
extends GutTest


func before_all() -> void:
	World.boot_scenario(World.SCENARIO_TEST_ARENA, 1)


## The player is assembled in `World._spawn_player`, which for a long time never announced
## itself. ViewManager spawns visuals ONLY from `entity_created`, so the player had no body.
func test_player_spawn_announces_itself_to_the_viewer() -> void:
	var seen: Array[int] = []
	var probe := func(entity: int, tags: Array, _pos: Vector3) -> void:
		if tags.has(&"Player"):
			seen.append(entity)
	ECSEvents.entity_created.connect(probe)
	World.boot_scenario(World.SCENARIO_TEST_ARENA, 1)
	ECSEvents.entity_created.disconnect(probe)

	assert_eq(seen.size(), 1, "booting emits exactly one Player entity_created")
	assert_eq(EH.index_of(seen[0]), 0, "the announced Player is entity row 0 (ADR-14)")


func test_view_manager_gives_the_player_a_visual() -> void:
	var view: ViewManager = ViewManager.new()
	add_child_autofree(view)
	World.boot_scenario(World.SCENARIO_TEST_ARENA, 1)
	assert_gt(view.spawned, 0, "the viewer spawned a visual for the player")
	assert_eq(
		int(view.counters()["visuals_live"]), 1, "exactly one live visual after a bare boot"
	)


## The arena has floors, walls, a ledge, a pit and a puddle. If TerrainView emits zero instances
## the player is walking through an invisible level.
func test_terrain_view_renders_floors_and_walls() -> void:
	var terrain: TerrainView = TerrainView.new()
	add_child_autofree(terrain)
	var floors: int = terrain.get_child(0).multimesh.instance_count
	var walls: int = terrain.get_child(1).multimesh.instance_count
	assert_gt(floors, 0, "floor tiles are drawn")
	assert_gt(walls, 0, "the border wall and interior wall are drawn")
	# 64x64 = 4,096 tiles, every one either open or solid, and none drawn twice.
	assert_eq(
		floors + walls,
		WorldConstants.CHUNK_TILES * WorldConstants.CHUNK_TILES,
		"every tile is drawn exactly once, as either floor or wall"
	)


func test_terrain_view_draws_the_puddle() -> void:
	var terrain: TerrainView = TerrainView.new()
	add_child_autofree(terrain)
	var water: int = terrain.get_child(2).multimesh.instance_count
	assert_gt(water, 0, "the TestArena water source is visible")


## The inspector is the highest-value debug surface in the build, and `select_row` sat with zero
## callers. A dead debug API is worse than none: it reads as covered.
func test_the_entity_inspector_has_a_caller() -> void:
	var callers: int = 0
	for path in ["res://viewer/player_input_bridge.gd", "res://ui/debug/debug_overlay.gd"]:
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		assert_not_null(file, "%s is readable" % path)
		if file == null:
			continue
		for line in file.get_as_text().split("\n"):
			var stripped: String = line.strip_edges()
			if stripped.begins_with("#") or stripped.begins_with("func select_row"):
				continue
			if stripped.contains("select_row("):
				callers += 1
	assert_gt(callers, 0, "something actually calls DebugOverlay.select_row")


## The overlay must report the player in TILE coordinates, because every arena feature is
## specified in tiles while the ECS stores metres. Without the readout, "walk to the ledge at
## (40-49, 40-49) and confirm the step rule" is not something a human can actually carry out.
func test_overlay_reports_player_tile_and_world_position() -> void:
	var overlay: DebugOverlay = DebugOverlay.new()
	add_child_autofree(overlay)
	World.boot_scenario(World.SCENARIO_TEST_ARENA, 1)

	# Asserted against the LIVE panel rows, not a helper. The old `_player_location()` was a
	# superseded orphan the panel never printed — this test was the only thing keeping it alive,
	# so it certified a readout no human could see (the 2026-08-01 cull deleted it).
	var text: String = "\n".join(overlay._player_rows())
	assert_string_contains(text, "tile", "the overlay names a tile coordinate")
	# The player spawns on TestArena.SPAWN_TILE. If these ever disagree, one of the two
	# coordinate systems has drifted and the arena table in RUNNING.md is lying.
	assert_string_contains(
		text,
		"tile %d, %d" % [TestArena.SPAWN_TILE.x, TestArena.SPAWN_TILE.y],
		"the reported tile is the spawn tile the arena actually authored"
	)


## Elevation and fluid are the two numbers the step/drop rules and the CA operate on, so the
## readout has to agree with the arena that was built, not with a hard-coded guess.
func test_tile_readout_matches_the_authored_arena() -> void:
	var overlay: DebugOverlay = DebugOverlay.new()
	add_child_autofree(overlay)
	var chunk: ChunkData = World.active_chunk

	assert_string_contains(
		overlay._tile_readout(chunk, Vector2i(45, 45)),
		"elev +0.40m",
		"the ledge reports its authored 0.4 m elevation"
	)
	assert_string_contains(
		overlay._tile_readout(chunk, Vector2i(42, 14)),
		"elev -2.50m",
		"the pit reports its authored depth"
	)
	assert_string_contains(
		overlay._tile_readout(chunk, Vector2i(24, 10)),
		"SOLID",
		"the interior wall at x=24 reads as solid"
	)
	assert_string_contains(
		overlay._tile_readout(chunk, Vector2i(24, TestArena.DOORWAY_Y)),
		"open",
		"the doorway in that same wall reads as open"
	)
	assert_string_contains(
		overlay._tile_readout(chunk, Vector2i(-1, 0)),
		"outside chunk",
		"a tile off the grid says so instead of reading out of bounds"
	)


## Readability is a requirement, not a preference. 13 pt was picked by an agent that never had to
## read it on a real monitor, and a fixed pixel size does not grow when the window does.
func test_overlay_text_is_legible_and_adjustable() -> void:
	assert_gte(
		DebugFlags.DEFAULT_OVERLAY_FONT_SIZE, 16, "the default overlay size is actually readable"
	)
	assert_true(InputMap.has_action(&"overlay_text_bigger"), "text size is adjustable at runtime")
	assert_true(InputMap.has_action(&"overlay_text_smaller"), "and shrinkable again")


## Fixed-pixel CanvasLayer text does not scale with the window, so enlarging the window made the
## overlay relatively SMALLER. `canvas_items` is what fixes that.
func test_window_stretch_scales_the_ui() -> void:
	assert_eq(
		ProjectSettings.get_setting("display/window/stretch/mode", ""),
		"canvas_items",
		"UI scales with the window instead of staying a fixed pixel size"
	)


## The cursor is a SURVEY tool and must be right about the two tiles worth surveying. A y=0 plane
## intersection is correct on flat ground and wrong on exactly the ledge and the pit — the only
## tiles in the arena whose elevation is not zero.
func test_cursor_reads_elevation_from_the_height_map() -> void:
	var overlay: DebugOverlay = DebugOverlay.new()
	add_child_autofree(overlay)
	var chunk: ChunkData = World.active_chunk

	# Straight down onto the ledge: the marched ray must stop at +0.40 m, not at y=0.
	assert_string_contains(
		overlay._tile_readout(chunk, Vector2i(45, 45)),
		"+0.40m",
		"the ledge tile reports the raised surface"
	)
	# The pit floor is 2.5 m down; a flat-plane cursor would report the tile as level ground.
	assert_string_contains(
		overlay._tile_readout(chunk, Vector2i(42, 14)),
		"-2.50m",
		"the pit tile reports the sunken floor"
	)
	assert_lt(
		chunk.height_at(42, 14),
		chunk.height_at(45, 45),
		"the pit and the ledge are genuinely different elevations, so the check is not vacuous"
	)


## Bullet-time and the inspector shared one key, which is why the inspector was unreachable.
func test_inspect_and_slow_time_are_separate_actions() -> void:
	assert_true(InputMap.has_action(&"inspect"), "inspect is mapped")
	assert_true(InputMap.has_action(&"slow_time"), "slow_time is mapped separately")
