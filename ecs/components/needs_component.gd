## Biological drives.
##
## SIGN CONVENTIONS (were undefined; both directions appeared in different docs):
##   hunger RISES 0 -> 100 (100 = starving)
##   energy FALLS 100 -> 0 (0 = exhausted)
##   morale FALLS 100 -> 0
class_name NeedsComponent
extends RefCounted

var hunger: float = 0.0
var energy: float = 100.0
var morale: float = 70.0


func clamp_all() -> void:
	hunger = clampf(hunger, 0.0, 100.0)
	energy = clampf(energy, 0.0, 100.0)
	morale = clampf(morale, 0.0, 100.0)
