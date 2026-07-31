## Physical state of matter.
##
## `mass_kg` is a DERIVED CACHE, never edited independently (registry section 5). It is
## recomputed from volume and composition by MaterialLibrary.recompute_mass().
##
## Thermal state is stored as ENTHALPY, not temperature, so phase change can consume latent
## heat. Without that, 1000 kg of water at 99.9C flash-boils entirely on receiving 1 kJ.
class_name PhysicalPropertyComponent
extends RefCounted

var quantity: int = 1
var volume_cm3: float = 1000.0
var mass_kg: float = 1.0
var heat_capacity: float = 1000.0
var phase: ECSEnums.Phase = ECSEnums.Phase.SOLID

## Joules relative to 0C at the current mass. temperature_c() derives from this.
var enthalpy_j: float = 0.0


func temperature_c() -> float:
	var thermal_mass: float = mass_kg * heat_capacity
	if thermal_mass <= 0.0:
		return 0.0
	return enthalpy_j / thermal_mass


func set_temperature_c(celsius: float) -> void:
	enthalpy_j = celsius * mass_kg * heat_capacity


## Adds energy in joules. Positive heats, negative cools.
func add_energy(joules: float) -> void:
	enthalpy_j += joules


## Total value-bearing quantity for payment validation. Payment sums VALUE, never mass.
func stack_volume_cm3() -> float:
	return volume_cm3 * float(quantity)


func stack_mass_kg() -> float:
	return mass_kg * float(quantity)
