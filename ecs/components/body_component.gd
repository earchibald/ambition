## Biology, competence, and damage state.
class_name BodyComponent
extends RefCounted

var max_health: float = 100.0
var health: float = 100.0
var stamina: float = 100.0
var max_stamina: float = 100.0
var strength: float = 10.0
## Multiplies the gib threshold. Armour raises it; soft creatures lower it. Sourced from the
## creature schema's `structural_toughness`.
var structural_toughness: float = 1.0
var armor_rating: float = 0.0
var mutations: Array[StringName] = []
var skills: Dictionary = {}
var exposure: Dictionary = {}


func is_alive() -> bool:
	return health > 0.0


func skill(name: StringName) -> float:
	return float(skills.get(name, 0.0))


## Muscle memory. Gain shrinks as the skill approaches its strength-derived soft cap, and
## scales with how challenging the target was.
func train_skill(name: StringName, challenge: float) -> void:
	var cap: float = 60.0 + 0.4 * strength
	var current: float = skill(name)
	if current >= cap:
		return
	var headroom: float = 1.0 - current / cap
	var gain: float = 0.05 * headroom * headroom * clampf(challenge, 0.2, 2.0)
	skills[name] = minf(current + gain, cap)


func carry_capacity_kg() -> float:
	return 10.0 + strength * 2.0
