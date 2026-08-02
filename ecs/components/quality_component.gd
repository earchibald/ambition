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

