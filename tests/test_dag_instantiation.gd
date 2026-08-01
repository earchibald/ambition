## Turning history into entities (Sprint 2 Step 3).
##
## Almost every assertion here is about ENTITY COUNT. The translation is easy to write and easy
## to write catastrophically: one entity per coin, or six hundred agents materialized at boot for
## factions the player will never visit, both "work" and both exhaust the ADR-12 budget.
extends GutTest

const SEED: int = 77

var grid: WorldGrid
var generator: DAGGenerator
var instantiator: DAGInstantiator


func before_each() -> void:
	GameLoopManager.set_physics_process(false)
	World.boot_scenario(World.SCENARIO_TEST_ARENA, SEED)
	RNGService.reseed_all(SEED)
	generator = DAGGenerator.new()
	generator.run_history_generation()
	grid = WorldGrid.new(SEED)
	grid.generate_village()
	grid.assign_anchors(generator.active_factions())
	instantiator = DAGInstantiator.new()


func after_all() -> void:
	GameLoopManager.set_physics_process(true)


## Every active faction gets exactly one ledger entity, no matter how big it is.
func test_each_active_faction_gets_exactly_one_macro_entity() -> void:
	var expected: int = generator.active_factions().size()
	instantiator.instantiate(generator.get_active_world_state(), grid)
	assert_eq(instantiator.factions_created, expected, "one macro-entity per active faction")
	assert_eq(
		ECSManager.query(ComponentMask.FACTION_CORE).size(),
		expected,
		"and they are all queryable"
	)


## The ledger entity is NOT a thing in the world. Giving it a position would put it in the
## spatial hash, in the renderer, and in the way.
func test_the_faction_macro_entity_has_no_physical_presence() -> void:
	instantiator.instantiate(generator.get_active_world_state(), grid)
	for row in ECSManager.query(ComponentMask.FACTION_CORE):
		assert_false(
			ECSManager.has_components(row, ComponentMask.POSITION),
			"a faction ledger has no position"
		)
		assert_false(
			ECSManager.has_components(row, ComponentMask.BOUNDS), "and no collision footprint"
		)


## THE memory rule. Factions whose territory is Abstracted stay as integers on a ledger; only
## Active and Simulated anchors get bodies.
func test_abstracted_factions_do_not_materialize_bodies() -> void:
	instantiator.instantiate(generator.get_active_world_state(), grid)
	assert_gt(
		instantiator.skipped_abstract, 0, "most factions live on unvisited floors and stay abstract"
	)

	# Every citizen that DID spawn belongs to a faction anchored in a non-abstract chunk.
	for row in ECSManager.query(ComponentMask.SOCIAL_IDENTITY):
		if row == 0:
			continue
		var identity: SocialIdentityComponent = ECSManager.social_identities[row]
		var node: DAGNode = generator.node_by_id(identity.faction_id)
		if node == null:
			continue
		assert_ne(
			grid.chunk_at(node.anchor_chunk_id).state,
			ECSEnums.LoD.ABSTRACTED,
			"no citizen was spawned in an abstracted chunk"
		)


## Population above the cap stays abstract rather than being dropped, so the head count is
## conserved between the physical crowd and the ledger.
func test_population_above_the_cap_is_kept_abstract_not_discarded() -> void:
	var node: DAGNode = generator.active_factions()[0]
	node.population = 500
	node.anchor_chunk_id = Vector3i.ZERO
	instantiator.instantiate([node] as Array[DAGNode], grid)

	assert_lte(
		instantiator.citizens_spawned,
		DAGInstantiator.MAX_CITIZENS_PER_FACTION,
		"the physical crowd is bounded"
	)
	var core: FactionCoreComponent = DAGInstantiator.faction_core(node.node_id)
	assert_eq(core.abstract_population, 500, "and the full population is still recorded")


## The whole boot must not blow the entity budget. This is the assertion that catches "spawn
## everyone everywhere" before it reaches a profiler.
func test_the_whole_history_instantiates_well_inside_the_entity_cap() -> void:
	instantiator.instantiate(generator.get_active_world_state(), grid)
	var alive: int = ECSManager.alive_count
	assert_lt(
		alive,
		WorldConstants.ACTIVE_ENTITY_HARD_CAP,
		"boot leaves headroom under the ADR-12 cap (alive=%d)" % alive
	)


## Wealth is a QUANTITY on one stack, never one entity per unit.
func test_wealth_is_carried_as_quantity_not_as_entity_count() -> void:
	var physical := PhysicalPropertyComponent.new()
	physical.quantity = 500
	assert_eq(physical.quantity, 500, "five hundred iron is one stack of 500")

	var node: DAGNode = generator.active_factions()[0]
	node.anchor_chunk_id = Vector3i.ZERO
	var before: int = ECSManager.alive_count
	instantiator.instantiate([node] as Array[DAGNode], grid)
	var spawned: int = ECSManager.alive_count - before
	# One core, plus at most the citizen cap. Ledger wealth adds no entities at all.
	assert_lte(
		spawned,
		1 + DAGInstantiator.MAX_CITIZENS_PER_FACTION,
		"ledger wealth contributed zero entities"
	)


## Citizens are people, not commodities. A PRESERVE_ENTITY policy is what stops the LoD sweep
## dissolving a village into a pile of biomass units.
func test_citizens_are_never_ledgerizable() -> void:
	var node: DAGNode = generator.active_factions()[0]
	node.anchor_chunk_id = Vector3i.ZERO
	instantiator.instantiate([node] as Array[DAGNode], grid)
	assert_gt(instantiator.citizens_spawned, 0, "citizens were spawned")

	for row in ECSManager.query(ComponentMask.MATERIALIZATION):
		var policy: MaterializationComponent = ECSManager.materializations[row]
		if policy.item_class != &"Citizen":
			continue
		assert_false(policy.can_ledgerize(), "a citizen is never swept into a ledger")


## Ownership is a component, never a tag (registry §7).
func test_citizens_carry_ownership_as_a_component() -> void:
	var node: DAGNode = generator.active_factions()[0]
	node.anchor_chunk_id = Vector3i.ZERO
	instantiator.instantiate([node] as Array[DAGNode], grid)

	var owned: int = 0
	for row in ECSManager.query(ComponentMask.OWNERSHIP):
		if ECSManager.ownerships[row].faction_id == node.node_id:
			owned += 1
	assert_eq(owned, instantiator.citizens_spawned, "every citizen is owned by its faction")


## A faction with no anchor means the boot order was violated. Spawning anyway would pile it on
## the world origin, which is the exact bug the anchor system exists to prevent.
func test_a_faction_without_an_anchor_is_refused() -> void:
	var orphan := DAGNode.new()
	orphan.node_id = 9001
	orphan.population = 10
	assert_false(orphan.has_anchor(), "the orphan has no anchor")

	var before: int = ECSManager.alive_count
	instantiator.instantiate([orphan] as Array[DAGNode], grid)
	# The push_error IS the intended behaviour here, so it is acknowledged rather than avoided.
	# GUT fails a test on any unhandled push_error, which is the right default — silencing it
	# globally would hide real errors in every other test.
	for tracked in gut.error_tracker.get_current_test_errors():
		tracked.handled = true

	assert_eq(ECSManager.alive_count, before, "nothing was spawned for the anchorless faction")


func test_the_ledger_cannot_be_overdrawn() -> void:
	var core := FactionCoreComponent.new()
	core.abstract_wealth_ledger = {&"MAT_IRON": 100}
	assert_eq(core.withdraw(&"MAT_IRON", 250), 100, "you can only take what is there")
	assert_eq(core.ledger_total(), 0, "and the ledger empties rather than going negative")
