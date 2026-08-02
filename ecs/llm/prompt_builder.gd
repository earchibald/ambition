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

## How long a violent memory keeps a faction in "crisis". Two in-game weeks: long enough that a
## running war stays a war, short enough that a grudge from year 300 is not an emergency.
const ATTACK_MEMORY_WINDOW_HOURS: int = 336

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
	if not context["leader_memories"].is_empty():
		lines.append("What you personally lived through:")
		for memory in context["leader_memories"]:
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
		"recently_attacked": was_recently_attacked(core),
		"memories": salient_memories(core),
		# What the LEADER personally lived through (roadmap Step 2, declared gap G-8). Faction
		# memory is the institutional record; a leader who watched their predecessor die knows
		# things the institution never wrote down, and gossip only ever lands on individuals.
		"leader_memories": leader_memories(core),
		"valid_targets": valid_targets(core, generator),
	}


## Top-3 by weight plus the 3 most recent, de-duplicated. Sending the whole history is how a
## per-call cost becomes unbounded.
##
## TOTALLY ORDERED, and it was not until 2026-08-01. Both sorts compared one field, and
## `sort_custom` is not stable, so two memories of equal weight could come back in either order.
## That is not cosmetic: it changes WHICH THREE ARE SELECTED, so identical world state could
## produce different prompts run to run. It breaks ADR-20's reproduce-from-seed requirement, and
## it silently defeats the response cache in `ReasoningQueue`, which keys on the prompt hash — a
## cache that misses on identical state is a paid call that should not have happened.
## Tie-break to `event_id`, which is globally unique, so the order is total and no tie remains.
static func salient_memories(core: FactionCoreComponent) -> Array[String]:
	var chosen: Array[String] = []
	var seen: Dictionary = {}

	var by_weight: Array = core.faction_memory.duplicate()
	by_weight.sort_custom(_more_salient)
	for i in mini(TOP_MEMORIES, by_weight.size()):
		_append_memory(by_weight[i], chosen, seen)

	# Most recent = highest tick. Recency and weight overlap often, hence the dedup.
	var by_tick: Array = core.faction_memory.duplicate()
	by_tick.sort_custom(_more_recent)
	for i in mini(RECENT_MEMORIES, by_tick.size()):
		_append_memory(by_tick[i], chosen, seen)
	return chosen


## DECAYED weight, then recency, then the unique id. Every comparison ends in a strict decision.
##
## Decay is applied HERE, at read time. The stored "weight" is the base weight — it was
## snapshotted at insertion, when age is zero and falloff is exactly 1.0 — so sorting on it
## directly meant faction memory NEVER decayed: a murder from year 1 outranked everything in the
## leader's prompt forever, while the identical event in an individual's `MemoryComponent`
## faded on its 72-hour half-life. One decay model, applied to both stores, evaluated at the
## moment of the question, which is the only moment age is knowable.
static func _more_salient(a: Dictionary, b: Dictionary) -> bool:
	var now: int = GameClock.total_hours()
	var weight_a: float = decayed_weight(a, now)
	var weight_b: float = decayed_weight(b, now)
	if not is_equal_approx(weight_a, weight_b):
		return weight_a > weight_b
	var tick_a: int = int(a.get("tick", 0))
	var tick_b: int = int(b.get("tick", 0))
	if tick_a != tick_b:
		return tick_a > tick_b
	return int(a.get("event_id", 0)) < int(b.get("event_id", 0))


## The same falloff and core floor as `MemoryEvent.weight_at`, for the dictionary-shaped
## records `faction_memory` holds. Public because eviction in `ReputationSystem` must rank by
## the same number the prompt ranks by, or the two disagree about which memory matters least.
static func decayed_weight(memory: Dictionary, now_hours: int) -> float:
	var age: float = maxf(0.0, float(now_hours - int(memory.get("tick", 0))))
	var falloff: float = pow(0.5, age / MemoryEvent.HALF_LIFE_H)
	if bool(memory.get("core", false)):
		falloff = maxf(MemoryEvent.CORE_FLOOR, falloff)
	return float(memory.get("weight", 0.0)) * falloff


## Recency, then weight, then the unique id.
static func _more_recent(a: Dictionary, b: Dictionary) -> bool:
	var tick_a: int = int(a.get("tick", 0))
	var tick_b: int = int(b.get("tick", 0))
	if tick_a != tick_b:
		return tick_a > tick_b
	var weight_a: float = float(a.get("weight", 0.0))
	var weight_b: float = float(b.get("weight", 0.0))
	if not is_equal_approx(weight_a, weight_b):
		return weight_a > weight_b
	return int(a.get("event_id", 0)) < int(b.get("event_id", 0))


## The current leader's own most salient memories, as text. Empty when the faction is abstract
## or leaderless — which is a real state, not an error, so no warning is pushed.
static func leader_memories(core: FactionCoreComponent) -> Array[String]:
	var out: Array[String] = []
	if not ECSManager.is_alive(core.leader_handle):
		return out
	var memory: MemoryComponent = ECSManager.memories.get(ECSManager.resolve(core.leader_handle))
	if memory == null:
		return out
	for event in memory.most_salient(TOP_MEMORIES):
		out.append(String(event.text))
	return out


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
## "RECENTLY" NOW MEANS RECENTLY. This checked only whether a violent memory existed anywhere in
## the list, so a murder stayed "recent" until it aged out of the 24-entry cap — which, for a
## quiet faction, is never. That was harmless while the flag only coloured a prompt; it stopped
## being harmless when the flag became the crisis trigger for reasoning cadence, where a
## permanent crisis means a permanently elevated request rate.
##
## Case-insensitive because these strings come from two writers: `ReputationSystem` emits
## `WITNESSED_MURDER`, and the DAG chronicle writes prose.
static func was_recently_attacked(core: FactionCoreComponent) -> bool:
	var now: int = GameClock.total_hours()
	for memory in core.faction_memory:
		var kind: String = String(memory.get("text", "")).to_upper()
		if not (kind.contains("MURDER") or kind.contains("ASSAULT") or kind.contains("ATTACK")):
			continue
		if now - int(memory.get("tick", 0)) <= ATTACK_MEMORY_WINDOW_HOURS:
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
