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

## How far a caster may reach for an environmental resource to Absorb. Arm's length plus a step:
## the grimoire spec's example is casting AT a campfire, not across a room.
const ABSORB_REACH_M: float = 3.0

## Joules of absorbed environmental energy that buy one point of Strain. Deliberately large —
## 200 kJ of campfire heat, the Absorb_Heat rune's requirement, buys 2 points against a fireball's
## 12.5 — so absorbing is a discount and never a way to cast for free.
const STRAIN_J_EQUIVALENT: float = 100000.0

var attacks_resolved: int = 0
var kills: int = 0
var gibs: int = 0
var damage_dealt: float = 0.0
var casts_resolved: int = 0
var casts_fizzled: int = 0

## Acts committed this tick that somebody might have seen. Drained by GameLoopManager and handed
## to PerceptionSystem, which owns the question of who had line of sight.
var witnessed_actions: Array[Dictionary] = []


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
	# WITNESSABLE. There is no global crime flag: this only says the act happened somewhere, and
	# perception decides who — if anyone — was in a position to see it.
	witnessed_actions.append({
		"subject": attacker_row,
		"action": &"MURDER" if not target.is_alive() else &"ASSAULT",
		"location": ECSManager.position_of(target_row),
	})

	if not target.is_alive():
		kills += 1
		# Announce the death BEFORE the body becomes a corpse. Converting first means every
		# listener resolves the entity after the Corpse tag is set, and the log reads
		# "corpse #1 DIED" — which describes the aftermath, not the event.
		ECSEvents.entity_died.emit(ECSManager.handle_of(target_row), &"melee")
		_convert_to_corpse(target_row)
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
		ECSEvents.entity_died.emit(ECSManager.handle_of(row), &"fall")
		_convert_to_corpse(row)
	return damage


## THE CAST PATH (Sprint 4 §3). Turns a compiled spell into physical ECS reality.
##
## Three ways to fail, and every one of them is REPORTED, because a cast that resolves silently
## is indistinguishable from a key that was never bound — the exact failure the outcome bus was
## added for in Sprint 1.
##   * The spell is not in the caster's grimoire: nothing was bound.
##   * The caster lacks the Strain: magic has no regenerating mana bar, it costs stamina
##     (magic doc §2), and a cast you cannot pay for must say so rather than half-happening.
##   * Absorb fizzles: the spell needed a quantified environmental resource and the world did not
##     have enough of it (review D8).
##
## Returns true only if an entity was actually spawned.
func resolve_cast(caster_row: int, spell_id: StringName, aim: Vector3) -> bool:
	var mind: MindComponent = ECSManager.minds.get(caster_row)
	var body: BodyComponent = ECSManager.bodies.get(caster_row)
	var caster: int = ECSManager.handle_of(caster_row)
	if mind == null or not mind.grimoire.has(spell_id):
		ECSEvents.action_rejected.emit(caster, &"cast", &"no spell bound")
		return false

	var spell: CompiledSpell = mind.grimoire[spell_id]
	# ABSORB FIRST, and only then charge Strain. Reversing the order takes stamina for a cast that
	# then fizzles, which is the player paying for nothing and is what "the cast is wasted" in the
	# grimoire spec must NOT be read as.
	var absorbed: float = _absorb_for(caster_row, spell)
	if absorbed < 0.0:
		casts_fizzled += 1
		ECSEvents.action_rejected.emit(caster, &"cast", &"fizzled — nothing to absorb")
		return false

	# Absorbed environmental energy pays part of the biological price (grimoire spec §2B). The
	# discount is bounded at the full cost so a large campfire cannot make a spell free AND
	# refund stamina.
	var discount: float = minf(spell.strain_cost, absorbed / STRAIN_J_EQUIVALENT)
	var strain: float = spell.strain_cost - discount
	if body == null or body.stamina < strain:
		ECSEvents.action_rejected.emit(caster, &"cast", &"not enough stamina")
		return false
	body.stamina -= strain

	var origin: Vector3 = ECSManager.position_of(caster_row)
	var heading: Vector3 = Vector3.FORWARD if aim.length() < 0.001 else aim.normalized()
	if spell.shape == RuneLibrary.SHAPE_PROJECTILE:
		# Spawned one radius clear of the caster, or it detonates against the hand that cast it.
		origin += heading * (spell.radius_m + 0.6)
	EphemeralSystem.spawn_spell(spell, origin, heading, caster)
	casts_resolved += 1
	ECSEvents.spell_cast.emit(caster, spell_id, strain)
	return true


## Absorb_Tag, with the conservation rule the review demanded (D8).
##
## Returns the joules taken, 0.0 when the spell absorbs nothing, and -1.0 to mean FIZZLE. The
## quantity is consumed ATOMICALLY from one source: `HeatSourceComponent.consume` decrements
## before this returns, so two casters resolving in the same Micro tick cannot both spend the
## same campfire — the second finds it already drained and fizzles, which is the specified
## behaviour rather than a race.
##
## The source tag is only removed when the underlying quantity crosses the extinguish threshold,
## which is the whole point of quantifying it: ripping [Burning] off a bonfire because someone
## drew a candle's worth of heat is the bug this design exists to prevent.
func _absorb_for(caster_row: int, spell: CompiledSpell) -> float:
	if spell.absorbs == &"":
		return 0.0
	var origin: Vector3 = ECSManager.position_of(caster_row)
	for row in ECSManager.query(ComponentMask.HEAT_SOURCE):
		var source: HeatSourceComponent = ECSManager.heat_sources.get(row)
		if source == null or source.stored_energy < spell.absorb_j:
			continue
		if origin.distance_to(ECSManager.position_of(row)) > ABSORB_REACH_M:
			continue
		var taken: float = source.consume(spell.absorb_j)
		if not source.is_lit():
			var chemistry: ChemistryComponent = ECSManager.chemistries.get(row)
			if chemistry != null:
				chemistry.remove_tag(&"Burning")
		return taken
	return -1.0


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
##
## THE GUARD BELOW WAS MISSING UNTIL 2026-08-01, and the comment above described an intention the
## code did not implement — the same failure mode as a doc comment on unused code. A fatal fall
## tagged ROW 0 itself `Corpse`/`Filth` and stripped its behaviour bits, and only afterwards did
## `GameLoopManager._check_player_death()` run `DeathLoopSystem`, which then built a second corpse
## out of already-mutated row-0 state. Two corpses, a player row wearing corpse tags, and ADR-14's
## reserved-row rule broken for the width of a frame.
##
## Row 0 is left entirely alone here. `DeathLoopSystem.on_player_death` is the single owner of
## what happens to the player, which is what C-D5 claims and what this now makes true.
func _convert_to_corpse(row: int) -> void:
	if row == WorldConstants.PLAYER_INDEX:
		return
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
		"casts_resolved": casts_resolved,
		"casts_fizzled": casts_fizzled,
	}
