## Utility AI, the job latch, memory decay, and schedules.
extends GutTest

var jobs: JobResolutionSystem
var spawned: PackedInt64Array = PackedInt64Array()


func before_each() -> void:
	jobs = JobResolutionSystem.new()
	spawned = PackedInt64Array()


func after_each() -> void:
	for i in spawned.size():
		ECSManager.destroy_entity(spawned[i])


func _spawn_agent(hunger: float, energy: float) -> int:
	var handle: int = ECSManager.allocate_entity()
	var row: int = EH.index_of(handle)
	var need := NeedsComponent.new()
	need.hunger = hunger
	need.energy = energy
	ECSManager.needs[row] = need
	ECSManager.add_component_bit(row, ComponentMask.NEEDS)
	ECSManager.schedules[row] = ScheduleComponent.new()
	ECSManager.add_component_bit(row, ComponentMask.SCHEDULE)
	spawned.append(handle)
	return handle


# --- The unreachable-branch bug ----------------------------------------------------------------


## THE REGRESSION GUARD. Under the old if/elif ladder, an agent at hunger 76 / energy 0 returned
## Consume forever and could NEVER sleep, because Sleep required hunger to be low first.
func test_exhausted_and_hungry_agent_can_still_choose_sleep() -> void:
	var handle: int = _spawn_agent(85.0, 0.0)
	var row: int = EH.index_of(handle)
	var scores: Dictionary = jobs.score_actions(row, ECSManager.needs[row])
	assert_gt(scores[ActionIntent.SLEEP], 0.0, "sleep is reachable while also hungry")
	assert_gt(scores[ActionIntent.CONSUME], 0.0, "eating is also on the table")
	# Both compete on one scale rather than one unconditionally masking the other.
	assert_true(
		scores[ActionIntent.SLEEP] > 0.0 and scores[ActionIntent.CONSUME] > 0.0,
		"the two urgencies coexist instead of forming a fixed priority ladder"
	)


func test_a_content_agent_prefers_work() -> void:
	var handle: int = _spawn_agent(10.0, 95.0)
	var row: int = EH.index_of(handle)
	var scores: Dictionary = jobs.score_actions(row, ECSManager.needs[row])
	assert_gt(scores[ActionIntent.WORK], scores[ActionIntent.CONSUME], "work beats eating")
	assert_gt(scores[ActionIntent.WORK], scores[ActionIntent.SLEEP], "work beats sleeping")


func test_a_starving_agent_prefers_eating() -> void:
	var handle: int = _spawn_agent(99.0, 95.0)
	var row: int = EH.index_of(handle)
	var scores: Dictionary = jobs.score_actions(row, ECSManager.needs[row])
	assert_gt(scores[ActionIntent.CONSUME], scores[ActionIntent.WORK], "hunger wins when severe")


# --- Hysteresis and the latch ------------------------------------------------------------------


## Without hysteresis, an agent sitting on a threshold flips action every single tick.
func test_hysteresis_sustains_eating_below_the_enter_threshold() -> void:
	var handle: int = _spawn_agent(85.0, 90.0)
	var row: int = EH.index_of(handle)
	jobs.run(1)
	var job: JobComponent = ECSManager.jobs[row]
	assert_eq(job.current_action, ActionIntent.CONSUME, "the agent starts eating")

	# Drop hunger below the ENTER threshold but above the EXIT threshold.
	ECSManager.needs[row].hunger = 50.0
	var scores: Dictionary = jobs.score_actions(row, ECSManager.needs[row])
	assert_gt(
		scores[ActionIntent.CONSUME],
		0.0,
		"eating remains attractive between the exit and enter thresholds"
	)


## THE NAVBRIDGE GUARD. Without a latch the evaluator re-issues an intent — and a path request —
## every Simulation tick, which at 1,500 agents is 3,000 requests/s against a 300/s budget.
func test_job_latch_prevents_re_issuing_every_tick() -> void:
	var handle: int = _spawn_agent(99.0, 90.0)
	var row: int = EH.index_of(handle)
	jobs.run(1)
	var first_action: StringName = ECSManager.jobs[row].current_action
	assert_true(ECSManager.jobs[row].is_latched(), "the claimed job is latched")

	var retained: int = 0
	for tick in range(2, 20):
		jobs.run(tick)
		retained += jobs.latched_retained
	assert_gt(retained, 10, "the latch held across many ticks instead of re-deciding each one")
	assert_eq(
		ECSManager.jobs[row].current_action, first_action, "the action did not thrash"
	)


func test_precondition_failure_puts_the_action_on_cooldown() -> void:
	var handle: int = _spawn_agent(99.0, 90.0)
	var row: int = EH.index_of(handle)
	jobs.run(1)
	assert_eq(ECSManager.jobs[row].current_action, ActionIntent.CONSUME, "starts by eating")

	# No food anywhere: the action must become unavailable rather than looping forever.
	jobs.mark_precondition_failed(row, ActionIntent.CONSUME, 1)
	jobs.run(2)
	assert_ne(
		ECSManager.jobs[row].current_action,
		ActionIntent.CONSUME,
		"an unsatisfiable action is not retried every tick"
	)


func test_dead_claimant_releases_its_job() -> void:
	var handle: int = _spawn_agent(99.0, 90.0)
	var row: int = EH.index_of(handle)
	jobs.run(1)
	jobs.release_jobs_of(row)
	assert_true(ECSManager.jobs[row].is_open(), "the job returned to the pool")
	assert_false(EH.is_valid(ECSManager.jobs[row].claimed_by), "the claimant was cleared")


# --- Schedules -------------------------------------------------------------------------------


func test_schedule_blocks_match_the_canonical_hours() -> void:
	var schedule := ScheduleComponent.new()
	assert_eq(schedule.block_for_hour(2), ScheduleComponent.Block.SLEEP, "02:00 is sleep")
	assert_eq(schedule.block_for_hour(9), ScheduleComponent.Block.WORK, "09:00 is work")
	assert_eq(schedule.block_for_hour(20), ScheduleComponent.Block.LEISURE, "20:00 is leisure")
	assert_eq(schedule.block_for_hour(23), ScheduleComponent.Block.SLEEP, "23:00 is sleep")


# --- Memory ----------------------------------------------------------------------------------


## THE REGRESSION GUARD. An ADDITIVE core bonus drives every core memory to the same weight as
## recency decays, so "top-3 by weight" becomes float-noise ordering. Multiplying preserves the
## relative ordering forever.
func test_core_memories_keep_their_relative_ordering_forever() -> void:
	var murder: MemoryEvent = MemoryEvent.create(&"WITNESSED_MURDER", &"saw a murder", 0, true)
	var meal: MemoryEvent = MemoryEvent.create(&"FED", &"had dinner", 0, true)
	var distant: int = 100000
	assert_gt(
		murder.weight_at(distant),
		meal.weight_at(distant),
		"a core murder still outweighs a core meal after a very long time"
	)


func test_core_memories_decay_to_a_floor_not_to_zero() -> void:
	var core: MemoryEvent = MemoryEvent.create(&"WITNESSED_MURDER", &"x", 0, true)
	var mundane: MemoryEvent = MemoryEvent.create(&"WITNESSED_MURDER", &"x", 0, false)
	var far: int = 10000
	assert_gt(core.weight_at(far), 3.0, "a core memory holds at its floor")
	assert_almost_eq(mundane.weight_at(far), 0.0, 0.01, "a mundane memory decays away")


func test_recent_memories_outweigh_old_ones() -> void:
	var old: MemoryEvent = MemoryEvent.create(&"TRADED", &"x", 0, false)
	var fresh: MemoryEvent = MemoryEvent.create(&"TRADED", &"y", 500, false)
	assert_gt(fresh.weight_at(500), old.weight_at(500), "recency matters")


func test_event_ids_are_unique_and_enable_dedup() -> void:
	var a: MemoryEvent = MemoryEvent.create(&"TRADED", &"x", 0)
	var b: MemoryEvent = MemoryEvent.create(&"TRADED", &"x", 0)
	assert_ne(a.event_id, b.event_id, "each event gets a distinct id")

	var memory := MemoryComponent.new()
	assert_true(memory.remember(a), "first insert succeeds")
	assert_false(memory.remember(a), "the SAME event cannot be gossiped in twice")
	assert_eq(memory.events.size(), 1, "no duplicate stored")


## Unbounded memory plus a unioning gossip loop converges to over a million records.
func test_memory_is_capped() -> void:
	var memory := MemoryComponent.new()
	for i in 200:
		memory.remember(MemoryEvent.create(&"IDLE_CHAT", &"chatter", i, false))
	assert_lte(memory.events.size(), MemoryComponent.MEMORY_CAP, "memory is bounded")


func test_overflow_evicts_mundane_before_core() -> void:
	var memory := MemoryComponent.new()
	var core: MemoryEvent = MemoryEvent.create(&"WITNESSED_MURDER", &"important", 0, true)
	memory.remember(core)
	for i in 200:
		memory.remember(MemoryEvent.create(&"IDLE_CHAT", &"chatter", i, false))
	var kept: bool = false
	for event in memory.events:
		if event.event_id == core.event_id:
			kept = true
	assert_true(kept, "the core memory survived 200 mundane insertions")
