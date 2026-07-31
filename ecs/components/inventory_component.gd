## Physical carrying. Volume and mass are real constraints, not abstract slots.
##
## Handles are packed ints (ADR-19), so held_items is a PackedInt64Array.
class_name InventoryComponent
extends RefCounted

var held_items: PackedInt64Array = PackedInt64Array()
var sub_containers: PackedInt64Array = PackedInt64Array()
var total_volume_used: float = 0.0
var total_mass_kg: float = 0.0


func contains(handle: int) -> bool:
	return held_items.has(handle)


func add(handle: int) -> void:
	if not held_items.has(handle):
		held_items.append(handle)


func remove(handle: int) -> bool:
	var idx: int = held_items.find(handle)
	if idx < 0:
		return false
	held_items.remove_at(idx)
	return true


func item_count() -> int:
	return held_items.size()
