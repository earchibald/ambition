## A faction's abstract self (registry §7). One per faction, on a single macro-entity.
##
## THIS IS THE LEDGER. When a faction's territory is Abstracted, its wealth exists only as
## integers here — the roadmap's Step 5 rule is explicit that off-screen economies must never
## instantiate physical items, because a hundred factions each minting item entities every Macro
## tick is how a simulation of this shape runs out of memory.
##
## The ledger is therefore the ONLY place faction wealth is counted while a chunk is not Active,
## and physical stacks are the only place it is counted while a chunk IS Active. Value must never
## exist in both at once: that is precisely the boundary-oscillation duplication window (review
## D1), and `ChunkData.wealth_materialized` is the guard.
class_name FactionCoreComponent
extends RefCounted

## ADR-12. Diplomacy is capped at top-K relationships; the rest are treated as NEUTRAL rather
## than stored, so the dictionary cannot grow quadratically with faction count.
const DIPLOMACY_TOP_K: int = 12

var faction_id: int = -1
var culture_tags: Array[StringName] = []
var diplomacy: Dictionary = {}
var abstract_wealth_ledger: Dictionary = {}
var abstract_population: int = 0
var faction_memory: Array = []

## The chunk this faction calls home. Populations materialize HERE, never at the world origin.
var anchor_chunk_id: Vector3i = DAGNode.NO_ANCHOR

## The DAG node this was built from, so "why does this faction exist" stays answerable at runtime.
var dag_node_id: int = -1

## What this faction is currently trying to do. Set by the reasoner (Sprint 3C) and read by the
## planner; IDLE until something decides otherwise, which is a real state rather than an absence.
var current_objective: ECSEnums.Objective = ECSEnums.Objective.IDLE
var current_emotion: ECSEnums.Emotion = ECSEnums.Emotion.CALM
## Last thing this faction said out loud, for the event feed and later for barks.
var last_declaration: String = ""
## Who the current objective is aimed at, or -1. Validated before it lands here: an unverified
## target is how a faction marches on ground where nobody lives.
var objective_target: int = -1


static func from_dag_node(node: DAGNode) -> FactionCoreComponent:
	var core := FactionCoreComponent.new()
	core.faction_id = node.node_id
	core.dag_node_id = node.node_id
	core.culture_tags = node.culture_tags.duplicate()
	core.abstract_wealth_ledger = node.abstract_wealth_ledger.duplicate()
	core.abstract_population = node.population
	core.anchor_chunk_id = node.anchor_chunk_id
	return core


func ledger_total() -> int:
	var total: int = 0
	for material in abstract_wealth_ledger:
		total += int(abstract_wealth_ledger[material])
	return total


func add_wealth(material: StringName, amount: int) -> void:
	var next: int = int(abstract_wealth_ledger.get(material, 0)) + amount
	# The ledger is unsigned by contract. A negative entry means a dematerialization pass
	# double-counted, and silently clamping it would hide the duplication bug it signals.
	assert(next >= 0, "faction ledger went negative for %s" % material)
	abstract_wealth_ledger[material] = maxi(0, next)


## Removes up to `amount` and returns what was actually taken, so a caller can never withdraw
## more than exists. Materialization uses this: spawning stacks worth more than the ledger held
## is the infinite-gold exploit in its simplest form.
func withdraw(material: StringName, amount: int) -> int:
	var held: int = int(abstract_wealth_ledger.get(material, 0))
	var taken: int = mini(held, maxi(0, amount))
	abstract_wealth_ledger[material] = held - taken
	return taken


func withdraw_all() -> Dictionary:
	var taken: Dictionary = abstract_wealth_ledger.duplicate()
	abstract_wealth_ledger.clear()
	return taken


## Keeps only the strongest K relationships (ADR-12). Everything else is NEUTRAL by omission.
func prune_diplomacy() -> void:
	if diplomacy.size() <= DIPLOMACY_TOP_K:
		return
	var ids: Array = diplomacy.keys()
	# Tie-broken by faction id. `sort_custom` is not stable, so comparing |score| alone let two
	# equally-strong relationships evict each other differently run to run — and this decides
	# which relationships a faction KEEPS, so a tie was a silent, unreproducible data loss.
	ids.sort_custom(
		func(a: int, b: int) -> bool:
			var strength_a: float = absf(diplomacy[a]["score"])
			var strength_b: float = absf(diplomacy[b]["score"])
			if not is_equal_approx(strength_a, strength_b):
				return strength_a > strength_b
			return a < b
	)
	for i in range(DIPLOMACY_TOP_K, ids.size()):
		diplomacy.erase(ids[i])
