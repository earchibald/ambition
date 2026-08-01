## Generates the 500-year history graph, in memory, before anything is rendered.
##
## This runs FIRST in the boot sequence (roadmap Step 6) because everything downstream reads it:
## world generation places factions at the anchors this assigns, and the instantiator turns the
## surviving nodes into entities. It never touches the ECS, a chunk, or a scene node.
##
## STRICTLY BOUNDED, three ways, because an unbounded history generator is an unbounded startup
## time and this sits directly in front of the player on every cold boot:
##   * `MAX_EPOCHS` caps the loop.
##   * `FACTION_CAP` (ADR-12) caps live factions; excess founding attempts are simply skipped.
##   * Every per-epoch event count is a fixed small integer, never "while something is true".
##
## DETERMINISTIC from the master seed via the `dag` RNG stream. ADR-1 makes no determinism
## promise for the RUNNING world, but history generation happens before any unreproducible input
## exists, so it costs nothing to keep this reproducible — and a soak harness that cannot
## regenerate the same history cannot compare anything (ADR-20).
class_name DAGGenerator
extends RefCounted

## 50 epochs of roughly a decade each is the "500 years" the roadmap asks for.
const MAX_EPOCHS: int = 50
const YEARS_PER_EPOCH: int = 10

## ADR-12. Beyond this, founding attempts are skipped rather than merged: merging invents
## history that never happened, and skipping is honest about the cap.
const FACTION_CAP: int = 24

## Floors a faction may call home. 0 is the surface village; negatives are dungeon depth.
const DEEPEST_FLOOR: int = -5

## The Day 0 village. Big enough to feel inhabited and to stock a starting economy, small enough
## that the whole thing can be Pre-Warmed synchronously without blowing the boot budget.
const VILLAGE_POPULATION: int = 28

## Per-epoch event odds. Founding is deliberately LOWER than conquest: with founding above the
## conquest rate the graph only ever grows, every run ends pinned against the ADR-12 cap, and
## 500 years of history produces no ruins to explore — which is most of the point of having it.
const FOUND_CHANCE: float = 0.32
const CONQUEST_CHANCE: float = 0.55
const ARTIFACT_CHANCE: float = 0.20

## No conquest before this epoch. The first few centuries need to produce something worth
## fighting over.
const FIRST_CONQUEST_EPOCH: int = 5

## Cultures are seeded, not generated. One worked example per archetype is Sprint 2 scope; the
## per-culture language and full trait model are explicitly post-1.0 (scope doc §5).
const CULTURES: Array[Dictionary] = [
	{
		"name": &"Dwarven",
		"tags": [&"Mining", &"Stoneworking"],
		"materials": [&"MAT_IRON", &"MAT_STONE"],
		"aggression": 0.25,
		"prefers_deep": true,
	},
	{
		"name": &"Goblin",
		"tags": [&"Raiding", &"Scavenging"],
		"materials": [&"MAT_COPPER", &"MAT_BIOMASS"],
		"aggression": 0.75,
		"prefers_deep": true,
	},
	{
		"name": &"Human",
		"tags": [&"Farming", &"Trade"],
		"materials": [&"MAT_BIOMASS", &"MAT_CLOTH"],
		"aggression": 0.30,
		"prefers_deep": false,
	},
	{
		"name": &"Cult",
		"tags": [&"Ritual", &"Secrecy"],
		"materials": [&"MAT_SULFUR", &"MAT_COPPER"],
		"aggression": 0.55,
		"prefers_deep": true,
	},
]

var nodes: Dictionary = {}
var edges: Array[DAGEdge] = []
var current_epoch: int = 0
var chronicle: Array[String] = []

var _next_node_id: int = 1


## Runs the whole history and returns the nodes still standing at the end.
func run_history_generation() -> Array[DAGNode]:
	nodes.clear()
	edges.clear()
	chronicle.clear()
	_next_node_id = 1

	# The surface village always exists and always survives: it is the player's Day 0 anchor and
	# the Pre-Warm depends on it being there. History happens AROUND it, not to it.
	var village: DAGNode = _found_faction(VILLAGE_POPULATION, 0, true)
	village.tags.append(&"SurfaceVillage")

	for epoch in MAX_EPOCHS:
		current_epoch = epoch
		_process_epoch()
	return get_active_world_state()


## The nodes an implementer actually wants: alive, and therefore worth turning into entities.
func get_active_world_state() -> Array[DAGNode]:
	var out: Array[DAGNode] = []
	for id in nodes:
		var node: DAGNode = nodes[id]
		if node.is_active():
			out.append(node)
	out.sort_custom(func(a: DAGNode, b: DAGNode) -> bool: return a.node_id < b.node_id)
	return out


func active_factions() -> Array[DAGNode]:
	return get_active_world_state().filter(
		func(n: DAGNode) -> bool: return n.type == ECSEnums.NodeType.FACTION
	)


func node_by_id(node_id: int) -> DAGNode:
	return nodes.get(node_id)


## Edges are the record of WHY. Kept queryable so the chronicle and, later, the LLM prompt
## builder can ask "what happened to this faction" without re-deriving it.
func edges_touching(node_id: int) -> Array[DAGEdge]:
	return edges.filter(
		func(e: DAGEdge) -> bool: return e.source_id == node_id or e.target_id == node_id
	)


func year_of(epoch: int) -> int:
	return epoch * YEARS_PER_EPOCH


## One epoch: at most one founding, at most one conquest, at most one artifact. Fixed counts
## keep the whole generation linear in MAX_EPOCHS.
func _process_epoch() -> void:
	if _roll() < FOUND_CHANCE:
		_found_faction(_roll_range(15, 60), _roll_floor(), false)
	if current_epoch >= FIRST_CONQUEST_EPOCH and _roll() < CONQUEST_CHANCE:
		_attempt_conquest()
	if _roll() < ARTIFACT_CHANCE:
		_forge_artifact()
	_grow_factions()


func _found_faction(population: int, floor_index: int, is_village: bool) -> DAGNode:
	var living: Array[DAGNode] = active_factions()
	if living.size() >= FACTION_CAP:
		# ADR-12: skip rather than merge. Merging fabricates a history that never happened.
		return null

	var culture: Dictionary = CULTURES[_roll_range(0, CULTURES.size() - 1)]
	if is_village:
		culture = CULTURES[2]

	var node := DAGNode.new()
	node.node_id = _next_node_id
	_next_node_id += 1
	node.type = ECSEnums.NodeType.FACTION
	node.birth_epoch = current_epoch
	node.population = population
	node.home_floor = 0 if is_village else floor_index
	node.name = StringName(
		"%s of %s" % [culture["name"], _place_name(node.node_id)]
	)
	for tag in culture["tags"]:
		node.culture_tags.append(tag)
	for material in culture["materials"]:
		node.add_wealth(material, _roll_range(40, 400))

	nodes[node.node_id] = node
	edges.append(
		DAGEdge.create(node.node_id, node.node_id, ECSEnums.EdgeType.FOUNDED, current_epoch)
	)
	_record(
		"Year %d: %s founded on floor %d with %d souls."
		% [year_of(current_epoch), node.name, node.home_floor, node.population]
	)
	return node


## An aggressive faction conquers a weaker neighbour on the same floor.
##
## The loser is marked DESTROYED but KEPT. Deleting it would erase the only explanation for why
## the winner holds that ground, and the DAG exists precisely to answer that question.
func _attempt_conquest() -> void:
	var living: Array[DAGNode] = active_factions()
	if living.size() < 2:
		return
	var aggressor: DAGNode = living[_roll_range(0, living.size() - 1)]
	if aggressor.tags.has(&"SurfaceVillage"):
		return
	if _roll() > _aggression_of(aggressor):
		return

	var victim: DAGNode = _weakest_rival_on_floor(aggressor)
	if victim == null:
		return

	victim.status = ECSEnums.NodeStatus.DESTROYED
	victim.death_epoch = current_epoch
	victim.conquered_by = aggressor.node_id

	# Spoils transfer. Wealth is not destroyed by conquest; it changes hands, which is what makes
	# the surviving faction rich and the ruin worth exploring.
	for material in victim.abstract_wealth_ledger:
		aggressor.add_wealth(material, int(victim.abstract_wealth_ledger[material]))
	victim.abstract_wealth_ledger.clear()
	aggressor.population += int(float(victim.population) * 0.25)

	edges.append(
		DAGEdge.create(
			aggressor.node_id, victim.node_id, ECSEnums.EdgeType.CONQUERED, current_epoch
		)
	)
	edges.append(
		DAGEdge.create(
			victim.node_id, victim.node_id, ECSEnums.EdgeType.DESTROYED, current_epoch
		)
	)
	_record(
		"Year %d: %s conquered %s in epoch %d."
		% [year_of(current_epoch), aggressor.name, victim.name, current_epoch]
	)


func _weakest_rival_on_floor(aggressor: DAGNode) -> DAGNode:
	var weakest: DAGNode = null
	for candidate in active_factions():
		if candidate.node_id == aggressor.node_id:
			continue
		if candidate.home_floor != aggressor.home_floor:
			continue
		if candidate.tags.has(&"SurfaceVillage"):
			continue
		if candidate.population >= aggressor.population:
			continue
		if weakest == null or candidate.population < weakest.population:
			weakest = candidate
	return weakest


func _forge_artifact() -> void:
	var living: Array[DAGNode] = active_factions()
	if living.is_empty():
		return
	var maker: DAGNode = living[_roll_range(0, living.size() - 1)]

	var artifact := DAGNode.new()
	artifact.node_id = _next_node_id
	_next_node_id += 1
	artifact.type = ECSEnums.NodeType.ARTIFACT
	artifact.birth_epoch = current_epoch
	artifact.home_floor = maker.home_floor
	artifact.name = StringName("The %s of %s" % [_artifact_noun(), _place_name(artifact.node_id)])
	artifact.tags.append(&"Artifact")

	nodes[artifact.node_id] = artifact
	edges.append(
		DAGEdge.create(maker.node_id, artifact.node_id, ECSEnums.EdgeType.FORGED, current_epoch)
	)
	_record("Year %d: %s forged %s." % [year_of(current_epoch), maker.name, artifact.name])


## Slow abstract growth so later epochs differ from earlier ones. Deliberately NOT the gray-box
## economy: that runs on the Macro tick during play (Step 5) and operates on live ECS ledgers.
func _grow_factions() -> void:
	for node in active_factions():
		node.population += _roll_range(0, 3)
		for material in node.abstract_wealth_ledger:
			node.abstract_wealth_ledger[material] = (
				int(node.abstract_wealth_ledger[material]) + _roll_range(0, 12)
			)


func _aggression_of(node: DAGNode) -> float:
	for culture in CULTURES:
		if node.culture_tags.has(culture["tags"][0]):
			return culture["aggression"]
	return 0.3


func _roll_floor() -> int:
	return -_roll_range(1, -DEEPEST_FLOOR)


func _place_name(salt: int) -> String:
	const STEMS: Array[String] = [
		"Karak", "Grimhold", "Ashfen", "Duskvale", "Ironmoor", "Blackreach", "Thornwick",
		"Greymarch", "Emberdeep", "Hollowfast",
	]
	return STEMS[salt % STEMS.size()]


func _artifact_noun() -> String:
	const NOUNS: Array[String] = ["Crown", "Hammer", "Seal", "Lantern", "Chalice"]
	return NOUNS[_roll_range(0, NOUNS.size() - 1)]


func _roll() -> float:
	return RNGService.randf_in(&"dag")


func _roll_range(from: int, to: int) -> int:
	return RNGService.randi_range_in(&"dag", from, to)


func _record(line: String) -> void:
	chronicle.append(line)


## The Step 1 success state: a printable history proving factions were founded, one conquered
## another in a specific epoch, and the survivor is still standing.
func chronicle_text() -> String:
	return "\n".join(chronicle)
