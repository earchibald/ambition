## Filters which faction jobs an entity may claim.
##
## Legacy prose like `[Prof_Hauler]` is shorthand for this component's value, not a tag.
class_name ProfessionComponent
extends RefCounted

var profession: StringName = &"Prof_Idler"


func _init(value: StringName = &"Prof_Idler") -> void:
	profession = value
