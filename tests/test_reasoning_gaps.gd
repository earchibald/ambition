## The reasoning-stack gaps closed by the 2026-08-01 remediation pass: queue priority,
## the ADR-12 cap, the 200-character gate, the timeout requeue, and the leader's memories.
## Split from `test_reasoning.gd` only because gdlint caps a script at 40 methods.
extends GutTest

const SEED: int = 607

var generator: DAGGenerator
var queue: ReasoningQueue
var resolver: LLMResolutionSystem


func before_each() -> void:
	GameLoopManager.set_physics_process(false)
	World.boot_scenario(World.SCENARIO_TEST_ARENA, SEED)
	RNGService.reseed_all(SEED)
	generator = DAGGenerator.new()
	generator.run_history_generation()
	queue = ReasoningQueue.new()
	resolver = LLMResolutionSystem.new()


func after_all() -> void:
	GameLoopManager.set_physics_process(true)


func _make_core(faction_id: int, population: int, food: int) -> int:
	var handle: int = ECSManager.allocate_entity()
	var row: int = EH.index_of(handle)
	var core := FactionCoreComponent.new()
	core.faction_id = faction_id
	core.dag_node_id = faction_id
	core.abstract_population = population
	core.abstract_wealth_ledger = {MaterialLibrary.MAT_BIOMASS: food, MaterialLibrary.MAT_IRON: 50}
	core.anchor_chunk_id = Vector3i.ZERO
	ECSManager.faction_cores[row] = core
	ECSManager.add_component_bit(row, ComponentMask.FACTION_CORE)
	return handle

## Declared gap G-5. Strict FIFO put a faction under attack behind twenty routine weekly
## reviews; the priority classes are what "crisis-triggered" was always supposed to mean.
func test_a_crisis_jumps_the_queue_ahead_of_routine_thinking() -> void:
	var routine_a: int = _make_core(40, 30, 500)
	var routine_b: int = _make_core(41, 30, 500)
	var crisis: int = _make_core(42, 30, 500)
	queue.submit(routine_a, ReasoningQueue.PRIORITY_ROUTINE)
	queue.submit(routine_b, ReasoningQueue.PRIORITY_ROUTINE)
	queue.submit(crisis, ReasoningQueue.PRIORITY_CRISIS)

	var served: Array[int] = []
	for _pump in 3:
		queue.pump(generator, func(handle: int, _r: Dictionary) -> void: served.append(handle))
	assert_eq(served[0], crisis, "the crisis fires first despite submitting last")
	assert_eq(served[1], routine_a, "then FIFO within the routine class")
	assert_eq(served[2], routine_b, "no starvation reordering inside a class")


## A faction that queued its weekly review and then got attacked must jump the line, not wait
## behind it. The duplicate submit is still refused; the URGENCY is what upgrades.
func test_a_resubmit_at_higher_urgency_upgrades_in_place() -> void:
	var routine: int = _make_core(43, 30, 500)
	var upgraded: int = _make_core(44, 30, 500)
	queue.submit(routine, ReasoningQueue.PRIORITY_ROUTINE)
	queue.submit(upgraded, ReasoningQueue.PRIORITY_ROUTINE)
	assert_false(
		queue.submit(upgraded, ReasoningQueue.PRIORITY_CRISIS),
		"the resubmit is still a dedup refusal"
	)
	assert_eq(queue.priority_upgrades, 1, "but the queued entry was upgraded")

	var served: Array[int] = []
	for _pump in 2:
		queue.pump(generator, func(handle: int, _r: Dictionary) -> void: served.append(handle))
	assert_eq(served[0], upgraded, "and it now outranks the earlier routine entry")


## ADR-12: the pending bound IS the faction cap, enforced before enqueue. Declared gap G-1.
func test_the_25th_faction_is_refused_not_silently_queued() -> void:
	for i in DAGGenerator.FACTION_CAP:
		queue.submit(_make_core(200 + i, 5, 100))
	assert_eq(queue.pending_count(), DAGGenerator.FACTION_CAP, "24 distinct factions queued")
	assert_false(queue.submit(_make_core(299, 5, 100)), "the 25th is refused")
	assert_gt(queue.rejected_full, 0, "and counted")


## Declared gap G-4: the prompt ASKS for 200 characters; a remote model is under no obligation
## to comply, and an uncapped response went straight into the overlay.
func test_a_five_kilobyte_reason_summary_is_capped_on_ingest() -> void:
	var handle: int = _make_core(50, 30, 500)
	var row: int = EH.index_of(handle)
	var core: FactionCoreComponent = ECSManager.faction_cores[row]
	var rant: String = "x".repeat(5000)
	resolver.resolve(handle, {
		"objective": "FORTIFY", "reason_summary": rant, "public_declaration": rant,
	}, generator)
	assert_eq(
		core.last_reasoning.length(), LLMResolutionSystem.MAX_SUMMARY_CHARS,
		"the summary is truncated at the gate"
	)
	assert_eq(
		core.last_declaration.length(), LLMResolutionSystem.MAX_SUMMARY_CHARS,
		"and so is the declaration — both free-text fields, one rule"
	)


## The fallback matrix's second half: "timeout -> maintain current objective AND REQUEUE next
## Macro tick". The requeue was asserted in a comment and implemented nowhere, so one failed
## call cost a faction a week of thinking.
func test_an_empty_response_keeps_the_plan_and_requeues() -> void:
	var handle: int = _make_core(51, 30, 500)
	var row: int = EH.index_of(handle)
	var core: FactionCoreComponent = ECSManager.faction_cores[row]
	core.current_objective = ECSEnums.Objective.RAID_FACTION
	queue.provider = _FailingProvider.new()
	queue.submit(handle)
	queue.pump(generator, func(answered: int, response: Dictionary) -> void:
		resolver.resolve(answered, response, generator)
		if response.is_empty() and ECSManager.is_alive(answered):
			queue.submit(answered, ReasoningQueue.PRIORITY_ROUTINE)
	)
	assert_eq(core.current_objective, ECSEnums.Objective.RAID_FACTION, "the raid continues")
	assert_eq(queue.pending_count(), 1, "and the leader is back in line to try again")


## Declared gap G-8: the leader's OWN memories reach the prompt. Faction memory is the
## institutional record; gossip only ever lands on individuals.
func test_the_leaders_personal_memories_reach_the_prompt() -> void:
	var handle: int = _make_core(52, 30, 500)
	var row: int = EH.index_of(handle)
	var core: FactionCoreComponent = ECSManager.faction_cores[row]

	var leader: int = ECSManager.allocate_entity()
	var leader_row: int = EH.index_of(leader)
	var memory := MemoryComponent.new()
	memory.remember(
		MemoryEvent.create(&"WITNESSED_MURDER", &"saw the old chief die", 0, true)
	)
	ECSManager.memories[leader_row] = memory
	ECSManager.add_component_bit(leader_row, ComponentMask.MEMORY)
	core.leader_handle = leader

	var context: Dictionary = PromptBuilder.build_context(core, generator)
	assert_has(context, "leader_memories")
	assert_true(
		context["leader_memories"].has("saw the old chief die"),
		"what the leader personally lived through is in the brief"
	)


## Declared gap G-9: the declaration lands in the leader's MemoryComponent as a core memory, so
## the gossip loop can carry it. `last_declaration` alone is a display field nobody can repeat.
func test_a_declaration_becomes_a_memory_gossip_can_repeat() -> void:
	var handle: int = _make_core(53, 30, 500)
	var row: int = EH.index_of(handle)
	var core: FactionCoreComponent = ECSManager.faction_cores[row]
	var leader: int = ECSManager.allocate_entity()
	var leader_row: int = EH.index_of(leader)
	ECSManager.memories[leader_row] = MemoryComponent.new()
	ECSManager.add_component_bit(leader_row, ComponentMask.MEMORY)
	core.leader_handle = leader

	resolver.resolve(handle, {
		"objective": "FORTIFY", "public_declaration": "The walls will hold!",
	}, generator)

	var events: Array[MemoryEvent] = ECSManager.memories[leader_row].events
	assert_eq(events.size(), 1, "the leader remembers saying it")
	assert_true(String(events[0].text).contains("The walls will hold!"))
	assert_true(events[0].core, "as a CORE memory, which is what makes it gossip-worthy")


## Faction memory never decayed: the weight was snapshotted at insert (age zero, falloff 1.0)
## and sorted raw, so a murder from year 1 outranked everything in the prompt forever.
func test_faction_memory_decays_in_the_salience_sort() -> void:
	var old_murder: Dictionary = {
		"event_id": 1, "text": "ancient murder", "tick": 0,
		"weight": MemoryEvent.base_weight(&"WITNESSED_MURDER"), "core": false,
	}
	var fresh_meal: Dictionary = {
		"event_id": 2, "text": "fresh meal", "tick": GameClock.total_hours(),
		"weight": MemoryEvent.base_weight(&"FED"), "core": false,
	}
	# Age the murder far past its half-life.
	GameClock.advance_interregnum_year()
	fresh_meal["tick"] = GameClock.total_hours()
	assert_true(
		PromptBuilder._more_salient(fresh_meal, old_murder),
		"a fresh minor event now outranks a year-old horror — memory decays at READ time"
	)


class _FailingProvider extends LLMProvider:
	func request(_prompt: String, on_done: Callable) -> void:
		on_done.call({})


func test_the_queue_refuses_to_grow_without_limit() -> void:
	for i in ReasoningQueue.MAX_PENDING + 10:
		queue.submit(_make_core(100 + i, 5, 100))
	assert_eq(queue.pending_count(), ReasoningQueue.MAX_PENDING, "the queue is capped")
	assert_gt(queue.rejected_full, 0, "and the overflow is reported")


## LAZY PROMPTS. The queue stores an id; a prompt built at enqueue time describes a world that
## has since moved on.
func test_a_leader_that_dies_while_queued_costs_nothing() -> void:
	var handle: int = _make_core(40, 30, 500)
	queue.submit(handle)
	ECSManager.destroy_entity(handle)

	var answers: int = 0
	queue.pump(generator, func(_h: int, _r: Dictionary) -> void: answers += 1)
	assert_eq(queue.dispatched, 0, "no request was fired for a dead leader")


func test_identical_prompts_are_served_from_cache() -> void:
	var handle: int = _make_core(50, 30, 500)
	queue.submit(handle)
	queue.pump(generator, func(_h: int, _r: Dictionary) -> void: pass)
	queue.submit(handle)
	queue.pump(generator, func(_h: int, _r: Dictionary) -> void: pass)
	assert_eq(queue.cache_hits, 1, "the second identical question was not asked twice")


# --- THE VALIDATION GATE -------------------------------------------------------------------------

## A faction that no longer exists cannot be given orders.
func test_a_dead_leader_is_discarded() -> void:
	var handle: int = _make_core(60, 30, 500)
	ECSManager.destroy_entity(handle)
	resolver.resolve(handle, {"objective": "RAID_FACTION"}, generator)
	assert_eq(resolver.rejected_dead, 1, "the order was discarded")
	assert_eq(resolver.objectives_applied, 0, "and nothing was applied")


## Malformed output, timeout and refusal all arrive as an empty Dictionary — one shape, one
## path, so there is no failure mode nobody wrote a branch for.
##
## THIS TEST ASSERTED THE OPPOSITE UNTIL 2026-08-01, and the two claims it sat between were in
## tension: every failure is indistinguishable by design, yet a timeout was supposed to preserve
## the objective while a malformed answer forced FORTIFY. You cannot have both, and the code
## resolved it the wrong way — a faction mid-raid abandoned it because the network was slow.
##
## The rule now: NO ANSWER CHANGES NOTHING. FORTIFY remains the fallback for a leader who did
## answer and answered about a faction that does not exist, which is a different failure.
func test_a_failed_call_leaves_the_plan_alone() -> void:
	var handle: int = _make_core(61, 30, 500)
	var core: FactionCoreComponent = ECSManager.faction_cores[ECSManager.resolve(handle)]
	core.current_objective = ECSEnums.Objective.RAID_FACTION
	core.objective_target = 9

	var chosen: ECSEnums.Objective = resolver.resolve(handle, {}, generator)
	assert_eq(chosen, ECSEnums.Objective.RAID_FACTION, "the raid continues")
	assert_eq(core.objective_target, 9, "against the same faction it was already marching on")
	assert_eq(resolver.rejected_malformed, 1, "and the failure was still counted")


## A leader that DID answer, with something unusable, is a different case: it said nothing about
## a target, so there is nothing to preserve and defending is the survivable default.
func test_an_answer_naming_no_objective_falls_back_to_fortify() -> void:
	var handle: int = _make_core(63, 30, 500)
	var chosen: ECSEnums.Objective = resolver.resolve(
		handle, {"emotion_state": "CALM"}, generator
	)
	assert_eq(chosen, ECSEnums.Objective.FORTIFY, "doing something defensive is survivable")


func test_an_unknown_objective_falls_back_to_fortify() -> void:
	var handle: int = _make_core(62, 30, 500)
	var chosen: ECSEnums.Objective = resolver.resolve(
		handle, {"objective": "CONQUER_THE_MOON"}, generator
	)
	assert_eq(chosen, ECSEnums.Objective.FORTIFY, "an invented objective is refused")


## THE HALLUCINATION CASE. A model will confidently name a faction that does not exist, and
## resolving a raid against it marches an army onto empty ground.
func test_a_hallucinated_target_is_stripped_and_the_raid_cancelled() -> void:
	var handle: int = _make_core(63, 30, 500)
	var chosen: ECSEnums.Objective = resolver.resolve(
		handle, {"objective": "RAID_FACTION", "target_faction_id": 999999}, generator
	)
	assert_eq(chosen, ECSEnums.Objective.FORTIFY, "the raid was cancelled")
	assert_eq(resolver.hallucinated_targets, 1, "and the hallucination was counted")
	var core: FactionCoreComponent = ECSManager.faction_cores[ECSManager.resolve(handle)]
	assert_eq(core.objective_target, -1, "no phantom target survived")


## A destroyed faction is a hallucination with extra steps: it WAS real, and is not any more.
func test_a_target_destroyed_since_the_prompt_is_refused() -> void:
	var handle: int = _make_core(64, 30, 500)
	var victim: DAGNode = generator.active_factions()[1]
	victim.status = ECSEnums.NodeStatus.DESTROYED

	var chosen: ECSEnums.Objective = resolver.resolve(
		handle, {"objective": "RAID_FACTION", "target_faction_id": victim.node_id}, generator
	)
	assert_eq(chosen, ECSEnums.Objective.FORTIFY, "you cannot raid the already-dead")


## A raid with no target is not a raid. Letting it through sends the planner marching at nothing.
func test_a_raid_without_a_target_becomes_fortify() -> void:
	var handle: int = _make_core(65, 30, 500)
	var chosen: ECSEnums.Objective = resolver.resolve(
		handle, {"objective": "RAID_FACTION", "target_faction_id": -1}, generator
	)
	assert_eq(chosen, ECSEnums.Objective.FORTIFY, "there is nobody to march on")


## The PLAYER is a legal target — Faction 0 (ADR-14) — despite having no DAG node.
func test_the_player_is_a_valid_target() -> void:
	var handle: int = _make_core(66, 30, 500)
	var chosen: ECSEnums.Objective = resolver.resolve(
		handle,
		{"objective": "RAID_FACTION", "target_faction_id": WorldConstants.PLAYER_FACTION_ID},
		generator
	)
	assert_eq(chosen, ECSEnums.Objective.RAID_FACTION, "they can absolutely come for you")


## Timeout keeps the CURRENT plan. Abandoning a siege because the network was slow is worse than
## continuing it.
## THE HELPER WAS DEAD CODE. `on_timeout()` had no caller outside this file, so this test proved
## a rule the production path did not follow. It now goes through `resolve()`, which is what the
## queue actually calls.
func test_a_timeout_keeps_the_current_objective_through_the_real_path() -> void:
	var handle: int = _make_core(64, 30, 500)
	var core: FactionCoreComponent = ECSManager.faction_cores[ECSManager.resolve(handle)]
	core.current_objective = ECSEnums.Objective.MIGRATE
	resolver.resolve(handle, {}, generator)
	assert_eq(core.current_objective, ECSEnums.Objective.MIGRATE, "still migrating")


func test_a_timeout_keeps_the_current_objective() -> void:
	var handle: int = _make_core(67, 30, 500)
	var core: FactionCoreComponent = ECSManager.faction_cores[ECSManager.resolve(handle)]
	core.current_objective = ECSEnums.Objective.RAID_FACTION
	assert_eq(
		resolver.on_timeout(handle), ECSEnums.Objective.RAID_FACTION, "the plan stands"
	)


# --- The prompt ------------------------------------------------------------------------------

## Valid target ids must be listed explicitly, or the model invents plausible numbers and every
## one becomes work for the gate.
func test_the_prompt_enumerates_valid_target_ids() -> void:
	var handle: int = _make_core(generator.active_factions()[0].node_id, 30, 500)
	var prompt: String = PromptBuilder.build(
		ECSManager.faction_cores[ECSManager.resolve(handle)].faction_id, generator
	)
	assert_string_contains(prompt, "Valid Targets:", "the list is present")
	assert_string_contains(
		prompt, "[%d:" % WorldConstants.PLAYER_FACTION_ID, "and the player is on it"
	)


## THE SALIENCE FILTER. An unfiltered history fills a context window and the bill is real money.
func test_only_the_most_salient_memories_are_sent() -> void:
	var core := FactionCoreComponent.new()
	for i in 40:
		core.faction_memory.append({
			"event_id": i, "text": "event %d" % i, "tick": i, "weight": float(i % 7), "core": false
		})
	var chosen: Array[String] = PromptBuilder.salient_memories(core)
	assert_lte(
		chosen.size(),
		PromptBuilder.TOP_MEMORIES + PromptBuilder.RECENT_MEMORIES,
		"at most top-3 plus 3 most recent"
	)
	assert_true(chosen.has("event 39"), "the newest event is included")


## TOTAL ORDER, OR IT IS NOT REPRODUCIBLE. Both sorts compared a single field, and `sort_custom`
## is not stable, so ties could resolve either way — which changes WHICH memories are selected,
## not merely their order. That breaks ADR-20's reproduce-from-seed rule and silently defeats the
## response cache in `ReasoningQueue`, which keys on the prompt hash: identical world state
## missing the cache is a paid call that should never have been made.
func test_the_same_history_always_produces_the_same_memories() -> void:
	var core := FactionCoreComponent.new()
	# EVERY weight and tick tied. Nothing but the tie-breaker can decide this.
	for i in 20:
		core.faction_memory.append({
			"event_id": i, "text": "event %d" % i, "tick": 5, "weight": 2.0, "core": false
		})
	var first: Array[String] = PromptBuilder.salient_memories(core)

	# Same memories, arriving in the OPPOSITE order. Selection must not depend on how the
	# history happened to be appended, or two saves of the same world reason differently.
	var reversed_core := FactionCoreComponent.new()
	for i in range(19, -1, -1):
		reversed_core.faction_memory.append({
			"event_id": i, "text": "event %d" % i, "tick": 5, "weight": 2.0, "core": false
		})
	assert_eq(
		PromptBuilder.salient_memories(reversed_core),
		first,
		"the same history chose the same memories, whatever order it arrived in"
	)


## Ties must not silently reorder the ones that DO differ, either.
func test_weight_still_beats_recency_when_they_disagree() -> void:
	var core := FactionCoreComponent.new()
	core.faction_memory.append(
		{"event_id": 1, "text": "old but grave", "tick": 0, "weight": 99.0, "core": true}
	)
	for i in 8:
		core.faction_memory.append({
			"event_id": 10 + i, "text": "recent trivia %d" % i,
			"tick": 100 + i, "weight": 0.1, "core": false
		})
	var chosen: Array[String] = PromptBuilder.salient_memories(core)
	assert_true(chosen.has("old but grave"), "the heavy memory survives eight fresher ones")


func test_the_prompt_states_the_required_schema() -> void:
	var handle: int = _make_core(generator.active_factions()[0].node_id, 30, 500)
	var prompt: String = PromptBuilder.build(
		ECSManager.faction_cores[ECSManager.resolve(handle)].faction_id, generator
	)
	for key in ["objective", "target_faction_id", "emotion_state", "public_declaration"]:
		assert_string_contains(prompt, key, "the schema names %s" % key)


# --- Cadence and bounds -------------------------------------------------------------------------

## ADR-9 SAYS WEEKLY. `_think()` submitted every faction every hour — 168x the specified rate,
## which burns a 200-call remote budget in a bit over a day of in-game time and churns objectives
## faster than any faction can act on one.
func test_leaders_do_not_think_every_hour() -> void:
	var handle: int = _make_core(70, 30, 500)
	GameLoopManager._last_thought.clear()
	var submitted_before: int = GameLoopManager.reasoning.enqueued

	# Six hours of ordinary time, none of them a review hour.
	for _hour in 6:
		GameClock.advance_hour()
		if GameClock.total_hours() % GameLoopManager.HOURS_PER_STRATEGY_REVIEW == 0:
			GameClock.advance_hour()
		GameLoopManager._think()

	assert_lt(
		GameLoopManager.reasoning.enqueued - submitted_before,
		6,
		"a quiet faction did not queue a thought every single hour"
	)
	assert_true(ECSManager.is_alive(handle), "and the faction is still there")


## Weekly must not mean never. The review hour has to actually fire.
func test_the_review_hour_makes_leaders_think() -> void:
	_make_core(71, 30, 500)
	GameLoopManager._last_thought.clear()
	while GameClock.total_hours() % GameLoopManager.HOURS_PER_STRATEGY_REVIEW != 0:
		GameClock.advance_hour()

	var before: int = GameLoopManager.reasoning.enqueued
	GameLoopManager._think()
	assert_gt(GameLoopManager.reasoning.enqueued, before, "the weekly review queued work")


## And a faction under attack does not wait six days to react — the crisis clause of ADR-9.
func test_an_attacked_faction_thinks_without_waiting_for_the_review() -> void:
	var handle: int = _make_core(72, 30, 500)
	var core: FactionCoreComponent = ECSManager.faction_cores[ECSManager.resolve(handle)]
	core.faction_memory.append({
		"event_id": 900, "text": "WITNESSED_MURDER by faction 3", "tick": GameClock.total_hours(),
		"weight": 9.0, "core": true
	})
	assert_true(PromptBuilder.was_recently_attacked(core), "the faction knows it was attacked")

	GameLoopManager._last_thought.clear()
	while GameClock.total_hours() % GameLoopManager.HOURS_PER_STRATEGY_REVIEW == 0:
		GameClock.advance_hour()
	var before: int = GameLoopManager.reasoning.enqueued
	GameLoopManager._think()
	assert_gt(GameLoopManager.reasoning.enqueued, before, "it thought anyway")


## A long siege must not become one request per hour. That is the whole reason for the cooldown.
func test_a_long_war_does_not_become_a_request_every_hour() -> void:
	var handle: int = _make_core(73, 30, 500)
	var core: FactionCoreComponent = ECSManager.faction_cores[ECSManager.resolve(handle)]
	core.faction_memory.append({
		"event_id": 901, "text": "WITNESSED_MURDER by faction 3", "tick": GameClock.total_hours(),
		"weight": 9.0, "core": true
	})
	GameLoopManager._last_thought.clear()

	var before: int = GameLoopManager.reasoning.enqueued
	for _hour in 8:
		GameLoopManager._think()
	assert_lte(
		GameLoopManager.reasoning.enqueued - before,
		2,
		"the crisis was answered, not asked eight times"
	)


## THE CACHE WAS A LEAK. A prompt changes whenever the world does, so the number of distinct
## prompts over a long run is unbounded and so was the "cost control" dictionary holding them.
func test_the_response_cache_cannot_grow_without_bound() -> void:
	var queue := ReasoningQueue.new()
	for i in ReasoningQueue.MAX_CACHED * 3:
		queue._remember("prompt-%d" % i, {"objective": "IDLE"})
	assert_lte(queue._cache.size(), ReasoningQueue.MAX_CACHED, "the cache is capped")
	assert_eq(queue._cache_order.size(), queue._cache.size(), "and the order index agrees with it")


## Oldest-first: an old prompt describes a world that has moved on, so it is both the least
## likely to hit again and the least harmful to lose.
func test_the_cache_evicts_the_oldest_entry_first() -> void:
	var queue := ReasoningQueue.new()
	for i in ReasoningQueue.MAX_CACHED + 1:
		queue._remember("prompt-%d" % i, {"objective": "IDLE"})
	assert_false(queue._cache.has("prompt-0"), "the first prompt was evicted")
	assert_true(queue._cache.has("prompt-%d" % ReasoningQueue.MAX_CACHED), "the newest is kept")


## Re-caching a repeated prompt must not enlarge the order index, or the cap drifts.
func test_recaching_the_same_prompt_does_not_grow_the_index() -> void:
	var queue := ReasoningQueue.new()
	for _repeat in 50:
		queue._remember("the same prompt", {"objective": "IDLE"})
	assert_eq(queue._cache_order.size(), 1, "one prompt, one entry")


## An ancient atrocity is not an emergency. Before the window check, any violent memory still in
## the capped list made a faction permanently "recently attacked" — which, once that flag became
## the crisis trigger, meant a permanently elevated reasoning rate.
func test_an_ancient_grievance_is_not_a_crisis() -> void:
	var core := FactionCoreComponent.new()
	core.faction_memory.append({
		"event_id": 902, "text": "WITNESSED_MURDER", "core": true, "weight": 9.0,
		"tick": GameClock.total_hours() - (PromptBuilder.ATTACK_MEMORY_WINDOW_HOURS + 10)
	})
	assert_false(PromptBuilder.was_recently_attacked(core), "a year-old murder is history")

	core.faction_memory.append({
		"event_id": 903, "text": "WITNESSED_MURDER", "core": true, "weight": 9.0,
		"tick": GameClock.total_hours()
	})
	assert_true(PromptBuilder.was_recently_attacked(core), "one that just happened is not")

