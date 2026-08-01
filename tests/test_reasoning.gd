## The reasoner and its validation gate (Sprint 3C).
##
## Per the amended ADR-5 the LLM is an OPTIONAL layer, so the heuristic provider is the default
## and is held to the identical gate. A validator that only runs on the remote path is a
## validator nobody has tested, and its fallbacks are exactly what the no-endpoint mode is.
extends GutTest

const SEED: int = 606

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


# --- The default provider ----------------------------------------------------------------------

## The whole point of the amendment: no endpoint, no key, still a complete game.
func test_the_game_reasons_with_no_endpoint_configured() -> void:
	assert_false(queue.provider.is_remote(), "the default provider is local")
	var handle: int = _make_core(7, 40, 500)
	queue.submit(handle)

	var answers: Array[Dictionary] = []
	queue.pump(generator, func(_h: int, response: Dictionary) -> void: answers.append(response))
	assert_eq(answers.size(), 1, "a decision came back")
	assert_true(answers[0].has("objective"), "in the agreed schema")


## Starving outranks everything. A faction that raids while its people die is not interesting.
func test_a_starving_faction_gathers_food_before_anything_else() -> void:
	var heuristic := HeuristicProvider.new()
	var answer: Dictionary = heuristic.decide({
		"population": 100, "food": 10, "strength": 500.0,
		"valid_targets": [{"faction_id": 9, "name": "weaklings", "strength": 1.0, "score": -90.0}],
	})
	assert_eq(answer["objective"], "GATHER_RESOURCES", "food first, despite easy prey")
	assert_eq(answer["emotion_state"], "DESPERATE", "and it knows it is in trouble")


func test_a_well_fed_faction_raids_a_weak_enemy() -> void:
	var heuristic := HeuristicProvider.new()
	var answer: Dictionary = heuristic.decide({
		"population": 100, "food": 9000, "strength": 500.0,
		"valid_targets": [{"faction_id": 9, "name": "weaklings", "strength": 1.0, "score": -90.0}],
	})
	assert_eq(answer["objective"], "RAID_FACTION", "opportunity is taken")
	assert_eq(int(answer["target_faction_id"]), 9, "against the named weakling")


## Being attacked and going mining reads as a bug, not as character.
func test_a_recently_attacked_faction_fortifies() -> void:
	var heuristic := HeuristicProvider.new()
	var answer: Dictionary = heuristic.decide({
		"population": 100, "food": 9000, "strength": 500.0, "recently_attacked": true,
		"valid_targets": [{"faction_id": 9, "name": "weaklings", "strength": 1.0, "score": -90.0}],
	})
	assert_eq(answer["objective"], "FORTIFY", "defence outranks opportunity")


func test_a_strong_neighbour_is_not_attacked() -> void:
	var heuristic := HeuristicProvider.new()
	var answer: Dictionary = heuristic.decide({
		"population": 10, "food": 9000, "strength": 10.0,
		"valid_targets": [{"faction_id": 9, "name": "giants", "strength": 900.0, "score": -90.0}],
	})
	assert_ne(answer["objective"], "RAID_FACTION", "suicide is not an objective")


# --- The queue ---------------------------------------------------------------------------------

## One in flight. Twenty leaders thinking at once is twenty paid calls and a provider 429 that
## arrives as twenty simultaneous failures.
func test_only_one_request_is_dispatched_at_a_time() -> void:
	queue.provider = _StallingProvider.new()
	for i in 5:
		queue.submit(_make_core(20 + i, 30, 500))
	queue.pump(generator, func(_h: int, _r: Dictionary) -> void: pass)
	queue.pump(generator, func(_h: int, _r: Dictionary) -> void: pass)
	assert_eq(queue.dispatched, 1, "the second pump waited for the first to land")
	assert_true(queue.is_busy(), "and the line is still busy")


func test_submitting_the_same_faction_twice_is_a_no_op() -> void:
	var handle: int = _make_core(30, 30, 500)
	assert_true(queue.submit(handle), "the first submission is accepted")
	assert_false(queue.submit(handle), "the second is not")
	assert_eq(queue.pending_count(), 1, "and it is queued exactly once")


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
## fallback, so there is no failure mode nobody wrote a branch for.
func test_a_malformed_answer_falls_back_to_fortify() -> void:
	var handle: int = _make_core(61, 30, 500)
	var chosen: ECSEnums.Objective = resolver.resolve(handle, {}, generator)
	assert_eq(chosen, ECSEnums.Objective.FORTIFY, "doing something defensive is survivable")
	assert_eq(resolver.rejected_malformed, 1, "and it was counted as malformed")


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


func test_the_prompt_states_the_required_schema() -> void:
	var handle: int = _make_core(generator.active_factions()[0].node_id, 30, 500)
	var prompt: String = PromptBuilder.build(
		ECSManager.faction_cores[ECSManager.resolve(handle)].faction_id, generator
	)
	for key in ["objective", "target_faction_id", "emotion_state", "public_declaration"]:
		assert_string_contains(prompt, key, "the schema names %s" % key)


## A provider that never answers, for testing the one-in-flight rule.
class _StallingProvider:
	extends LLMProvider

	func request(_prompt: String, _on_done: Callable) -> void:
		pass

	func describe() -> String:
		return "stalling (test)"
