## The history graph (Sprint 2 Step 1).
##
## This runs before anything is rendered and everything downstream reads it, so the properties
## that matter are boundedness, reproducibility, and conservation — not literary quality.
extends GutTest

var gen: DAGGenerator


func before_each() -> void:
	RNGService.reseed_all(1)
	gen = DAGGenerator.new()


## An unbounded history generator is an unbounded cold boot, sitting directly in front of the
## player. Three separate bounds, all asserted.
func test_generation_is_bounded() -> void:
	gen.run_history_generation()
	assert_lte(
		gen.active_factions().size(),
		DAGGenerator.FACTION_CAP,
		"live factions never exceed the ADR-12 cap"
	)
	assert_eq(gen.current_epoch, DAGGenerator.MAX_EPOCHS - 1, "the epoch loop terminated")
	# Each epoch adds at most one faction, one artifact, and two conquest edges.
	assert_lte(gen.nodes.size(), DAGGenerator.MAX_EPOCHS * 2 + 1, "node count is linear in epochs")


## Same seed, same history. ADR-20's soak harness cannot compare runs against a baseline if the
## world it boots into differs every time.
func test_history_is_reproducible_from_the_seed() -> void:
	gen.run_history_generation()
	var first: String = gen.chronicle_text()

	RNGService.reseed_all(1)
	var second_run := DAGGenerator.new()
	second_run.run_history_generation()

	assert_eq(second_run.chronicle_text(), first, "the same seed replays the same history")


func test_different_seeds_produce_different_histories() -> void:
	gen.run_history_generation()
	var first: String = gen.chronicle_text()

	RNGService.reseed_all(999)
	var other := DAGGenerator.new()
	other.run_history_generation()

	assert_ne(other.chronicle_text(), first, "a different seed writes a different history")


## The village is the player's Day 0 anchor and the Pre-Warm depends on it. History happens
## around it, never to it.
func test_the_surface_village_always_exists_and_survives() -> void:
	gen.run_history_generation()
	var villages: Array[DAGNode] = gen.active_factions().filter(
		func(n: DAGNode) -> bool: return n.tags.has(&"SurfaceVillage")
	)
	assert_eq(villages.size(), 1, "exactly one surface village survives every history")
	assert_eq(villages[0].home_floor, 0, "and it is on the surface")
	assert_gt(villages[0].population, 10, "with enough people to be worth visiting")


## DESTROYED nodes are RETAINED. A conquered faction is the only explanation for why its
## conqueror holds that ground; deleting it deletes the answer.
func test_conquered_factions_are_retained_not_deleted() -> void:
	gen.run_history_generation()
	var destroyed: Array = []
	for id in gen.nodes:
		var node: DAGNode = gen.nodes[id]
		if node.status == ECSEnums.NodeStatus.DESTROYED:
			destroyed.append(node)

	assert_gt(destroyed.size(), 0, "500 years produced at least one conquest")
	for node in destroyed:
		assert_gt(node.conquered_by, 0, "%s records who conquered it" % node.name)
		assert_gte(node.death_epoch, 0, "and when")
		assert_true(
			gen.nodes.has(node.conquered_by), "and the conqueror is still in the graph"
		)


func test_every_conquest_is_recorded_as_an_edge() -> void:
	gen.run_history_generation()
	var conquered_ids: Array[int] = []
	for id in gen.nodes:
		if gen.nodes[id].status == ECSEnums.NodeStatus.DESTROYED:
			conquered_ids.append(id)
	for victim_id in conquered_ids:
		var found: bool = false
		for edge in gen.edges_touching(victim_id):
			if edge.type == ECSEnums.EdgeType.CONQUERED and edge.target_id == victim_id:
				found = true
		assert_true(found, "node %d has a CONQUERED edge naming it" % victim_id)


## CONSERVATION. Conquest moves wealth, it does not mint or burn it. This is the same invariant
## the LoD boundary must hold, checked here at the abstract layer where it originates.
func test_conquest_transfers_wealth_without_creating_or_destroying_it() -> void:
	# Two hand-built factions, so no epoch growth can pollute the measurement.
	gen.current_epoch = 10
	var strong: DAGNode = gen._found_faction(100, -1, false)
	var weak: DAGNode = gen._found_faction(10, -1, false)
	strong.abstract_wealth_ledger = {&"MAT_IRON": 500}
	weak.abstract_wealth_ledger = {&"MAT_IRON": 120, &"MAT_GOLD": 40}
	var before: int = strong.ledger_total() + weak.ledger_total()

	weak.status = ECSEnums.NodeStatus.DESTROYED
	for material in weak.abstract_wealth_ledger:
		strong.add_wealth(material, int(weak.abstract_wealth_ledger[material]))
	weak.abstract_wealth_ledger.clear()

	assert_eq(
		strong.ledger_total() + weak.ledger_total(),
		before,
		"total wealth is identical before and after the conquest"
	)
	assert_eq(weak.ledger_total(), 0, "the loser keeps nothing")


## Anchors are World Generation's job (Step 2). If the DAG assigned them, two systems would own
## the same field and the loser would silently overwrite the winner.
func test_the_dag_does_not_assign_spatial_anchors() -> void:
	gen.run_history_generation()
	for node in gen.active_factions():
		assert_false(
			node.has_anchor(), "%s has no anchor until world generation places it" % node.name
		)


## The unset anchor must be distinguishable from a legitimate chunk at the origin, or every
## faction quietly piles up at (0, 0, 0).
func test_the_unset_anchor_is_not_the_world_origin() -> void:
	var node := DAGNode.new()
	assert_false(node.has_anchor(), "a fresh node has no anchor")
	node.anchor_chunk_id = Vector3i.ZERO
	assert_true(node.has_anchor(), "the origin is a LEGAL anchor, not a sentinel")


## The Step 1 success state, as an assertion rather than a screenshot of a log.
func test_the_chronicle_reports_foundings_and_conquests() -> void:
	gen.run_history_generation()
	var text: String = gen.chronicle_text()
	assert_string_contains(text, "founded on floor", "the chronicle records foundings")
	assert_string_contains(text, "conquered", "and conquests")
	assert_gt(gen.chronicle.size(), 5, "500 years produced a readable history")


func test_nodes_survive_a_json_round_trip() -> void:
	gen.run_history_generation()
	var node: DAGNode = gen.active_factions()[0]
	var parsed: Variant = JSON.parse_string(JSON.stringify(node.to_dict()))
	assert_eq(int(parsed["node_id"]), node.node_id, "the id survives JSON (ADR-21)")
	assert_eq(int(parsed["population"]), node.population, "and so does the population")
