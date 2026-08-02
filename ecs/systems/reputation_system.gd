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

## Relationship score bounds (registry §4).
const SCORE_MIN: float = -100.0
const SCORE_MAX: float = 100.0

## Below this a faction treats you as an enemy; above it, a friend.
const HOSTILE_BELOW: float = -40.0
const FRIENDLY_ABOVE: float = 40.0

## A witness only tells people they are actually near. Gossip is a conversation, not a broadcast.
const GOSSIP_RANGE_M: float = 8.0

## Memories spread per Simulation tick, across the whole world. Bounded so a crowded village
## cannot turn one murder into thousands of dictionary writes in a single tick.
const MAX_GOSSIP_PER_TICK: int = 24

var grievances_recorded: int = 0
var gossip_spread: int = 0
var factions_turned_hostile: int = 0


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
	var severity: float = float(SEVERITY.get(event.action, -5.0)) * event.confidence
	if is_zero_approx(severity):
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
	var before: float = relationship_score(core, offender_faction)
	adjust(core, offender_faction, severity, event.action)
	grievances_recorded += 1

	if before > HOSTILE_BELOW and relationship_score(core, offender_faction) <= HOSTILE_BELOW:
		factions_turned_hostile += 1
		ECSEvents.faction_relationship_changed.emit(
			witness_faction, offender_faction, relationship_score(core, offender_faction), true
		)

	# The faction REMEMBERS, not just scores. The reasoner reads memory for context, and a bare
	# number cannot tell it what happened.
	var record: MemoryEvent = MemoryEvent.create(
		&"WITNESSED_MURDER" if event.action == &"MURDER" else &"WITNESSED_THEFT",
		event.action,
		GameClock.total_hours(),
		event.action == &"MURDER"
	)
	record.subject = event.subject
	_remember_for_faction(core, record)


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
	if score >= FRIENDLY_ABOVE:
		return ECSEnums.RelationshipStatus.ALLIED
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
		"weight": record.weight_at(GameClock.total_hours()),
		"core": record.core,
	})
	# The faction's memory is a summary, not an archive. The prompt builder only ever reads the
	# top few anyway, and an unbounded list is what makes a save file grow forever.
	while core.faction_memory.size() > 24:
		core.faction_memory.pop_front()


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
	}
