## Global ECS -> viewer/UI signal bus.
##
## MUST `extends Node`: Godot refuses to instantiate an autoload whose script does not
## inherit from Node ("does not inherit from 'Node'").
##
## Direction is one-way. The ECS emits; the viewer and UI listen. Nothing that listens here
## may mutate ECS state (Prime Directive / invariants §2).
##
## Handles are plain ints (ADR-19), so no signal parameter carries an object handle.
extends Node

signal entity_created(entity: int, tags: Array, initial_pos: Vector3)
signal entity_destroyed(entity: int)
signal entity_moved(entity: int, new_pos: Vector3)
signal chunk_state_changed(chunk_id: Vector3i, is_active: bool)
signal clock_advanced(hour: int, day: int, season: int, year: int)

## Emitted once per tick class so debug overlays can read durations without polling.
signal tick_completed(tick_class: StringName, duration_ms: float, entities_processed: int)

## Outcome events. Sprint 1 resolved melee, falls, deaths and pickups correctly and reported
## NONE of them, so from the player's seat a swing that hit and a swing that missed looked
## identical, and a 2.5 m drop was indistinguishable from a step. A simulation with no outcome
## feed cannot be play-tested — you can only read the source and hope.
signal entity_damaged(entity: int, amount: float, remaining: float, cause: StringName)
signal entity_died(entity: int, cause: StringName)
signal item_taken(taker: int, item: int, reason: StringName)
signal action_rejected(actor: int, action: StringName, reason: StringName)

## Every landing above walking speed, whether it hurt or not. A fall that deals no damage is a
## RESULT, not an absence of one: without it, "I fell and nothing happened" is indistinguishable
## from "the fall was never detected", which is exactly how the fall system looked while it was
## genuinely broken.
signal entity_landed(entity: int, speed_mps: float, damage: float)

## A faction changed its mind. Carries the DECLARATION so the feed can show what it said rather
## than only what it decided — the difference between a log line and a world that talks.
signal faction_decided(faction_id: int, objective: String, declaration: String)

## A leader just joined the reasoning queue (roadmap review F1: the "thinking" bark). Emitted at
## SUBMIT, not at dispatch, because the requirement is that deliberation is visible the moment it
## starts — the async answer replaces it via `faction_decided` whenever it lands. `is_crisis`
## lets the feed distinguish an emergency from the weekly review.
signal faction_thinking(faction_id: int, is_crisis: bool)

## The run ended. Carries the CORPSE handle, not the old player handle: row 0's generation has
## been bumped, so the old handle is deliberately dead by the time anyone reads this.
signal player_died(corpse: int, killer: int, lineage_generation: int)
signal player_reborn(player: int, lineage_generation: int)

## The player used a stairwell. A SUCCESS deserves its own signal: reporting it through
## `action_rejected` produced "stairs refused - you are now on floor -1", which is gibberish
## assembled from a template that only ever meant to describe failures.
signal player_changed_floor(from_floor: int, to_floor: int)

## Magic, reported like everything else. A cast that resolves silently is indistinguishable from
## one that was never registered, which is the failure mode this bus was added for in Sprint 1.
## `reason` is empty on success and names the refusal otherwise (not enough stamina, fizzled for
## want of an environmental resource, compilation refused).
signal spell_bound(caster: int, spell_id: StringName, ok: bool, reason: StringName)
signal spell_cast(caster: int, spell_id: StringName, strain: float)
signal spell_detonated(caster: int, spell_id: StringName, at: Vector3)

## A permanent physiological change. Its own signal rather than a feed line, because the faction
## reputation path and the UI both need it and neither should have to poll `BodyComponent`.
signal entity_mutated(entity: int, mutation: StringName)


## A faction's opinion of another crossed a threshold. Carries the score so the feed can say how
## bad it is, and `now_hostile` so it can say what changed rather than just that something did.
signal faction_relationship_changed(
	faction_id: int, about_faction: int, score: float, now_hostile: bool
)

## Succession (factions doc §3): the leader died and the highest-prestige member took over.
## A story beat the feed must carry — a decapitated faction recovering is the entire point of
## the mechanic, and invisibly recovering is indistinguishable from never having been hurt.
signal faction_leader_succeeded(faction_id: int, new_leader: int, prestige: float)

## The Schism Mechanic: disloyal citizens broke away as a new faction, at war with the old one.
signal faction_schism(parent_faction: int, splinter_faction: int, defectors: int)

## Trade caravans (factions doc §4). Departure and arrival are separate signals because the gap
## between them is where interception lives — a caravan that leaves and never arrives is the
## player-facing event, and one signal could not express it.
signal caravan_departed(from_faction: int, to_faction: int, carrier: int)
signal caravan_arrived(from_faction: int, to_faction: int, material: StringName, quantity: int)
signal caravan_lost(from_faction: int, to_faction: int)


## Tag arrays are `Array[StringName]`. Emitting an untyped array literal into a typed
## parameter fails at runtime and SILENTLY DROPS THE LISTENER, so build tags explicitly:
##     var tags: Array[StringName] = [&"Burning"]
## Rather than rely on every caller remembering, this bus takes an untyped `Array` and
## validates in debug builds.
func emit_entity_created(entity: int, tags: Array, initial_pos: Vector3) -> void:
	assert(_tags_are_string_names(tags), "entity tags must be StringName values")
	entity_created.emit(entity, tags, initial_pos)


func _tags_are_string_names(tags: Array) -> bool:
	for tag in tags:
		if typeof(tag) != TYPE_STRING_NAME:
			return false
	return true
