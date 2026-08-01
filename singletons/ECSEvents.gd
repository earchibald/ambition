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
