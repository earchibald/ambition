## Forges, campfires, and torches. Uses the same heat model as materials; there is no separate
## ad-hoc station-energy component.
class_name HeatSourceComponent
extends RefCounted

var stored_energy: float = 0.0
var max_temperature: float = 1200.0
var fuel_materials: Array[StringName] = []
## Joules released into the environment per Micro tick while fuelled.
var output_j_per_tick: float = 0.0


func is_lit() -> bool:
	return stored_energy > 0.0


func consume(delta_energy: float) -> float:
	var spent: float = minf(stored_energy, delta_energy)
	stored_energy -= spent
	return spent
