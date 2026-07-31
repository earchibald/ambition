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


## Bullet-time and the inspector shared one key, which is why the inspector was unreachable.
func test_inspect_and_slow_time_are_separate_actions() -> void:
	assert_true(InputMap.has_action(&"inspect"), "inspect is mapped")
	assert_true(InputMap.has_action(&"slow_time"), "slow_time is mapped separately")
