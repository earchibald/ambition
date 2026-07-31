## Condition of an item.
##
## `wear` is authoritative; `condition` is a DERIVED band (registry section 5). Degradation
## always writes wear, because an enum cannot be decremented "by 1 point per tick" or
## multiplied by a percentage.
class_name QualityComponent
extends RefCounted

var wear: float = 0.0


func condition() -> ECSEnums.Quality:
	return ECSEnums.quality_from_wear(wear)


func add_wear(amount: float) -> void:
	wear = clampf(wear + amount, 0.0, 100.0)


## Value multiplier by condition band (economy doc section 5).
func value_modifier() -> float:
	match condition():
		ECSEnums.Quality.PRISTINE:
			return 1.0
		ECSEnums.Quality.CHIPPED:
			return 0.65
		ECSEnums.Quality.RUINED:
			return 0.30
		_:
			return 0.10
