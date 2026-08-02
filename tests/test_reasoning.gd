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


## A provider that never answers, for testing the one-in-flight rule.
class _StallingProvider:
	extends LLMProvider

	func request(_prompt: String, _on_done: Callable) -> void:
		pass

	func describe() -> String:
		return "stalling (test)"
