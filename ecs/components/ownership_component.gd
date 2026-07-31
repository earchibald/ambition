## THE single item-ownership representation (registry section 7). Ownership is never a tag.
class_name OwnershipComponent
extends RefCounted

var faction_id: int = -1


func _init(owner_faction: int = -1) -> void:
	faction_id = owner_faction


func is_player_owned() -> bool:
	return WorldConstants.is_player_faction(faction_id)


func is_unowned() -> bool:
	return faction_id < 0
