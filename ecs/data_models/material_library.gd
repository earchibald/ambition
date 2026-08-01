## The seed material dictionary, authoritative from Sprint 1 (material doc §2).
##
## These numbers exist in code because Sprint 1's mass derivation and thermodynamics cannot run
## without them, and the specs previously deferred every one of them to a Sprint 5 dictionary
## that does not exist. Sprint 5 expands this table; it does not re-originate it.
##
## Units: `density` kg/cm3. `heat_capacity` J/(kg*K). Phase points Celsius. `acoustic_resonance`
## 0..1. `attenuation_db` is sound loss per tile of this material (hearing model, Sprint 1 §11).
## `melt`/`boil` of NAN means the material chars rather than melting cleanly — phase-change
## logic must not fire on it.
##
## `combustion_j_per_kg` (Sprint 4) is the heat of combustion, present only on materials that
## actually burn. It exists so a flash-fire's energy is DERIVED from what is burning rather than
## being a per-rule magic number: the reaction matrix would otherwise carry a hand-tuned joule
## figure that is identical for a spore cloud and a wooden barn. Real values — dry biomass
## ~18 MJ/kg, cotton ~17, sulfur ~9.3 — so the temperature rise a fire produces is arguable from
## the physics rather than from taste.
class_name MaterialLibrary
extends RefCounted

const MAT_IRON: StringName = &"MAT_IRON"
const MAT_COPPER: StringName = &"MAT_COPPER"
const MAT_TIN: StringName = &"MAT_TIN"
const MAT_SULFUR: StringName = &"MAT_SULFUR"
const MAT_SILICA: StringName = &"MAT_SILICA"
const MAT_GLASS: StringName = &"MAT_GLASS"
const MAT_CLOTH: StringName = &"MAT_CLOTH"
const MAT_BIOMASS: StringName = &"MAT_BIOMASS"
const MAT_WATER: StringName = &"MAT_WATER"
const MAT_GOLD: StringName = &"MAT_GOLD"
const MAT_BLOOD: StringName = &"MAT_BLOOD"
const MAT_STONE: StringName = &"MAT_STONE"

## Latent heats in J/kg. Without these, phase change is free and total: a 1000 kg body of water
## at 99.9C would flash-boil entirely on receiving 1 kJ.
const TABLE: Dictionary = {
	MAT_IRON: {
		"density": 0.00787,
		"heat_capacity": 450.0,
		"melt": 1538.0,
		"boil": 2862.0,
		"latent_fusion": 247000.0,
		"latent_vapor": 6090000.0,
		"acoustic_resonance": 0.7,
		"attenuation_db": 30.0,
		"base_value": 5.0,
		"toughness_mult": 4.0,
		"innate_tags": [&"Conductive", &"Magnetic"],
	},
	MAT_COPPER: {
		"density": 0.00896,
		"heat_capacity": 385.0,
		"melt": 1085.0,
		"boil": 2562.0,
		"latent_fusion": 205000.0,
		"latent_vapor": 4730000.0,
		"acoustic_resonance": 0.6,
		"attenuation_db": 30.0,
		"base_value": 3.0,
		"toughness_mult": 3.0,
		"innate_tags": [&"High_Conductivity", &"Soft"],
	},
	MAT_TIN: {
		"density": 0.00729,
		"heat_capacity": 227.0,
		"melt": 232.0,
		"boil": 2602.0,
		"latent_fusion": 59000.0,
		"latent_vapor": 2500000.0,
		"acoustic_resonance": 0.5,
		"attenuation_db": 28.0,
		"base_value": 2.0,
		"toughness_mult": 2.0,
		"innate_tags": [&"Low_Melting_Point"],
	},
	MAT_SULFUR: {
		"density": 0.00207,
		"heat_capacity": 710.0,
		"melt": 115.0,
		"boil": 445.0,
		"latent_fusion": 53000.0,
		"latent_vapor": 1500000.0,
		"combustion_j_per_kg": 9300000.0,
		"acoustic_resonance": 0.3,
		"attenuation_db": 14.0,
		"base_value": 10.0,
		"toughness_mult": 0.6,
		"innate_tags": [&"Volatile", &"Toxic"],
	},
	MAT_SILICA: {
		"density": 0.00265,
		"heat_capacity": 703.0,
		"melt": 1700.0,
		"boil": 2230.0,
		"latent_fusion": 142000.0,
		"latent_vapor": 4800000.0,
		"acoustic_resonance": 0.8,
		"attenuation_db": 22.0,
		"base_value": 1.0,
		"toughness_mult": 1.5,
		"innate_tags": [&"Brittle", &"Transparent"],
	},
	MAT_GLASS: {
		"density": 0.00250,
		"heat_capacity": 840.0,
		"melt": 1400.0,
		"boil": 2230.0,
		"latent_fusion": 140000.0,
		"latent_vapor": 4800000.0,
		"acoustic_resonance": 0.9,
		"attenuation_db": 18.0,
		"base_value": 2.0,
		"toughness_mult": 0.8,
		"innate_tags": [&"Brittle", &"Transparent"],
	},
	MAT_CLOTH: {
		"density": 0.00030,
		"heat_capacity": 1300.0,
		"melt": NAN,
		"boil": NAN,
		"latent_fusion": 0.0,
		"latent_vapor": 0.0,
		"acoustic_resonance": 0.1,
		"combustion_j_per_kg": 17000000.0,
		"attenuation_db": 4.0,
		"base_value": 1.0,
		"toughness_mult": 0.3,
		"innate_tags": [&"Flammable", &"Insulating"],
	},
	MAT_BIOMASS: {
		"density": 0.00106,
		"heat_capacity": 3500.0,
		"melt": NAN,
		"boil": NAN,
		"latent_fusion": 0.0,
		"latent_vapor": 0.0,
		"acoustic_resonance": 0.2,
		"combustion_j_per_kg": 18000000.0,
		"attenuation_db": 10.0,
		"base_value": 1.0,
		"toughness_mult": 1.0,
		"innate_tags": [&"Rot", &"Edible_Scavenger"],
	},
	MAT_WATER: {
		"density": 0.00100,
		"heat_capacity": 4186.0,
		"melt": 0.0,
		"boil": 100.0,
		"latent_fusion": 334000.0,
		"latent_vapor": 2257000.0,
		"acoustic_resonance": 0.4,
		"attenuation_db": 8.0,
		"base_value": 1.0,
		"toughness_mult": 0.2,
		"innate_tags": [&"Wet", &"Extinguishing"],
	},
	MAT_GOLD: {
		"density": 0.01932,
		"heat_capacity": 129.0,
		"melt": 1064.0,
		"boil": 2856.0,
		"latent_fusion": 63000.0,
		"latent_vapor": 1650000.0,
		"acoustic_resonance": 0.6,
		"attenuation_db": 32.0,
		"base_value": 50.0,
		"toughness_mult": 1.5,
		"innate_tags": [&"Heavy", &"Noble", &"Soft"],
	},
	MAT_BLOOD: {
		"density": 0.00106,
		"heat_capacity": 3600.0,
		"melt": -0.5,
		"boil": 100.0,
		"latent_fusion": 320000.0,
		"latent_vapor": 2257000.0,
		"acoustic_resonance": 0.3,
		"attenuation_db": 8.0,
		"base_value": 0.0,
		"toughness_mult": 0.2,
		"innate_tags": [&"Wet", &"Filth"],
	},
	MAT_STONE: {
		"density": 0.00270,
		"heat_capacity": 840.0,
		"melt": 1200.0,
		"boil": NAN,
		"latent_fusion": 200000.0,
		"latent_vapor": 0.0,
		"acoustic_resonance": 0.5,
		"attenuation_db": 25.0,
		"base_value": 0.0,
		"toughness_mult": 8.0,
		"innate_tags": [&"Hard"],
	},
}


static func has_material(material_id: StringName) -> bool:
	return TABLE.has(material_id)


static func field(material_id: StringName, key: String, fallback: float = 0.0) -> float:
	if not TABLE.has(material_id):
		return fallback
	return float(TABLE[material_id].get(key, fallback))


static func density_of(material_id: StringName) -> float:
	return field(material_id, "density", 0.0)


static func innate_tags(material_id: StringName) -> Array:
	if not TABLE.has(material_id):
		return []
	return TABLE[material_id]["innate_tags"]


## Volume-weighted mean density. Correct ONLY for volume fractions, which is why
## MaterialCompositionComponent declares them as such.
static func mean_density(composition: MaterialCompositionComponent) -> float:
	var total: float = 0.0
	for material_id in composition.volume_fractions:
		var fraction: float = float(composition.volume_fractions[material_id])
		total += fraction * density_of(material_id)
	return total


## Volume-weighted mean specific heat.
static func mean_heat_capacity(composition: MaterialCompositionComponent) -> float:
	var total: float = 0.0
	for material_id in composition.volume_fractions:
		var fraction: float = float(composition.volume_fractions[material_id])
		total += fraction * field(material_id, "heat_capacity", 1000.0)
	if total <= 0.0:
		return 1000.0
	return total


## THE single source of truth for mass (registry §5). Preserves temperature across the change
## by re-deriving enthalpy, because enthalpy scales with mass.
static func recompute_mass(
	physical: PhysicalPropertyComponent, composition: MaterialCompositionComponent
) -> void:
	var celsius: float = physical.temperature_c()
	physical.heat_capacity = mean_heat_capacity(composition)
	physical.mass_kg = physical.volume_cm3 * mean_density(composition)
	physical.set_temperature_c(celsius)


## Weighted toughness multiplier for the gib threshold (Sprint 1 §10).
static func toughness_mult(composition: MaterialCompositionComponent) -> float:
	var total: float = 0.0
	for material_id in composition.volume_fractions:
		var fraction: float = float(composition.volume_fractions[material_id])
		total += fraction * field(material_id, "toughness_mult", 1.0)
	return maxf(0.05, total)


## Heat of combustion for a whole body, in joules: volume-weighted over what it is made of.
## Materials with no `combustion_j_per_kg` contribute nothing, so a stone statue in a burning
## room releases no energy of its own.
static func combustion_energy_j(
	physical: PhysicalPropertyComponent, composition: MaterialCompositionComponent
) -> float:
	if physical == null or composition == null:
		return 0.0
	var per_kg: float = 0.0
	for material_id in composition.volume_fractions:
		var fraction: float = float(composition.volume_fractions[material_id])
		per_kg += fraction * field(material_id, "combustion_j_per_kg", 0.0)
	return per_kg * maxf(physical.mass_kg, 0.0)


static func acoustic_sum(composition: MaterialCompositionComponent) -> float:
	var total: float = 0.0
	for material_id in composition.volume_fractions:
		var fraction: float = float(composition.volume_fractions[material_id])
		total += fraction * field(material_id, "acoustic_resonance", 0.0)
	return total


## Sound loss per tile. Open space is 0; unknown material falls back to stone.
static func attenuation_db(material_id: StringName) -> float:
	if material_id == &"":
		return 0.0
	return field(material_id, "attenuation_db", 25.0)


## Every material validates against the content schema's positivity rules.
static func validate_table() -> Array[String]:
	var problems: Array[String] = []
	for material_id in TABLE:
		if density_of(material_id) <= 0.0:
			problems.append("%s has non-positive density" % material_id)
		if field(material_id, "heat_capacity", 0.0) <= 0.0:
			problems.append("%s has non-positive heat_capacity" % material_id)
		if field(material_id, "base_value", -1.0) < 0.0:
			problems.append("%s has negative base_value" % material_id)
	return problems
