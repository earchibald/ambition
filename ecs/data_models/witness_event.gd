## A perception-gated observation of an action (registry section 4).
##
## Crime and reputation are NOT omniscient. A crime only becomes reputation data when a
## perceiving observer generates one of these and it propagates through memory/gossip.
class_name WitnessEvent
extends RefCounted

var observer: int = EH.INVALID
var subject: int = EH.INVALID
var action: StringName = &""
var location: Vector3 = Vector3.ZERO
var tick_hours: int = 0
## 0..1. Partial occlusion, distance, and darkness reduce it.
var confidence: float = 1.0


static func create(
	observer_handle: int,
	subject_handle: int,
	action_name: StringName,
	where: Vector3,
	now_hours: int,
	confidence_value: float = 1.0
) -> WitnessEvent:
	var event := WitnessEvent.new()
	event.observer = observer_handle
	event.subject = subject_handle
	event.action = action_name
	event.location = where
	event.tick_hours = now_hours
	event.confidence = clampf(confidence_value, 0.0, 1.0)
	return event


## Only a confident observation is strong enough to be treated as caught red-handed.
func is_actionable() -> bool:
	return confidence >= 0.5
