## Builds a leader's context at the instant the request fires (Sprint 3 Step 2).
##
## LAZY BY CONTRACT. The queue stores an entity id and NOTHING else. A prompt built when the
## request was enqueued describes a world that has since moved on — the roadmap calls this "Stale
## Context", and it is worse than no context: the leader reasons confidently about a siege that
## ended, or a neighbour that no longer exists.
##
## THE SALIENCE FILTER is a cost control with teeth. A 500-year history and a faction memory that
## grows every hour will happily fill a context window, and the bill is real money per call. Only
## the top-3 memories by decayed weight plus the 3 most recent go in.
##
## VALID TARGETS ARE ENUMERATED EXPLICITLY, with integer ids. Without the list the model invents
## plausible faction numbers, and every invented id is a hallucination the Validation Gate then
## has to catch. Listing them turns most of that class of error into an impossibility.
class_name PromptBuilder
extends RefCounted

## Separates the human-readable brief from the machine-readable block. The heuristic provider
## parses what follows this, so both providers read ONE context, built once.
const CONTEXT_MARKER: String = "\n---CONTEXT---\n"

const TOP_MEMORIES: int = 3
const RECENT_MEMORIES: int = 3

## Hard ceiling on the brief. Cheap insurance against a memory text that is itself enormous.
const MAX_PROMPT_CHARS: int = 4000

const SCHEMA_INSTRUCTION: String = (
	"Reply with ONLY a JSON object with these exact keys: "
	+ "reason_summary (string, max 200 chars), "
	+ "objective (one of FORTIFY, RAID_FACTION, GATHER_RESOURCES, MIGRATE, IDLE), "
	+ "target_faction_id (integer, MUST be one of the Valid Targets ids, or -1), "
	+ "emotion_state (one of CALM, FEARFUL, AGGRESSIVE, DESPERATE), "
	+ "public_declaration (string, one short spoken line)."
)


## The whole prompt for one faction, built NOW.
static func build(faction_id: int, generator: DAGGenerator) -> String:
	var core: FactionCoreComponent = DAGInstantiator.faction_core(faction_id)
	if core == null:
		return ""
	var context: Dictionary = build_context(core, generator)

	var lines: Array[String] = []
	lines.append(
		"You are the leader of %s. Population %d." % [context["name"], context["population"]]
	)
	lines.append("Culture: %s." % ", ".join(context["culture"]))
	lines.append("Stores: %s." % _describe_ledger(core.abstract_wealth_ledger))
	if not context["memories"].is_empty():
		lines.append("Recent events you remember:")
		for memory in context["memories"]:
			lines.append("  - %s" % memory)
	lines.append("Valid Targets: %s" % _describe_targets(context["valid_targets"]))
	lines.append(SCHEMA_INSTRUCTION)

	var brief: String = "\n".join(lines)
	if brief.length() > MAX_PROMPT_CHARS:
		brief = brief.substr(0, MAX_PROMPT_CHARS)
	return brief + CONTEXT_MARKER + JSON.stringify(context)


## The machine-readable half. Both providers consume this, so the salience rule lives in exactly
## one place and cannot drift between the two brains.
static func build_context(core: FactionCoreComponent, generator: DAGGenerator) -> Dictionary:
	var node: DAGNode = null if generator == null else generator.node_by_id(core.dag_node_id)
	return {
		"faction_id": core.faction_id,
		"name": "Faction %d" % core.faction_id if node == null else String(node.name),
		"population": core.abstract_population,
		"culture": core.culture_tags.map(func(t: StringName) -> String: return String(t)),
		# Counted from WHEREVER it lives. Reading the ledger alone reports zero for any faction
		# whose chunk is Active, because promotion spent it into stacks — so every village the
		# player could see looked like it was starving.
		"food": ChunkStreamingSystem.owned_material_total(
			core.faction_id, MaterialLibrary.MAT_BIOMASS
		),
		"strength": strength_of(core),
		"recently_attacked": _was_recently_attacked(core),
		"memories": salient_memories(core),
		"valid_targets": valid_targets(core, generator),
	}


## Top-3 by weight plus the 3 most recent, de-duplicated. Sending the whole history is how a
## per-call cost becomes unbounded.
static func salient_memories(core: FactionCoreComponent) -> Array[String]:
	var chosen: Array[String] = []
	var seen: Dictionary = {}

	var by_weight: Array = core.faction_memory.duplicate()
	by_weight.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.get("weight", 0.0)) > float(b.get("weight", 0.0))
	)
	for i in mini(TOP_MEMORIES, by_weight.size()):
		_append_memory(by_weight[i], chosen, seen)

	# Most recent = highest tick. Recency and weight overlap often, hence the dedup.
	var by_tick: Array = core.faction_memory.duplicate()
	by_tick.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("tick", 0)) > int(b.get("tick", 0))
	)
	for i in mini(RECENT_MEMORIES, by_tick.size()):
		_append_memory(by_tick[i], chosen, seen)
	return chosen


## Neighbours this faction could plausibly act on, with their INTEGER ids. The player is always
## listed: they are Faction 0 (ADR-14) and are the most likely subject of a decision.
static func valid_targets(core: FactionCoreComponent, generator: DAGGenerator) -> Array:
	var out: Array = []
	out.append({
		"faction_id": WorldConstants.PLAYER_FACTION_ID,
		"name": "the adventurer",
		"strength": 1.0,
		"score": float(core.diplomacy.get(WorldConstants.PLAYER_FACTION_ID, {}).get("score", 0.0)),
	})
	if generator == null:
		return out
	for node in generator.active_factions():
		if node.node_id == core.faction_id:
			continue
		var other: FactionCoreComponent = DAGInstantiator.faction_core(node.node_id)
		if other == null:
			continue
		out.append({
			"faction_id": node.node_id,
			"name": String(node.name),
			"strength": strength_of(other),
			"score": float(core.diplomacy.get(node.node_id, {}).get("score", 0.0)),
		})
	return out


## A single comparable number, so "can we take them" is one division rather than a policy.
static func strength_of(core: FactionCoreComponent) -> float:
	return float(core.abstract_population) + float(
		ChunkStreamingSystem.owned_material_total(core.faction_id, MaterialLibrary.MAT_IRON)
	) * 0.05


## True when this faction has a fresh memory of being wronged. Read from faction memory rather
## than from the relationship score, because a score says WHO you dislike and a memory says
## whether something just happened — and "fortify NOW" is a response to the second.
static func _was_recently_attacked(core: FactionCoreComponent) -> bool:
	for memory in core.faction_memory:
		var kind: String = String(memory.get("text", ""))
		if kind.contains("MURDER") or kind.contains("ASSAULT") or kind.contains("attacked"):
			return true
	return false


static func _append_memory(memory: Dictionary, into: Array[String], seen: Dictionary) -> void:
	var id: int = int(memory.get("event_id", -1))
	if seen.has(id):
		return
	seen[id] = true
	into.append(String(memory.get("text", "")))


static func _describe_ledger(ledger: Dictionary) -> String:
	if ledger.is_empty():
		return "nothing"
	var parts: Array[String] = []
	for material in ledger:
		parts.append("%d %s" % [int(ledger[material]), material])
	return ", ".join(parts)


static func _describe_targets(targets: Array) -> String:
	var parts: Array[String] = []
	for target in targets:
		parts.append("[%d: %s]" % [int(target["faction_id"]), target["name"]])
	return " ".join(parts)
