## Faction membership and standing for an individual entity.
class_name SocialIdentityComponent
extends RefCounted

var faction_id: int = -1
var loyalty: float = 50.0
var prestige: float = 0.0


func _init(faction: int = -1) -> void:
	faction_id = faction
