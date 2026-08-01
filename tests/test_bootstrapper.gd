## The boot sequence (Sprint 2 Step 6).
##
## Order IS the deliverable here, so the order is what is asserted. Every ordering bug in this
## sequence presents as something else entirely — factions at the world origin, a Day 0 collision
## explosion, a time-skip that costs a hundred times what it should — which is exactly why it
## needs tests rather than a comment.
extends GutTest

const SEED: int = 12345

var boot: Bootstrapper


func before_each() -> void:
	GameLoopManager.set_physics_process(false)
	World.boot_scenario(World.SCENARIO_TEST_ARENA, SEED)
	boot = Bootstrapper.new()


func after_all() -> void:
	GameLoopManager.set_physics_process(true)


func test_the_phases_run_in_the_specified_order() -> void:
	boot.execute_boot_sequence(SEED)
	assert_eq(
		boot.phases_run,
		[&"history", &"grid", &"populate", &"pre_warm"] as Array[StringName],
		"history, then grid, then populate, then pre-warm"
	)


## The grid must exist BEFORE the Interregnum, which ages zones that have to be there to age.
func test_the_interregnum_runs_after_the_grid_not_before() -> void:
	boot.execute_boot_sequence(SEED, true)
	var grid_at: int = boot.phases_run.find(&"grid")
	var interregnum_at: int = boot.phases_run.find(&"interregnum")
	assert_gt(interregnum_at, grid_at, "the grid is built before the world is aged")
	assert_gt(
		boot.phases_run.find(&"pre_warm"), interregnum_at, "and Pre-Warm runs after the skip"
	)


func test_a_normal_boot_skips_the_interregnum_entirely() -> void:
	boot.execute_boot_sequence(SEED, false)
	assert_false(boot.phases_run.has(&"interregnum"), "no death, no year-long absence")
	assert_eq(boot.interregnum_months_run, 0, "and no months were aged")


## Twelve COARSE passes, not 8,760 hourly Macro ticks. The fine-grained version is two orders of
## magnitude more expensive and lets hour-scale behaviour fire thousands of times with nobody
## present to interact with it.
func test_the_interregnum_is_twelve_coarse_months() -> void:
	boot.execute_boot_sequence(SEED, true)
	assert_eq(boot.interregnum_months_run, Bootstrapper.INTERREGNUM_MONTHS, "twelve months")
	assert_lt(
		boot.economy.ticks_run,
		8760,
		"and it did NOT degenerate into an hour-by-hour year"
	)


## A year of absence must visibly change the world, or the death loop's central promise — that
## things carried on without you — is a lie.
func test_the_interregnum_actually_ages_the_world() -> void:
	boot.execute_boot_sequence(SEED, false)
	var quiet: int = _total_faction_wealth()

	var aged := Bootstrapper.new()
	World.boot_scenario(World.SCENARIO_TEST_ARENA, SEED)
	aged.execute_boot_sequence(SEED, true)
	assert_gt(_total_faction_wealth(), quiet, "a year away left the factions richer")


func test_pre_warm_runs_the_specified_number_of_ticks() -> void:
	var ticks: Array[bool] = []
	boot.execute_boot_sequence(
		SEED, false, func(pre_warm: bool) -> void: ticks.append(pre_warm)
	)
	assert_eq(ticks.size(), Bootstrapper.PRE_WARM_TICKS, "100 Simulation ticks")


## THE PHYSICS PATCH. Pre-Warm must hand the tick a flag saying "gravity off": items crafted
## during it are placed on display surfaces, and dropping them under gravity spawns them
## interpenetrating so the depenetration pass fires the lot across the room on frame one.
func test_pre_warm_tells_the_tick_to_suppress_gravity() -> void:
	var flags: Array[bool] = []
	boot.execute_boot_sequence(
		SEED, false, func(pre_warm: bool) -> void: flags.append(pre_warm)
	)
	for flag in flags:
		assert_true(flag, "every Pre-Warm tick runs in pre-warm mode")


## And the result: nothing is left mid-air or moving when the player takes control.
func test_pre_warm_leaves_loose_items_at_rest_on_the_ground() -> void:
	boot.execute_boot_sequence(SEED)
	var handle: int = World.spawn_item(
		Vector3(10.0, 12.0, 10.0), MaterialLibrary.MAT_COPPER, 100.0, 1
	)
	var row: int = ECSManager.resolve(handle)
	ECSManager.set_velocity(row, Vector3(5.0, -9.0, 3.0))

	boot._snap_loose_items_to_ground()

	var position: Vector3 = ECSManager.position_of(row)
	var bounds: BoundsComponent = ECSManager.bounds[row]
	assert_almost_eq(
		position.y,
		boot.grid.height_at_world(position) + bounds.half_extents.y,
		0.001,
		"the item rests exactly on its tile rather than hanging above it"
	)
	assert_eq(ECSManager.velocity_of(row), Vector3.ZERO, "and is not moving")
	assert_true(ECSManager.loose_items[row].resting, "and is marked at rest")


## Boot must not spawn anyone at the origin by accident, which is what happens when populate
## runs before the grid has assigned anchors.
func test_every_faction_has_a_real_anchor_by_the_time_it_is_populated() -> void:
	boot.execute_boot_sequence(SEED)
	for node in boot.generator.active_factions():
		assert_true(node.has_anchor(), "%s was anchored before populate" % node.name)


## Same seed, same world. Without this, the soak harness has nothing stable to compare against.
func test_the_same_seed_boots_the_same_world() -> void:
	boot.execute_boot_sequence(SEED)
	var first: String = boot.generator.chronicle_text()

	World.boot_scenario(World.SCENARIO_TEST_ARENA, SEED)
	var second := Bootstrapper.new()
	second.execute_boot_sequence(SEED)
	assert_eq(second.generator.chronicle_text(), first, "identical history")


## Scope doc §7: a cold boot has a 30 second ceiling. Timed HERE rather than inside the
## bootstrapper, because `ecs/` never reads wall-clock (ADR-20).
func test_a_cold_boot_is_inside_its_budget() -> void:
	var started: int = Time.get_ticks_usec()
	boot.execute_boot_sequence(SEED)
	var elapsed: float = float(Time.get_ticks_usec() - started) / 1_000_000.0
	assert_lt(
		elapsed,
		Bootstrapper.COLD_BOOT_BUDGET_S,
		"cold boot took %.2fs against a %.0fs ceiling" % [elapsed, Bootstrapper.COLD_BOOT_BUDGET_S]
	)
	gut.p("cold boot: %.3fs" % elapsed)


func _total_faction_wealth() -> int:
	var total: int = 0
	for row in ECSManager.query(ComponentMask.FACTION_CORE):
		total += ECSManager.faction_cores[row].ledger_total()
	return total


## The Pre-Warm's ROADMAP SUCCESS STATE, asserted against the production boot: "when the player
## gains camera control, NPCs are already working". The old test injected its own callable and
## proved the injection point; the shipped boot passed nothing, so zero ticks ran and the
## counter still read 100. This asserts the visible consequence, which no injection can fake.
func test_the_shipped_boot_prewarms_so_npcs_are_already_working() -> void:
	World.boot_scenario(World.SCENARIO_WORLD, SEED)
	# Evidence only SIMULATION TICKS can produce: hunger accrues at 0.139 per tick, so 100
	# Pre-Warm ticks leave every citizen visibly hungrier than a fresh spawn. Job assignment is
	# NOT usable as evidence — the boot-time planner pass hands out jobs with zero ticks run,
	# which is exactly how the first version of this test let an unwired Pre-Warm survive a
	# mutation run.
	var hungriest: float = 0.0
	for row in ECSManager.query(ComponentMask.NEEDS):
		if row == WorldConstants.PLAYER_INDEX:
			continue
		hungriest = maxf(hungriest, ECSManager.needs[row].hunger)
	assert_gt(hungriest, 5.0, "the village is mid-routine before the player's first frame")
	assert_eq(
		World.grid.chunk_at(Vector3i.ZERO).claim_faction_id,
		_origin_faction_id(),
		"and the village chunk is CLAIMED by its faction — the ClaimTag is set in production"
	)


func _origin_faction_id() -> int:
	for row in ECSManager.query(ComponentMask.FACTION_CORE):
		var core: FactionCoreComponent = ECSManager.faction_cores[row]
		if core.anchor_chunk_id == Vector3i.ZERO:
			return core.faction_id
	return -1
