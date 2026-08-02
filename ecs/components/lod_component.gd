## Level of detail. Drives how deeply an entity is simulated (ECS spec section 3).
class_name LoDComponent
extends RefCounted

var current_state: ECSEnums.LoD = ECSEnums.LoD.ACTIVE


func _init(state: ECSEnums.LoD = ECSEnums.LoD.ACTIVE) -> void:
	current_state = state


func is_active() -> bool:
	return current_state == ECSEnums.LoD.ACTIVE
