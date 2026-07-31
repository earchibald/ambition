## What an entity is made of.
##
## CRITICAL: these are VOLUME fractions, not mass fractions (registry section 5). The mass
## formula is a volume-weighted mean density, so reading them as mass fractions gives a 96%
## error for a metal/liquid composite. Authors who think in mass convert first.
class_name MaterialCompositionComponent
extends RefCounted

var volume_fractions: Dictionary = {}


func _init(fractions: Dictionary = {}) -> void:
	volume_fractions = fractions.duplicate()


func is_normalized() -> bool:
	return absf(fraction_sum() - 1.0) <= 0.001


func fraction_sum() -> float:
	var total: float = 0.0
	for key in volume_fractions:
		total += float(volume_fractions[key])
	return total


func normalize() -> void:
	var total: float = fraction_sum()
	if total <= 0.0:
		return
	for key in volume_fractions:
		volume_fractions[key] = float(volume_fractions[key]) / total


## Convert mass fractions to volume fractions:
##   vf_i = (w_i / rho_i) / sum(w_j / rho_j)
static func from_mass_fractions(mass_fractions: Dictionary) -> MaterialCompositionComponent:
	var weighted: Dictionary = {}
	var total: float = 0.0
	for material_id in mass_fractions:
		var density: float = MaterialLibrary.density_of(material_id)
		if density <= 0.0:
			continue
		var term: float = float(mass_fractions[material_id]) / density
		weighted[material_id] = term
		total += term
	if total > 0.0:
		for material_id in weighted:
			weighted[material_id] = float(weighted[material_id]) / total
	return MaterialCompositionComponent.new(weighted)


func dominant_material() -> StringName:
	var best: StringName = &""
	var best_fraction: float = -1.0
	for material_id in volume_fractions:
		var fraction: float = float(volume_fractions[material_id])
		if fraction > best_fraction:
			best_fraction = fraction
			best = material_id
	return best
