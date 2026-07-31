## A request to change the world. Input and UI produce these; the ECS resolves them.
##
## Nothing outside `ecs/` may mutate ECS state directly (Prime Directive). Pressing W does not
## move the player: it pushes a MOVE intent onto Entity 0's action queue.
class_name ActionIntent
extends RefCounted

const MOVE: StringName = &"MOVE"
const MELEE: StringName = &"MELEE"
const INTERACT: StringName = &"INTERACT"
const TAKE: StringName = &"TAKE"
const DROP: StringName = &"DROP"
const CONSUME: StringName = &"CONSUME"
const SLEEP: StringName = &"SLEEP"
const WORK: StringName = &"WORK"

var type: StringName = &""
var target: int = EH.INVALID
var vector_data: Vector3 = Vector3.ZERO
var scalar_data: float = 0.0


static func create(
	intent_type: StringName, target_handle: int = EH.INVALID, vector: Vector3 = Vector3.ZERO
) -> ActionIntent:
	var intent := ActionIntent.new()
	intent.type = intent_type
	intent.target = target_handle
	intent.vector_data = vector
	return intent


func has_target() -> bool:
	return EH.is_valid(target)
