## The off-screen economy (Sprint 2 Step 5).
##
## The success state the roadmap names is "a faction steadily increases its MAT_IRON every Macro
## tick, without a single physical item entity being created". Both halves are asserted, and the
## second one is the one that matters — an economy that quietly spawns ore off-screen works
## perfectly right up until memory runs out.
extends GutTest

var economy: GrayBoxSystem
var miners: FactionCoreComponent
var farmers: FactionCoreComponent


func before_each() -> void:
	GameLoopManager.set_physics_process(false)
	World.boot_scenario(World.SCENARIO_TEST_ARENA, 5)
	economy = GrayBoxSystem.new()
	miners = _make_core(1, [&"Mining"], 100)
	farmers = _make_core(2, [&"Farming"], 100)


func after_all() -> void:
	GameLoopManager.set_physics_process(true)


func _make_core(id: int, tags: Array[StringName], population: int) -> FactionCoreComponent:
	var handle: int = ECSManager.allocate_entity()
	var row: int = EH.index_of(handle)
	var core := FactionCoreComponent.new()
	core.faction_id = id
	core.culture_tags = tags
	core.abstract_population = population
	ECSManager.faction_cores[row] = core
	ECSManager.add_component_bit(row, ComponentMask.FACTION_CORE)
	return core


## THE rule. Not one entity, ever.
func test_the_economy_never_creates_an_entity() -> void:
	var before: int = ECSManager.alive_count
	for _tick in 50:
		economy.run()
	assert_eq(ECSManager.alive_count, before, "fifty Macro ticks created zero entities")
	assert_eq(economy.entities_created, 0, "and the system says so itself")


## The roadmap's stated success state, verbatim.
func test_a_mining_faction_steadily_accumulates_iron() -> void:
	var readings: Array[int] = []
	for _tick in 5:
		economy.run()
		readings.append(int(miners.abstract_wealth_ledger.get(MaterialLibrary.MAT_IRON, 0)))
	for i in range(1, readings.size()):
		assert_gt(readings[i], readings[i - 1], "iron rose again on tick %d" % i)


## Production follows CULTURE, not faction id. A farming faction mines nothing.
func test_production_is_driven_by_culture_tags() -> void:
	economy.run()
	assert_gt(
		int(miners.abstract_wealth_ledger.get(MaterialLibrary.MAT_IRON, 0)), 0, "miners mine"
	)
	assert_eq(
		int(farmers.abstract_wealth_ledger.get(MaterialLibrary.MAT_IRON, 0)),
		0,
		"farmers do not"
	)
	assert_gt(
		int(farmers.abstract_wealth_ledger.get(MaterialLibrary.MAT_BIOMASS, 0)),
		0,
		"farmers farm"
	)


## People eat whether or not anyone is watching. Without consumption every ledger rises forever
## and scarcity — the thing the whole economy exists to produce — never happens.
func test_population_consumes_food() -> void:
	miners.abstract_wealth_ledger[MaterialLibrary.MAT_BIOMASS] = 1000
	economy.run()
	assert_lt(
		int(miners.abstract_wealth_ledger[MaterialLibrary.MAT_BIOMASS]),
		1000,
		"a hundred mouths ate something"
	)
	assert_gt(economy.units_consumed, 0, "and it was reported")


## A starving faction reaches zero. It does not go into debt: the ledger is unsigned by contract,
## and a negative entry means some sweep double-counted.
func test_a_starving_faction_stops_at_zero_rather_than_going_negative() -> void:
	var starving: FactionCoreComponent = _make_core(3, [] as Array[StringName], 5000)
	for _tick in 20:
		economy.run()
	assert_eq(starving.ledger_total(), 0, "it starved down to nothing")
	for material in starving.abstract_wealth_ledger:
		assert_gte(int(starving.abstract_wealth_ledger[material]), 0, "%s is not negative" % material)


## ADR-21: JSON cannot carry integers past 2^53. A 500-year run at eight units an hour would
## otherwise climb into the tens of millions and quietly corrupt on save.
func test_the_ledger_is_capped() -> void:
	miners.abstract_wealth_ledger[MaterialLibrary.MAT_IRON] = GrayBoxSystem.LEDGER_SOFT_CAP
	economy.run()
	assert_lte(
		miners.ledger_total(),
		GrayBoxSystem.LEDGER_SOFT_CAP + 100,
		"production stops once the cap is reached"
	)


## Abstracted factions are exactly the ones this system exists for: they have no chunk, no
## bodies, and no items, and they still have an economy.
func test_a_faction_with_no_physical_presence_still_has_an_economy() -> void:
	var ghost: FactionCoreComponent = _make_core(4, [&"Mining"] as Array[StringName], 40)
	assert_eq(
		ChunkStreamingSystem.rows_in_chunk(ghost.anchor_chunk_id).size(),
		0,
		"the faction has no entities anywhere"
	)
	economy.run()
	assert_gt(ghost.ledger_total(), 0, "and still produced this hour")
