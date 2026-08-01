## The off-screen economy (Sprint 2 Step 5). Runs on the Macro tick — once every 10 real
## seconds, one in-game hour (ADR-9).
##
## THE ONE RULE: this system may not create entities. Not one. A faction on floor five that mines
## iron increases an integer; it does not instantiate an ore. With a couple of dozen factions
## producing every in-game hour, spawning items off-screen would fill memory with goods nobody
## will ever look at, and the LoD sweep would then have to find and delete them all again.
##
## Production is driven by culture tags, so what a faction accumulates is a consequence of who
## they are rather than a hard-coded table of faction ids.
class_name GrayBoxSystem
extends RefCounted

## Per Macro tick, per faction. Deliberately small: this fires every in-game hour, so 8 units an
## hour is roughly 200 a day, and a 500-year history would already be absurd at ten times this.
const YIELD_PER_TICK: Dictionary = {
	&"Mining": {&"MAT_IRON": 8, &"MAT_STONE": 12},
	&"Stoneworking": {&"MAT_STONE": 6},
	&"Farming": {&"MAT_BIOMASS": 10},
	&"Scavenging": {&"MAT_CLOTH": 3, &"MAT_COPPER": 2},
	&"Trade": {&"MAT_COPPER": 4},
	&"Raiding": {&"MAT_COPPER": 3},
	&"Ritual": {&"MAT_SULFUR": 4},
}

## Consumption scales with abstract population: people eat whether or not anyone is watching.
## Without this, every faction's wealth rises monotonically forever and scarcity never exists.
const BIOMASS_PER_HUNDRED_PEOPLE: int = 6

## Above this the ledger stops accumulating. A 500-year run at 8 units an hour would otherwise
## reach tens of millions, and ADR-21 is explicit that JSON cannot carry integers past 2^53.
const LEDGER_SOFT_CAP: int = 1_000_000

var ticks_run: int = 0
var factions_processed: int = 0
var units_produced: int = 0
var units_consumed: int = 0
var entities_created: int = 0


## One Macro tick of abstract economy across every faction that has a ledger.
func run() -> void:
	ticks_run += 1
	factions_processed = 0
	units_produced = 0
	units_consumed = 0

	var before: int = ECSManager.alive_count
	for row in ECSManager.query(ComponentMask.FACTION_CORE):
		_produce(ECSManager.faction_cores[row])
		_consume(ECSManager.faction_cores[row])
		factions_processed += 1
	# Self-check rather than a comment. The invariant IS the design, so it is measured, and the
	# debug overlay shows the number.
	entities_created = ECSManager.alive_count - before
	assert(entities_created == 0, "the gray-box economy must never instantiate entities")


func _produce(core: FactionCoreComponent) -> void:
	for tag in core.culture_tags:
		var yields: Dictionary = YIELD_PER_TICK.get(tag, {})
		for material in yields:
			if core.ledger_total() >= LEDGER_SOFT_CAP:
				return
			var amount: int = int(yields[material])
			core.add_wealth(material, amount)
			units_produced += amount


## Mouths to feed. `withdraw` cannot overdraw, so a starving faction simply reaches zero — it
## does not go into debt, and the ledger's unsigned contract holds.
func _consume(core: FactionCoreComponent) -> void:
	if core.abstract_population <= 0:
		return
	var eaten: int = maxi(
		1, core.abstract_population * BIOMASS_PER_HUNDRED_PEOPLE / 100
	)
	units_consumed += core.withdraw(MaterialLibrary.MAT_BIOMASS, eaten)


func counters() -> Dictionary:
	return {
		"graybox_ticks": ticks_run,
		"graybox_factions": factions_processed,
		"graybox_produced": units_produced,
		"graybox_consumed": units_consumed,
		"graybox_entities_created": entities_created,
	}
