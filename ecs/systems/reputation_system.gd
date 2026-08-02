## Consequences (Sprint 3.5, "The Body Politic").
##
## The gap this closes was the most-reported thing in play-testing: you could kill a villager in
## the middle of their own village and NOTHING happened. Not because the machinery was missing —
## `PerceptionSystem.report_crime` existed, built and tested, with no caller — but because the
## chain from "someone saw that" to "their people hold it against you" was never joined up.
##
## THE CHAIN, and why each link exists separately:
##   1. An action is REPORTED as witnessable. Combat does this; nothing global watches the world.
##   2. Perception decides WHO SAW IT — line of sight, distance, confidence. No omniscience.
##   3. This system turns each witness into a GRIEVANCE against the offender's faction.
##   4. Gossip spreads the memory to people who were not there, over time.
##   5. The reasoner reads the resulting relationship and changes what the faction does.
##
## REPUTATION IS PER FACTION PAIR, not global. "The world hates you" is a much duller thing than
## "the village hates you and the goblins are delighted".
class_name ReputationSystem
extends RefCounted

## Score change per witnessed act, before confidence weighting. Murder is an order of magnitude
## worse than theft on purpose: a scale where everything is -10 cannot express escalation.
const SEVERITY: Dictionary = {
	&"MURDER": -45.0,
	&"ASSAULT": -18.0,
	&"THEFT": -12.0,
	&"TRESPASS": -4.0,
}

## MUTATION IS NOT A CRIME, and it is the first act whose severity depends on WHO SAW IT.
##
## Every other entry in `SEVERITY` is a constant because murder is murder to everybody. A player
## sprouting fungal lungs is a defilement to the Surface Village and a sign of favour to the
## Spore-Lord's people, so the delta is looked up against the WITNESS faction's own
## `culture_tags` (review D3). Getting this wrong in the obvious direction — one global number —
## would make the mutation path just another way to be hated, which is the opposite of the
## design: the environment is meant to be a skill tree with a social cost, not a penalty.
const MUTATION_PREFIX: String = "MUTATION_"
const MUTATION_KINSHIP: float = 14.0
const MUTATION_REVULSION: float = -16.0

## Culture tag that makes a faction welcome a given mutation track.
##
## THESE ARE REAL TAGS FROM `DAGGenerator.CULTURES`, and the first draft of this table was not:
## it invented `CULTURE_FUNGAL` and three siblings that no generated faction has ever carried, so
## every branch below it was unreachable and the whole affinity mechanism would have been a
## constant `MUTATION_REVULSION` wearing a lookup table. That is this codebase's signature defect
## and it was caught by grepping for a second reference rather than by any test.
## `test_every_mutation_affinity_names_a_real_culture` now fails if the two drift apart.
##
## Read in play: the goblins (Raiding/Scavenging) warm to you as you rot; the Cult
## (Ritual/Secrecy) welcomes what the arcane does to you; the Dwarves and the Human village are
## revolted by all four.
const MUTATION_AFFINITY: Dictionary = {
	&"MUTATION_FUNGAL": &"Scavenging",
	&"MUTATION_FILTH": &"Scavenging",
	&"MUTATION_TOXIC": &"Ritual",
	&"MUTATION_ARCANE": &"Ritual",
}

## Above this magnitude an event is worth repeating, so gossip carries it. Previously only
## MURDER travelled, which meant a witnessed mutation — the entire propagation mechanism the
## Sprint 4 faction shift is specified to use — would have stayed with whoever happened to be
## looking.
const GOSSIP_WORTHY: float = 10.0

## Relationship score bounds (registry §4).
const SCORE_MIN: float = -100.0
const SCORE_MAX: float = 100.0

## Canonical faction memory cap (factions doc: `FACTION_MEMORY_CAP: int = 64`). Was 24, which
## matched nothing in any document.
const FACTION_MEMORY_CAP: int = 64

## Below this a faction treats you as an enemy; above it, a friend.
const HOSTILE_BELOW: float = -40.0
const FRIENDLY_ABOVE: float = 40.0
## Above this, friendship hardens into alliance. The band between FRIENDLY_ABOVE and here is
## TRADE — which existed in the enum since Sprint 2 and was UNREACHABLE by construction, so the
## factions doc's "at high reputation the player is granted Trade status" and the entire
## caravan mechanism were dead on arrival. Trade is deliberately easier to earn than alliance:
## commerce precedes trust.
const ALLIED_ABOVE: float = 75.0

## A witness only tells people they are actually near. Gossip is a conversation, not a broadcast.
const GOSSIP_RANGE_M: float = 8.0

## Memories spread per Simulation tick, across the whole world. Bounded so a crowded village
## cannot turn one murder into thousands of dictionary writes in a single tick.
const MAX_GOSSIP_PER_TICK: int = 24

var grievances_recorded: int = 0
var gossip_spread: int = 0
var factions_turned_hostile: int = 0
var guest_status_revoked: int = 0


## Turns this tick's witnesses into grievances.
func run(perception: PerceptionSystem) -> void:
	for event in perception.take_witness_events():
		_record(event)


## One witness, one grievance against the offender's faction, weighted by how well it was seen.
##
## Confidence matters: a murder glimpsed at the edge of vision at dusk should not carry the same
## weight as one committed in someone's face, or every crime becomes equally unforgivable and
## stealth stops meaning anything.
func _record(event: WitnessEvent) -> void:
	var observer_row: int = ECSManager.resolve(event.observer)
	var subject_row: int = ECSManager.resolve(event.subject)
	if observer_row < 0 or subject_row < 0:
		return

	var witness_faction: int = _faction_of(observer_row)
	var offender_faction: int = _faction_of(subject_row)
	if witness_faction < 0 or offender_faction < 0 or witness_faction == offender_faction:
		# A faction does not file grievances against itself. Internal crime is a schism problem,
		# and schism is a different mechanism from diplomacy.
		return

	var core: FactionCoreComponent = DAGInstantiator.faction_core(witness_faction)
	if core == null:
		return

	# AFTER the faction lookup, not before: a mutation's severity depends on the witness's
	# culture, so it cannot be computed until we know whose culture it is.
	var severity: float = severity_for(event.action, core) * event.confidence
	if is_zero_approx(severity):
		return
	var before: float = relationship_score(core, offender_faction)
	adjust(core, offender_faction, severity, event.action)
	grievances_recorded += 1

	# A WITNESSED crime revokes Guest_Status (the other half of the perception invariant "an
	# unseen crime does not revoke Guest_Status", which shipped with no revoking half at all).
	# Only real offences: a welcomed mutation is kinship, not a crime.
	if (
		offender_faction == WorldConstants.PLAYER_FACTION_ID
		and severity < 0.0
		and not String(event.action).begins_with(MUTATION_PREFIX)
	):
		var player_chemistry: ChemistryComponent = ECSManager.chemistries.get(
			WorldConstants.PLAYER_INDEX
		)
		if player_chemistry != null and player_chemistry.has_tag(&"Guest_Status"):
			player_chemistry.remove_tag(&"Guest_Status")
			guest_status_revoked += 1

	if before > HOSTILE_BELOW and relationship_score(core, offender_faction) <= HOSTILE_BELOW:
		factions_turned_hostile += 1
		ECSEvents.faction_relationship_changed.emit(
			witness_faction, offender_faction, relationship_score(core, offender_faction), true
		)

	# The faction REMEMBERS, not just scores. The reasoner reads memory for context, and a bare
	# number cannot tell it what happened.
	#
	# The text is DERIVED from the action and `core` is derived from how big the event was. The
	# old version had one special case for MURDER and filed everything else as a theft that never
	# travelled — so an assault was remembered wrongly AND stayed with its only witness.
	var record: MemoryEvent = MemoryEvent.create(
		StringName("WITNESSED_%s" % event.action),
		event.action,
		GameClock.total_hours(),
		absf(severity) >= GOSSIP_WORTHY
	)
	record.subject = event.subject
	_remember_for_faction(core, record)


## How badly one faction takes one act. Constant for crime; culture-dependent for mutation.
##
## Static and public so the Grimoire, the inspector, and the tests can ask the same question the
## system asks, rather than each re-deriving it — which is how the answers drift apart.
static func severity_for(action: StringName, witness: FactionCoreComponent) -> float:
	if not String(action).begins_with(MUTATION_PREFIX):
		return float(SEVERITY.get(action, -5.0))
	var affinity: StringName = MUTATION_AFFINITY.get(action, &"")
	if witness != null and affinity != &"" and witness.culture_tags.has(affinity):
		return MUTATION_KINSHIP
	return MUTATION_REVULSION


## Moves one relationship and records the grievance behind it.
static func adjust(
	core: FactionCoreComponent, other_faction: int, delta: float, reason: StringName
) -> void:
	var state: Dictionary = core.diplomacy.get(other_faction, _fresh_relationship())
	state["score"] = clampf(float(state["score"]) + delta, SCORE_MIN, SCORE_MAX)
	state["status"] = status_for(float(state["score"]))
	if delta < 0.0:
		var grievances: Array = state["grievances"]
		grievances.append(reason)
		# Bounded: a grudge list that grows forever is a memory leak with a narrative excuse.
		while grievances.size() > 8:
			grievances.pop_front()
	core.diplomacy[other_faction] = state
	core.prune_diplomacy()


static func relationship_score(core: FactionCoreComponent, other_faction: int) -> float:
	return float(core.diplomacy.get(other_faction, _fresh_relationship())["score"])


static func status_for(score: float) -> ECSEnums.RelationshipStatus:
	if score <= HOSTILE_BELOW:
		return ECSEnums.RelationshipStatus.WAR
	if score >= ALLIED_ABOVE:
		return ECSEnums.RelationshipStatus.ALLIED
	if score >= FRIENDLY_ABOVE:
		return ECSEnums.RelationshipStatus.TRADE
	return ECSEnums.RelationshipStatus.NEUTRAL


static func is_hostile_to(faction_id: int, other_faction: int) -> bool:
	var core: FactionCoreComponent = DAGInstantiator.faction_core(faction_id)
	if core == null:
		return false
	return relationship_score(core, other_faction) <= HOSTILE_BELOW


## GOSSIP. Spreads what one person saw to people who were not there.
##
## Not a broadcast, and not instant (review D3). A witness tells whoever is standing near them,
## and those people tell others later — so a murder in a back alley takes time to reach the
## guards, and one committed in the square does not.
##
## Deduplicated by `event_id`, which is why MemoryEvent carries a globally unique one. Without it
## two neighbours re-tell each other the same story forever and every memory list grows without
## bound.
func spread_gossip(hash: SpatialHash) -> void:
	var budget: int = MAX_GOSSIP_PER_TICK
	for row in ECSManager.query(ComponentMask.MEMORY):
		if budget <= 0:
			return
		var memory: MemoryComponent = ECSManager.memories[row]
		if memory.events.is_empty():
			continue
		var teller_faction: int = _faction_of(row)
		if teller_faction < 0:
			continue

		var listeners: PackedInt32Array = hash.query_radius(
			ECSManager.position_of(row), GOSSIP_RANGE_M
		)
		for i in listeners.size():
			if budget <= 0:
				return
			var listener: int = listeners[i]
			if listener == row or _faction_of(listener) != teller_faction:
				continue
			var heard: MemoryComponent = ECSManager.memories.get(listener)
			if heard == null:
				continue
			for event in memory.events:
				if not event.core:
					# Only things that MATTER travel. Idle chat staying local is why the memory
					# lists do not converge on identical contents across a whole village.
					continue
				if _already_knows(heard, event.event_id):
					continue
				heard.remember(event)
				gossip_spread += 1
				budget -= 1
				break


static func _already_knows(memory: MemoryComponent, event_id: int) -> bool:
	for known in memory.events:
		if known.event_id == event_id:
			return true
	return false


static func _remember_for_faction(core: FactionCoreComponent, record: MemoryEvent) -> void:
	for known in core.faction_memory:
		if int(known.get("event_id", -1)) == record.event_id:
			return
	core.faction_memory.append({
		"event_id": record.event_id,
		"text": String(record.text),
		"tick": record.tick_hours,
		# The BASE weight. At insertion age is zero, so `weight_at(now)` returns exactly this —
		# the old call was not wrong, it was misleading: it looked like decay was involved and
		# it never was. Decay happens at read (`PromptBuilder.decayed_weight`), where age exists.
		"weight": MemoryEvent.base_weight(record.kind),
		"core": record.core,
	})
	# The faction's memory is a summary, not an archive — but eviction follows the CANONICAL
	# policy (factions doc: cap 64, evict the lowest-weight NON-CORE entry). This was cap 24
	# with FIFO, which silently pushed a core witnessed murder out after 24 ordinary events —
	# the exact guarantee (`core memories survive overflow`) the entity-side store enforces.
	if core.faction_memory.size() <= FACTION_MEMORY_CAP:
		return
	var now: int = GameClock.total_hours()
	var worst_index: int = -1
	var worst_weight: float = INF
	for i in core.faction_memory.size():
		var memory: Dictionary = core.faction_memory[i]
		if bool(memory.get("core", false)):
			continue
		var weight: float = PromptBuilder.decayed_weight(memory, now)
		if weight < worst_weight:
			worst_weight = weight
			worst_index = i
	# All-core overflow evicts the oldest core memory: a hard cap that can be exceeded is not
	# a cap, and the oldest is the least likely to still be shaping decisions.
	core.faction_memory.remove_at(worst_index if worst_index >= 0 else 0)


static func _faction_of(row: int) -> int:
	if row == WorldConstants.PLAYER_INDEX:
		return WorldConstants.PLAYER_FACTION_ID
	var identity: SocialIdentityComponent = ECSManager.social_identities.get(row)
	return -1 if identity == null else identity.faction_id


static func _fresh_relationship() -> Dictionary:
	return {"score": 0.0, "status": ECSEnums.RelationshipStatus.NEUTRAL, "grievances": []}


func counters() -> Dictionary:
	return {
		"grievances": grievances_recorded,
		"gossip_spread": gossip_spread,
		"factions_turned_hostile": factions_turned_hostile,
		"guest_status_revoked": guest_status_revoked,
	}
