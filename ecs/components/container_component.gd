## Capacity and filtering for anything that holds other entities.
class_name ContainerComponent
extends RefCounted

var capacity_cm3: float = 50000.0
var accepts_tags: Array[StringName] = []
var rejects_tags: Array[StringName] = []
## Prevents the bag-of-holding-inside-a-bag-of-holding volume exploit.
var allow_nested_container: bool = false
## Contents inherit this tag while inside (e.g. a Padded_Pouch applying Muffled).
var confers_tag: StringName = &""


## Overstuff is allowed up to 115%, which is what makes the rupture mechanic a real gamble.
func overstuff_limit_cm3() -> float:
	return capacity_cm3 * 1.15


func accepts(tags: Array[StringName], is_container: bool) -> bool:
	if is_container and not allow_nested_container:
		return false
	for tag in rejects_tags:
		if tags.has(tag):
			return false
	if accepts_tags.is_empty():
		return true
	for tag in accepts_tags:
		if tags.has(tag):
			return true
	return false
