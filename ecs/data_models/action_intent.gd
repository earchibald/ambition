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
const CAST: StringName = &"CAST"
const BIND: StringName = &"BIND"

var type: StringName = &""
var target: int = EH.INVALID
var vector_data: Vector3 = Vector3.ZERO
var scalar_data: float = 0.0

## The Action_ID a CAST refers to (magic doc §5). The UI sends an id, never a spell object: the
## compiled spell lives on the caster's `MindComponent.grimoire`, so an intent that survives a
## frame cannot hold a stale copy of a spell the player has since recompiled.
var name_data: StringName = &""

## The rune array a BIND carries. The Grimoire assembles a list and the ECS compiles it — the UI
## never writes a CompiledSpell into a MindComponent itself, because that would make the panel an
## author of ECS state rather than a listener that sends requests (Prime Directive).
var name_list: Array[StringName] = []


## A bind request: compile these runes and register the result as an Action_ID.
## `overclock` rides in `scalar_data` (1.0 = forced compile, grimoire spec §2C). That field was
## declared in Sprint 1 and read by nothing until this; a bool-shaped payload finally exists.
static func bind(runes: Array[StringName], overclock: bool = false) -> ActionIntent:
	var intent := create(BIND)
	intent.name_list = runes.duplicate()
	intent.scalar_data = 1.0 if overclock else 0.0
	return intent


static func create(
	intent_type: StringName, target_handle: int = EH.INVALID, vector: Vector3 = Vector3.ZERO
) -> ActionIntent:
	var intent := ActionIntent.new()
	intent.type = intent_type
	intent.target = target_handle
	intent.vector_data = vector
	return intent


## A cast, by Action_ID and aim direction.
static func cast(spell_id: StringName, aim: Vector3) -> ActionIntent:
	var intent := create(CAST, EH.INVALID, aim)
	intent.name_data = spell_id
	return intent

