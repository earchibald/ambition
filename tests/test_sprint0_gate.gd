## The Sprint 0 gate from `docs/invariants_and_test_strategy.md` §4, as executable checks.
##
## This file is also the guard against a GUT false positive: if the test runner ever reports
## success while running nothing, these assertions were not executed.
extends GutTest

const REQUIRED_ACTIONS: Array[StringName] = [
	&"move_left",
	&"move_right",
	&"move_forward",
	&"move_back",
	&"interact",
	&"attack",
	&"inspect",
	&"slow_time",
	&"cancel",
]


func test_autoloads_exist_and_are_nodes() -> void:
	for name_and_node in [
		["ECSEvents", ECSEvents], ["ECSManager", ECSManager], ["GameLoopManager", GameLoopManager]
	]:
		assert_not_null(name_and_node[1], "%s autoload exists" % name_and_node[0])
		assert_true(
			name_and_node[1] is Node, "%s must extend Node to be autoloadable" % name_and_node[0]
		)


func test_input_actions_are_mapped() -> void:
	# Input.get_vector() pushes an error every frame on unmapped actions.
	for action in REQUIRED_ACTIONS:
		assert_true(InputMap.has_action(action), "InputMap has action: %s" % action)


func test_physics_tick_is_sixty_hz() -> void:
	# ADR-9. The Simulation and Macro cadences are derived from this by frame count.
	assert_eq(
		Engine.physics_ticks_per_second,
		WorldConstants.MICRO_TICK_HZ,
		"physics tick is the 60Hz Micro metronome"
	)


func test_main_scene_is_configured() -> void:
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene", "")
	assert_eq(main_scene, "res://viewer/Main.tscn", "main scene is set")
	assert_true(ResourceLoader.exists(main_scene), "main scene resource actually exists")


func test_derived_tick_cadences_match_the_adr() -> void:
	assert_eq(
		WorldConstants.SIM_TICK_EVERY_N_MICRO, 30, "Simulation tick is 2Hz (every 30 frames)"
	)
	assert_eq(
		WorldConstants.MACRO_TICK_EVERY_N_MICRO,
		600,
		"Macro tick fires every 10 real seconds (every 600 frames)"
	)
	assert_eq(WorldConstants.FLUID_TICK_EVERY_N_MICRO, 4, "fluids run at 15Hz (ADR-10)")


func test_enums_are_reachable_across_files() -> void:
	# A bare enum in a script without class_name is unreachable from another file.
	assert_eq(ECSEnums.Phase.SOLID, 0, "Phase enum resolves")
	assert_eq(ECSEnums.LoD.ACTIVE, 0, "LoD enum resolves")
	assert_eq(
		ECSEnums.MaterializationPolicy.LEDGERIZE, 0, "MaterializationPolicy enum resolves"
	)


func test_quality_is_derived_from_wear() -> void:
	# Registry §5: condition is a derived band; degradation writes `wear`.
	assert_eq(ECSEnums.quality_from_wear(0.0), ECSEnums.Quality.PRISTINE, "0 wear is pristine")
	assert_eq(ECSEnums.quality_from_wear(30.0), ECSEnums.Quality.CHIPPED, "30 wear is chipped")
	assert_eq(ECSEnums.quality_from_wear(60.0), ECSEnums.Quality.RUINED, "60 wear is ruined")
	assert_eq(ECSEnums.quality_from_wear(99.0), ECSEnums.Quality.SCRAP, "99 wear is scrap")


func test_grid_apron_prevents_row_wrap() -> void:
	# The defect this guards: on a bare 64x64 array, idx+1 at x=63 wraps to the next row and
	# at idx 4095 runs off the end entirely.
	var right_of_east_edge: int = WorldConstants.cell_index(63, 0) + 1
	var apron_cell: int = WorldConstants.cell_index(64, 0)
	assert_eq(right_of_east_edge, apron_cell, "the east neighbour is an apron cell, not a wrap")
	assert_lt(
		WorldConstants.cell_index(64, 64),
		WorldConstants.GRID_CELLS,
		"the far corner's neighbour is still in range"
	)


func test_debug_config_initializes_and_trace_dir_is_writable() -> void:
	# Debugging spec section 9: Sprint 0 must create the debug flag/config and ensure logs are
	# writable under user://.
	DebugFlags.initialize()
	assert_true(
		DirAccess.dir_exists_absolute(DebugFlags.TRACE_DIR),
		"user:// debug trace directory exists and is writable"
	)
	var flags: Dictionary = DebugFlags.snapshot()
	assert_true(flags.has("tick_counters_enabled"), "debug flags snapshot is populated")
	assert_true(
		flags["hard_fail_on_invariant_violation"],
		"debug builds hard-fail on invariant violations by default"
	)
