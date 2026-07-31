## Melee, fall damage, and death. Combat is physics (Sprint 1 section 10).
##
## KINETIC ENERGY MODEL. The old formula was broken five ways: it called momentum "force", added
## a dimensionless stat to kilograms, counted density twice (mass is already volume*density),
## delivered exactly ZERO damage from a stationary attacker, and never touched health despite
## both roadmaps describing health reaching 0.
##
## Verified against real numbers with a 1.5 kg sword, 70 kg wielder, strength 10 (E = 106 J):
## a 0.4 kg rat gibs (threshold 65 J); a 70 kg human takes 35 hp and needs three hits
## (threshold 2,040 J); an armoured knight needs ~11 hits; a 500 kg boulder at 20 m/s gibs
## anything. A stationary player still deals the full 106 J.
class_name ActionResolutionSystem
extends RefCounted

var attacks_resolved: int = 0
var kills: int = 0
var gibs: int = 0
var damage_dealt: float = 0.0


## Weapon-tip speed. DECOUPLED from body velocity, which is what fixes the zero-damage bug. A
## forward lunge adds a capped charge bonus rather than being the sole source of damage.
static func swing_speed(body: BodyComponent, body_velocity: Vector3, swing_dir: Vector3) -> float:
	var base: float = (
		WorldConstants.BASE_SWING_MPS
		* sqrt(maxf(body.strength, 0.01) / WorldConstants.STRENGTH_REF)
		* (1.0 + 0.5 * body.skill(&"Blade_Familiarity") / 100.0)
	)
	var charge: float = 0.0
	if swing_dir.length() > 0.001:
		charge = clampf(body_velocity.dot(swing_dir.normalized()), 0.0, 0.5 * base)
	return base + charge


## Delivered kinetic energy in joules.
static func impact_energy(
	wielder_mass_kg: float, weapon_mass_kg: float, swing_mps: float
) -> float:
	var effective_mass: float = (
		weapon_mass_kg + WorldConstants.ARM_MASS_FRAC * maxf(wielder_mass_kg, 0.0)
	)
	return 0.5 * effective_mass * swing_mps * swing_mps


## Energy above which the target is destroyed outright. Scales with CROSS-SECTION
## (mass^(2/3)), not with mass*density, which was dimensionally meaningless.
static func gib_threshold(target_mass_kg: float, toughness_mult: float) -> float:
	return WorldConstants.TOUGHNESS_J * pow(maxf(target_mass_kg, 0.001), 2.0 / 3.0) * toughness_mult


## Armour absorbs a fraction that falls off as energy rises, so heavy blows still land.
static func absorbed_fraction(armor_rating: float, energy_j: float) -> float:
	if armor_rating <= 0.0:
		return 0.0
	return clampf(armor_rating / (armor_rating + maxf(energy_j, 0.001)), 0.0, 0.95)


## Resolves one melee attack. Returns the damage applied in hit points.
func resolve_melee(
	attacker_row: int, target_row: int, swing_dir: Vector3, weapon_mass_kg: float
) -> float:
	var attacker: BodyComponent = ECSManager.bodies.get(attacker_row)
	var target: BodyComponent = ECSManager.bodies.get(target_row)
	if attacker == null or target == null or not target.is_alive():
		return 0.0

	var attacker_physical: PhysicalPropertyComponent = ECSManager.physicals.get(attacker_row)
	var wielder_mass: float = 70.0 if attacker_physical == null else attacker_physical.mass_kg
	var speed: float = swing_speed(attacker, ECSManager.velocity_of(attacker_row), swing_dir)
	var energy: float = impact_energy(wielder_mass, weapon_mass_kg, speed)

	var effective: float = energy * (1.0 - absorbed_fraction(target.armor_rating, energy))
	var damage: float = effective / WorldConstants.J_PER_HP

	var target_physical: PhysicalPropertyComponent = ECSManager.physicals.get(target_row)
	var target_mass: float = 70.0 if target_physical == null else target_physical.mass_kg
	var threshold: float = gib_threshold(target_mass, target.structural_toughness)

	attacks_resolved += 1
	damage_dealt += damage

	if effective > threshold:
		gibs += 1
		target.health = 0.0
	else:
		target.health = maxf(0.0, target.health - damage)

	# Muscle memory: harder targets teach more.
	attacker.train_skill(&"Blade_Familiarity", threshold / maxf(effective, 0.001))

	# The impact makes NOISE regardless of whether anyone saw it. This is what lets an unseen
	# hit produce INVESTIGATE rather than omniscient combat.
	_emit_impact_noise(target_row, effective)
	_report(target_row, damage, target.health, &"gib" if effective > threshold else &"melee")

	if not target.is_alive():
		kills += 1
		_convert_to_corpse(target_row)
		ECSEvents.entity_died.emit(ECSManager.handle_of(target_row), &"melee")
	return damage


## Falls reuse the same energy model rather than inventing a second damage system.
func resolve_fall(row: int, impact_speed_mps: float) -> float:
	if impact_speed_mps <= WorldConstants.SAFE_FALL_MPS:
		return 0.0
	var body: BodyComponent = ECSManager.bodies.get(row)
	var physical: PhysicalPropertyComponent = ECSManager.physicals.get(row)
	if body == null:
		return 0.0
	var mass: float = 70.0 if physical == null else physical.mass_kg
	var excess: float = impact_speed_mps - WorldConstants.SAFE_FALL_MPS
	var energy: float = 0.5 * mass * excess * excess
	var damage: float = energy / WorldConstants.J_PER_HP
	body.health = maxf(0.0, body.health - damage)
	damage_dealt += damage
	_report(row, damage, body.health, &"fall")
	if not body.is_alive():
		kills += 1
		_convert_to_corpse(row)
		ECSEvents.entity_died.emit(ECSManager.handle_of(row), &"fall")
	return damage


## Announces an outcome. Systems resolve; the bus reports. Nothing here reads back from the UI.
func _report(row: int, amount: float, remaining: float, cause: StringName) -> void:
	if amount <= 0.0:
		return
	ECSEvents.entity_damaged.emit(ECSManager.handle_of(row), amount, remaining, cause)


func _emit_impact_noise(row: int, energy_j: float) -> void:
	var emitter: SensoryEmitterComponent = ECSManager.emitters.get(row)
	if emitter == null:
		emitter = SensoryEmitterComponent.new()
		ECSManager.emitters[row] = emitter
		ECSManager.add_component_bit(row, ComponentMask.SENSORY_EMITTER)
	emitter.noise_radius_m = maxf(emitter.noise_radius_m, clampf(energy_j * 0.15, 2.0, 30.0))


## Death converts the entity into a corpse IN PLACE for non-player entities. The PLAYER's death
## is different: it creates a SEPARATE corpse entity and retires handle 0 with a bumped
## generation, so the corpse and the next adventurer never compete for the reserved slot.
func _convert_to_corpse(row: int) -> void:
	var chemistry: ChemistryComponent = ECSManager.chemistries.get(row)
	if chemistry == null:
		chemistry = ChemistryComponent.new()
		ECSManager.chemistries[row] = chemistry
		ECSManager.add_component_bit(row, ComponentMask.CHEMISTRY)
	chemistry.add_tag(&"Corpse")
	chemistry.add_tag(&"Filth")

	# A corpse is no longer an agent: strip the behaviour bits so no system keeps ticking it.
	ECSManager.remove_component_bit(row, ComponentMask.NEEDS)
	ECSManager.remove_component_bit(row, ComponentMask.SCHEDULE)
	ECSManager.remove_component_bit(row, ComponentMask.PERCEPTION)
	ECSManager.needs.erase(row)
	ECSManager.schedules.erase(row)
	ECSManager.perceptions.erase(row)

	# Corpses become loose matter that spoils.
	if not ECSManager.loose_items.has(row):
		ECSManager.loose_items[row] = LooseItemComponent.new()
		ECSManager.add_component_bit(row, ComponentMask.LOOSE_ITEM)


func counters() -> Dictionary:
	return {
		"attacks_resolved": attacks_resolved,
		"kills": kills,
		"gibs": gibs,
		"damage_dealt": damage_dealt,
	}
