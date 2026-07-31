## Dynamic state tags.
##
## Tags are StringName ONLY (registry section 7). Phase is NOT a tag: Solid/Liquid/Gas are
## `ECSEnums.Phase` values on PhysicalPropertyComponent.
class_name ChemistryComponent
extends RefCounted

var active_tags: Array[StringName] = []


func has_tag(tag: StringName) -> bool:
	return active_tags.has(tag)


func add_tag(tag: StringName) -> bool:
	if active_tags.has(tag):
		return false
	active_tags.append(tag)
	return true


func remove_tag(tag: StringName) -> bool:
	var idx: int = active_tags.find(tag)
	if idx < 0:
		return false
	active_tags.remove_at(idx)
	return true
