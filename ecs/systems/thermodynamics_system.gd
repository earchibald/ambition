## Heat conduction and phase change (material doc section 7).
##
## CONDUCTION IS CLAMPED BY THE EQUILIBRIUM TEMPERATURE. Explicit conduction with no bound is
## unstable: measured on a 100C/0C pair at dt=1/60, K=60 becomes a perfect 2-cycle that LOOKS
## stable because energy is conserved, while the cell flickers ICE<->GAS 30 times a second; and
## K=150 reaches +/-3.2 million C in 0.13 s. The clamp makes overshoot impossible for ANY K, so
## a mis-tuned constant merely slows convergence instead of exploding.
class_name ThermodynamicsSystem
extends RefCounted

## Game-feel value. MUST satisfy K <= 1/(N*dt) = 15 for four neighbours at 60 Hz.
## A physically correct constant for stone would produce no observable transfer at 1 m tiles
## (equilibration takes ~231 hours), so this is deliberately not physical.
const CONDUCTION_K: float = 3.0
## Surface effects heat a shell, not the whole body. Distributing over total mass raises an iron
## sword by +1485C (melting it) while raising a human by +4.1C (unharmed) from the same fireball.
const SURFACE_DEPTH_CM: float = 0.5

var conduction_pairs: int = 0
var phase_changes: int = 0


## Conducts an entity toward its chunk's ambient temperature.
func run(delta: float, chunk: ChunkData) -> void:
	conduction_pairs = 0
	phase_changes = 0
	var rows: PackedInt32Array = ECSManager.query(ComponentMask.PHYSICAL)
	for i in rows.size():
		var row: int = rows[i]
		var physical: PhysicalPropertyComponent = ECSManager.physicals[row]
		_conduct_toward(physical, chunk.ambient_temperature_c, 1.0, delta)
		conduction_pairs += 1
		_update_phase(row, physical)


## Exchange between two bodies. Exactly conservative, and cannot overshoot equilibrium.
func conduct_pair(
	a: PhysicalPropertyComponent,
	b: PhysicalPropertyComponent,
	contact_area_m2: float,
	delta: float
) -> void:
	var capacity_a: float = a.mass_kg * a.heat_capacity
	var capacity_b: float = b.mass_kg * b.heat_capacity
	if capacity_a <= 0.0 or capacity_b <= 0.0:
		return
	var temp_a: float = a.temperature_c()
	var temp_b: float = b.temperature_c()
	var equilibrium: float = (capacity_a * temp_a + capacity_b * temp_b) / (capacity_a + capacity_b)
	# Normalize on the REDUCED (harmonic) thermal mass so CONDUCTION_K is a true per-second rate.
	# Without this the effective rate is K/C, so the same constant equilibrates a coin in a
	# frame and a barrel of water never — which makes the constant impossible to tune and makes
	# the K <= 1/(N*dt) stability bound meaningless.
	var reduced: float = (capacity_a * capacity_b) / (capacity_a + capacity_b)
	var energy: float = CONDUCTION_K * contact_area_m2 * (temp_a - temp_b) * delta * reduced
	# The clamp is what makes any K stable.
	var max_from_a: float = absf(capacity_a * (temp_a - equilibrium))
	var max_into_b: float = absf(capacity_b * (equilibrium - temp_b))
	energy = clampf(energy, -max_into_b, max_from_a)
	a.add_energy(-energy)
	b.add_energy(energy)


## Conduction toward a fixed reservoir (ambient air, a heated floor).
func _conduct_toward(
	physical: PhysicalPropertyComponent,
	reservoir_c: float,
	contact_area_m2: float,
	delta: float
) -> void:
	var capacity: float = physical.mass_kg * physical.heat_capacity
	if capacity <= 0.0:
		return
	var current: float = physical.temperature_c()
	# A reservoir is infinite, so the reduced thermal mass is just the body's own capacity.
	var energy: float = (
		CONDUCTION_K * contact_area_m2 * (reservoir_c - current) * delta * capacity
	)
	var max_energy: float = absf(capacity * (reservoir_c - current))
	energy = clampf(energy, -max_energy, max_energy)
	physical.add_energy(energy)


## Phase is an ENUM on PhysicalPropertyComponent, never a ChemistryComponent tag string.
func _update_phase(row: int, physical: PhysicalPropertyComponent) -> void:
	var composition: MaterialCompositionComponent = ECSManager.materials.get(row)
	if composition == null:
		return
	var dominant: StringName = composition.dominant_material()
	var melt: float = MaterialLibrary.field(dominant, "melt", NAN)
	var boil: float = MaterialLibrary.field(dominant, "boil", NAN)
	if is_nan(melt):
		# Chars rather than melting cleanly; phase-change logic must not fire.
		return

	var celsius: float = physical.temperature_c()
	var previous: ECSEnums.Phase = physical.phase
	var next: ECSEnums.Phase = ECSEnums.Phase.LIQUID
	if celsius <= melt:
		next = ECSEnums.Phase.SOLID
	elif not is_nan(boil) and celsius >= boil:
		next = ECSEnums.Phase.GAS

	if next == previous:
		return
	physical.phase = next
	phase_changes += 1
	_apply_phase_tags(row, next, dominant)


func _apply_phase_tags(row: int, phase: ECSEnums.Phase, dominant: StringName) -> void:
	var chemistry: ChemistryComponent = ECSManager.chemistries.get(row)
	if chemistry == null:
		return
	# Frozen water is walkable and treacherous; that is a TAG. The phase itself is not.
	if phase == ECSEnums.Phase.SOLID and dominant == MaterialLibrary.MAT_WATER:
		chemistry.add_tag(&"Slippery")
		chemistry.remove_tag(&"Wet")
	elif phase == ECSEnums.Phase.LIQUID and dominant == MaterialLibrary.MAT_WATER:
		chemistry.remove_tag(&"Slippery")
		chemistry.add_tag(&"Wet")
	elif phase == ECSEnums.Phase.GAS:
		chemistry.remove_tag(&"Slippery")
		chemistry.add_tag(&"Steam")


## Energy applied to a surface, not distributed over total mass.
static func apply_surface_energy(
	physical: PhysicalPropertyComponent,
	composition: MaterialCompositionComponent,
	joules: float,
	exposed_area_cm2: float
) -> void:
	var density: float = MaterialLibrary.mean_density(composition)
	var shell_mass: float = SURFACE_DEPTH_CM * exposed_area_cm2 * density
	var heated_mass: float = minf(physical.mass_kg, maxf(shell_mass, 0.0001))
	# Scale the energy by the fraction of the body actually heated.
	var fraction: float = heated_mass / maxf(physical.mass_kg, 0.0001)
	physical.add_energy(joules * fraction)


func counters() -> Dictionary:
	return {"conduction_pairs": conduction_pairs, "phase_changes": phase_changes}
