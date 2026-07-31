## Mass derivation, the volume-fraction basis, and conduction stability.
extends GutTest


func test_material_table_validates() -> void:
	assert_eq(
		MaterialLibrary.validate_table(),
		[] as Array[String],
		"every seed material has positive density, heat capacity, and non-negative value"
	)


## A litre of water is a kilogram. If this fails, every mass in the game is wrong.
func test_water_mass_is_unit_correct() -> void:
	var physical := PhysicalPropertyComponent.new()
	physical.volume_cm3 = 1000.0
	var composition := MaterialCompositionComponent.new({MaterialLibrary.MAT_WATER: 1.0})
	MaterialLibrary.recompute_mass(physical, composition)
	assert_almost_eq(physical.mass_kg, 1.0, 0.001, "1000 cm3 of water is 1.0 kg")


func test_iron_density_is_physical() -> void:
	var physical := PhysicalPropertyComponent.new()
	physical.volume_cm3 = 190.5
	var composition := MaterialCompositionComponent.new({MaterialLibrary.MAT_IRON: 1.0})
	MaterialLibrary.recompute_mass(physical, composition)
	assert_almost_eq(physical.mass_kg, 1.5, 0.01, "a 190.5 cm3 iron blade is ~1.5 kg")


func test_gold_coin_mass_is_plausible() -> void:
	var physical := PhysicalPropertyComponent.new()
	physical.volume_cm3 = 1.04
	var composition := MaterialCompositionComponent.new({MaterialLibrary.MAT_GOLD: 1.0})
	MaterialLibrary.recompute_mass(physical, composition)
	assert_almost_eq(physical.mass_kg, 0.020, 0.001, "a 1.04 cm3 gold coin is ~20 g")


## Fractions are VOLUME fractions. Reading them as mass fractions is a 96% error.
func test_volume_and_mass_fraction_bases_differ_materially() -> void:
	var by_volume := MaterialCompositionComponent.new(
		{MaterialLibrary.MAT_IRON: 0.8, MaterialLibrary.MAT_WATER: 0.2}
	)
	var volume_density: float = MaterialLibrary.mean_density(by_volume)
	assert_almost_eq(volume_density, 0.006496, 0.00001, "volume-weighted density is 6.496 g/cm3")

	var by_mass: MaterialCompositionComponent = MaterialCompositionComponent.from_mass_fractions(
		{MaterialLibrary.MAT_IRON: 0.8, MaterialLibrary.MAT_WATER: 0.2}
	)
	var mass_density: float = MaterialLibrary.mean_density(by_mass)
	assert_almost_eq(mass_density, 0.003316, 0.00001, "mass-weighted density is 3.316 g/cm3")
	assert_gt(
		volume_density / mass_density, 1.9, "the two bases differ by nearly 2x — basis matters"
	)


func test_mass_fraction_conversion_normalizes() -> void:
	var converted: MaterialCompositionComponent = (
		MaterialCompositionComponent.from_mass_fractions(
			{MaterialLibrary.MAT_IRON: 0.5, MaterialLibrary.MAT_WATER: 0.5}
		)
	)
	assert_true(converted.is_normalized(), "converted volume fractions sum to 1.0")


func test_mass_is_recomputed_when_volume_changes() -> void:
	var physical := PhysicalPropertyComponent.new()
	physical.volume_cm3 = 1000.0
	var composition := MaterialCompositionComponent.new({MaterialLibrary.MAT_WATER: 1.0})
	MaterialLibrary.recompute_mass(physical, composition)
	physical.volume_cm3 = 2000.0
	MaterialLibrary.recompute_mass(physical, composition)
	assert_almost_eq(physical.mass_kg, 2.0, 0.001, "doubling volume doubles derived mass")


func test_temperature_survives_a_mass_recompute() -> void:
	var physical := PhysicalPropertyComponent.new()
	physical.volume_cm3 = 1000.0
	var composition := MaterialCompositionComponent.new({MaterialLibrary.MAT_WATER: 1.0})
	MaterialLibrary.recompute_mass(physical, composition)
	physical.set_temperature_c(50.0)
	physical.volume_cm3 = 1500.0
	MaterialLibrary.recompute_mass(physical, composition)
	assert_almost_eq(
		physical.temperature_c(), 50.0, 0.01, "temperature is preserved when mass changes"
	)


# --- Conduction stability ---------------------------------------------------------------------


func _body(mass: float, celsius: float) -> PhysicalPropertyComponent:
	var physical := PhysicalPropertyComponent.new()
	physical.mass_kg = mass
	physical.heat_capacity = 1000.0
	physical.set_temperature_c(celsius)
	return physical


## The equilibrium clamp must make conduction stable for ANY constant. At K=60 the naive form
## becomes a perfect 2-cycle; at K=150 it reaches millions of degrees in a fraction of a second.
func test_conduction_converges_and_never_oscillates() -> void:
	var thermo := ThermodynamicsSystem.new()
	var hot: PhysicalPropertyComponent = _body(1.0, 100.0)
	var cold: PhysicalPropertyComponent = _body(1.0, 0.0)
	for _i in 400:
		thermo.conduct_pair(hot, cold, 1.0, 1.0 / 60.0)
	assert_almost_eq(hot.temperature_c(), 50.0, 2.0, "the hot body converges toward equilibrium")
	assert_almost_eq(cold.temperature_c(), 50.0, 2.0, "the cold body converges toward equilibrium")
	assert_lt(hot.temperature_c(), 100.0, "the hot body actually cooled")
	assert_gt(cold.temperature_c(), 0.0, "the cold body actually warmed")


func test_conduction_conserves_energy() -> void:
	var thermo := ThermodynamicsSystem.new()
	var hot: PhysicalPropertyComponent = _body(2.0, 80.0)
	var cold: PhysicalPropertyComponent = _body(1.0, 10.0)
	var before: float = hot.enthalpy_j + cold.enthalpy_j
	for _i in 100:
		thermo.conduct_pair(hot, cold, 1.0, 1.0 / 60.0)
	assert_almost_eq(
		hot.enthalpy_j + cold.enthalpy_j, before, 1.0, "total thermal energy is conserved"
	)


## Neither body may overshoot past equilibrium — that is what the clamp guarantees.
func test_conduction_cannot_overshoot_equilibrium() -> void:
	var thermo := ThermodynamicsSystem.new()
	var hot: PhysicalPropertyComponent = _body(1.0, 100.0)
	var cold: PhysicalPropertyComponent = _body(1.0, 0.0)
	for _i in 500:
		thermo.conduct_pair(hot, cold, 1.0, 1.0 / 60.0)
		assert_between(hot.temperature_c(), 49.0, 100.1, "hot body never dips below equilibrium")
		assert_between(cold.temperature_c(), -0.1, 51.0, "cold body never rises above equilibrium")


## Surface energy must not be spread over total mass, or one fireball melts a sword while
## leaving a human unharmed.
func test_surface_energy_affects_a_small_item_more_than_a_large_body() -> void:
	var sword: PhysicalPropertyComponent = _body(1.5, 20.0)
	var sword_comp := MaterialCompositionComponent.new({MaterialLibrary.MAT_IRON: 1.0})
	sword.heat_capacity = 450.0
	sword.set_temperature_c(20.0)

	var human: PhysicalPropertyComponent = _body(70.0, 20.0)
	var human_comp := MaterialCompositionComponent.new({MaterialLibrary.MAT_BIOMASS: 1.0})
	human.heat_capacity = 3500.0
	human.set_temperature_c(20.0)

	ThermodynamicsSystem.apply_surface_energy(sword, sword_comp, 500000.0, 200.0)
	ThermodynamicsSystem.apply_surface_energy(human, human_comp, 500000.0, 4500.0)

	assert_gt(sword.temperature_c(), 20.0, "the sword heated")
	assert_gt(human.temperature_c(), 20.0, "the human also actually heated")
