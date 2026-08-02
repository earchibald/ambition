## Forges, campfires, and torches. Uses the same heat model as materials; there is no separate
## ad-hoc station-energy component.
class_name HeatSourceComponent
extends RefCounted

var stored_energy: float = 0.0
## Ceiling on the owning body's temperature while lit. Enforced by the burn pass in
## `ReactionSystem`: a brazier is hot, not unboundedly hot.
var max_temperature: float = 1200.0
## Joules released into the chunk air per Micro tick while lit, drained from `stored_energy` by
## the burn pass — which is what lets a brazier BURN DOWN instead of burning forever for free.
## (`fuel_materials` used to sit beside this: a refuelling list declared in Sprint 1, read by
## nothing, deleted in the 2026-08-01 remediation. Refuelling returns when an interaction
## exists to pour fuel in.)
var output_j_per_tick: float = 500.0


func is_lit() -> bool:
	return stored_energy > 0.0


func consume(delta_energy: float) -> float:
	var spent: float = minf(stored_energy, delta_energy)
	stored_energy -= spent
	return spent
