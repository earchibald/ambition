## Biomass decay on the Macro tick (material doc section 6).
##
## Cold slows spoilage, which makes refrigeration a real preservation strategy rather than
## flavour text.
class_name SpoilageSystem
extends RefCounted

const SPOILAGE_MACRO_TICKS: float = 72.0

var tracked: int = 0
var converted_to_filth: int = 0

## row -> remaining macro ticks.
var _timers: Dictionary = {}


func run(chunk: ChunkData) -> void:
	tracked = 0
	converted_to_filth = 0
	var rows: PackedInt32Array = ECSManager.query(ComponentMask.MATERIAL)
	for i in rows.size():
		var row: int = rows[i]
		var composition: MaterialCompositionComponent = ECSManager.materials[row]
		var biomass: float = float(
			composition.volume_fractions.get(MaterialLibrary.MAT_BIOMASS, 0.0)
		)
		if biomass <= 0.0:
			continue
		tracked += 1
		if not _timers.has(row):
			_timers[row] = SPOILAGE_MACRO_TICKS

		# Cold slows the clock; the floor keeps it from stopping entirely.
		var rate: float = maxf(0.25, 1.0 - (20.0 - chunk.ambient_temperature_c) * 0.05)
		_timers[row] = float(_timers[row]) - rate
		if float(_timers[row]) > 0.0:
			continue
		_timers.erase(row)
		_become_filth(row)
		converted_to_filth += 1


func _become_filth(row: int) -> void:
	var chemistry: ChemistryComponent = ECSManager.chemistries.get(row)
	if chemistry == null:
		chemistry = ChemistryComponent.new()
		ECSManager.chemistries[row] = chemistry
		ECSManager.add_component_bit(row, ComponentMask.CHEMISTRY)
	chemistry.add_tag(&"Filth")
	chemistry.remove_tag(&"Edible_Scavenger")
	# Filth in stagnant water is what breeds Tier-1 swarms, so mark the chunk.
	var physical: PhysicalPropertyComponent = ECSManager.physicals.get(row)
	if physical != null:
		physical.quantity = maxi(1, physical.quantity)


func counters() -> Dictionary:
	return {"spoilage_tracked": tracked, "filth_created": converted_to_filth}
