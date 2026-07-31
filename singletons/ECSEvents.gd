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
