## One remembered fact (registry section 4).
##
## Weight is MULTIPLICATIVE with a core floor, not additive. An additive core bonus drives
## every core memory to the same weight as recency decays, which turns "top-3 by weight" into
## float-noise ordering.
##
## Decay is AGE-DERIVED, never applied incrementally. Incremental decay would age a memory by
## only 12 hours across an Interregnum that covers 8,760.
class_name MemoryEvent
extends RefCounted

const CORE_FLOOR: float = 0.35
const HALF_LIFE_H: float = 72.0

static var _next_id: int = 1

## Globally unique. REQUIRED so the gossip loop can dedup instead of unioning duplicates.
var event_id: int = 0
var text: StringName = &""
var kind: StringName = &"IDLE_CHAT"
var tick_hours: int = 0
var core: bool = false
var subject: int = EH.INVALID


static func base_weight(kind_name: StringName) -> float:
	match kind_name:
		&"WITNESSED_MURDER":
			return 10.0
		&"WAS_ATTACKED":
			return 8.0
		&"WITNESSED_THEFT":
			return 6.0
		&"FED":
			return 3.0
		&"TRADED":
			return 2.0
		_:
			return 0.5


static func create(
	kind_name: StringName, text_value: StringName, now_hours: int, is_core: bool = false
) -> MemoryEvent:
	var event := MemoryEvent.new()
	event.event_id = _next_id
	_next_id += 1
	event.kind = kind_name
	event.text = text_value
	event.tick_hours = now_hours
	event.core = is_core
	return event


## Current salience. Core memories keep their RELATIVE ordering forever because the floor is
## applied multiplicatively: a core murder floors at 3.5, a core meal at 1.05.
func weight_at(now_hours: int) -> float:
	var age: float = maxf(0.0, float(now_hours - tick_hours))
	var falloff: float = pow(0.5, age / HALF_LIFE_H)
	if core:
		falloff = maxf(CORE_FLOOR, falloff)
	return base_weight(kind) * falloff
