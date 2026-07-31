## Sight, hearing, and awareness state.
##
## `sight_range_m` defaults to 12, not 20: LoS cost scales ~r^3 and the 20 m default made
## naive all-pairs sight 65 ms in a single Simulation tick at the ADR-10 entity target.
##
## `last_known_targets` is keyed by packed-int handle (ADR-19), so it is Dictionary-safe and
## serializes cleanly.
class_name PerceptionComponent
extends RefCounted

var sight_range_m: float = 12.0
var fov_degrees: float = 110.0
var hearing_sensitivity: float = 1.0
var awareness_state: ECSEnums.AwarenessState = ECSEnums.AwarenessState.UNAWARE
var last_known_targets: Dictionary = {}
## Sim-tick counter used to tier re-evaluation frequency by awareness state.
var next_eval_tick: int = 0


## Unaware agents do not need 2 Hz threat detection. Tiering is what makes the LoS budget fit.
func eval_interval_ticks() -> int:
	match awareness_state:
		ECSEnums.AwarenessState.COMBAT, ECSEnums.AwarenessState.INVESTIGATING:
			return 1
		ECSEnums.AwarenessState.SUSPICIOUS:
			return 5
		_:
			return 20


func note_target(handle: int, position: Vector3) -> void:
	last_known_targets[handle] = position


func forget(handle: int) -> void:
	last_known_targets.erase(handle)
