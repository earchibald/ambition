## Sprint 3's performance gates (declared gap G-6 / scope doc §7).
##
## The scope doc marks these budgets "enforced by test" and no test enforced them. Budgets that
## are not assertions are aspirations; every number here fails the build when it regresses.
extends GutTest

const SEED: int = 303

## Scope doc §7: "Debug scenario -> controllable <= 2 s. This is the number that governs daily
## life." The cheaper and more frequently-paid of the two boot budgets was the unguarded one.
const ARENA_BOOT_BUDGET_S: float = 2.0

## Scope doc §5: death -> respawn <= 5 s. The whole loop: death, Interregnum, successor.
const RESPAWN_BUDGET_S: float = 5.0


func after_all() -> void:
	GameLoopManager.set_physics_process(true)


func test_the_debug_arena_boots_inside_its_two_second_budget() -> void:
	GameLoopManager.set_physics_process(false)
	var start: int = Time.get_ticks_usec()
	World.boot_scenario(World.SCENARIO_TEST_ARENA, SEED)
	var seconds: float = float(Time.get_ticks_usec() - start) / 1_000_000.0
	assert_lt(seconds, ARENA_BOOT_BUDGET_S, "arena boot took %.3f s" % seconds)


func test_death_to_respawn_completes_inside_five_seconds() -> void:
	GameLoopManager.set_physics_process(false)
	World.boot_scenario(World.SCENARIO_WORLD, SEED)
	var deaths := DeathLoopSystem.new()
	var generator: DAGGenerator = World.boot_report.generator

	var start: int = Time.get_ticks_usec()
	ECSManager.bodies[WorldConstants.PLAYER_INDEX].health = 0.0
	deaths.on_player_death(EH.INVALID, generator)
	deaths.run_interregnum(World.boot_report, World.grid)
	deaths.spawn_successor(World.grid.chunk_at(Vector3i.ZERO), LineageJournal.load_journal())
	var seconds: float = float(Time.get_ticks_usec() - start) / 1_000_000.0

	assert_lt(seconds, RESPAWN_BUDGET_S, "death -> respawn took %.3f s" % seconds)
	assert_true(ECSManager.bodies[WorldConstants.PLAYER_INDEX].is_alive())
	LineageJournal.erase()


## The reasoning pump must fit inside the frame that hosts the Macro tick. A full queue served
## by the heuristic provider is the worst local case; it must not blow the 8 ms Micro budget.
func test_a_full_reasoning_queue_pumps_inside_the_micro_budget() -> void:
	GameLoopManager.set_physics_process(false)
	World.boot_scenario(World.SCENARIO_WORLD, SEED)
	var queue := ReasoningQueue.new()
	var generator: DAGGenerator = World.boot_report.generator
	for row in ECSManager.query(ComponentMask.FACTION_CORE):
		queue.submit(ECSManager.handle_of(row))

	var worst_ms: float = 0.0
	while queue.pending_count() > 0:
		var start: int = Time.get_ticks_usec()
		queue.pump(generator, func(_h: int, _r: Dictionary) -> void: pass)
		worst_ms = maxf(worst_ms, float(Time.get_ticks_usec() - start) / 1000.0)
	assert_lt(
		worst_ms, WorldConstants.MICRO_BUDGET_MS,
		"worst single pump was %.2f ms against the %d ms budget"
		% [worst_ms, int(WorldConstants.MICRO_BUDGET_MS)]
	)
