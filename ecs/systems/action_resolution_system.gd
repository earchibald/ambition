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
##
## CROSS-LoD BOUNDARY COMBAT (Sprint 2 scaffolding §229 asks for the branch to be STATED here):
## actions resolve in the ATTACKER's LoD, and the chosen branch is (b) — a hostile action from a
## Simulated chunk into an Active one resolves ABSTRACTLY at ledger scale, never by
## force-promoting the target chunk. Force-promotion (a) hands any distant faction a lever that
## spikes the frame budget on demand. Today NO action crosses a seam at all: melee requires
## reach, and hostile engagement targets only spatial-hash neighbours, which are same-floor and
## Active by construction. The branch is recorded now so the first cross-seam feature inherits a
## decision instead of an accident.
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
var mishaps_rolled: int = 0

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
		_grant_kill_insight(attacker_row, target_row)
		_convert_to_corpse(target_row)
	return damage


## Knowledge-driven growth (magic doc §4: killing and studying a creature deepens Insight).
## Every insight value in the build was FROZEN at its Field Primer seed — nothing incremented
## any key in play — so the Tactical Lens gates and the Rune_Stability budget were constants
## wearing a progression system's name. A kill teaches you about what the thing was made of.
func _grant_kill_insight(attacker_row: int, target_row: int) -> void:
	var mind: MindComponent = ECSManager.minds.get(attacker_row)
	var composition: MaterialCompositionComponent = ECSManager.materials.get(target_row)
	if mind == null or composition == null:
		return
	var topic: StringName = _insight_topic_for(composition.dominant_material())
	mind.insight[topic] = mind.insight_in(topic) + 1


static func _insight_topic_for(material_id: StringName) -> StringName:
	match material_id:
		MaterialLibrary.MAT_BIOMASS, MaterialLibrary.MAT_BLOOD:
			return &"Biomass"
		MaterialLibrary.MAT_IRON:
			return &"Iron"
		MaterialLibrary.MAT_WATER:
			return &"Water"
		_:
			return &"Biomass"


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
	# STRAIN DAMAGES THE CEILING, NOT THE TANK (magic doc §2: "temporary damage to the caster's
	# Max_Stamina... until they rest"). Charging current stamina — the Sprint 4 shipping
	# behaviour — was the wrong quantity, and with no recovery path anywhere in the build it made
	# the starting fireball castable five times per LIFE. The refusal fires when the body has no
	# ceiling left to dent; recovery is `MetabolismSystem`'s rest pass.
	if body == null or body.strain + strain > body.max_stamina:
		ECSEvents.action_rejected.emit(caster, &"cast", &"too strained — rest first")
		return false
	body.strain += strain
	body.stamina = minf(body.stamina, body.effective_max_stamina())

	# THE MISHAP TABLE (grimoire spec §2C, declared gap G-2). An [Unstable] spell rolls d100 on
	# every cast; the roll only ever changes HOW the cast goes wrong, never whether stamina and
	# strain were spent — the spec's whole point is that forcing the compile buys risk, not a
	# discount.
	var to_cast: CompiledSpell = spell
	if spell.unstable:
		to_cast = _roll_mishap(caster_row, spell)

	var origin: Vector3 = ECSManager.position_of(caster_row)
	var heading: Vector3 = Vector3.FORWARD if aim.length() < 0.001 else aim.normalized()
	if to_cast.shape == RuneLibrary.SHAPE_PROJECTILE:
		# Spawned one radius clear of the caster, or it detonates against the hand that cast it.
		origin += heading * (to_cast.radius_m + 0.6)
	if to_cast != spell and to_cast.shape == RuneLibrary.SHAPE_SELF:
		# Syntax Inversion: the spell goes off ON the caster, whatever was aimed at.
		origin = ECSManager.position_of(caster_row)
	EphemeralSystem.spawn_spell(to_cast, origin, heading, caster)
	casts_resolved += 1
	ECSEvents.spell_cast.emit(caster, spell_id, strain)
	return true


## One d100 roll on the mishap table, from the seeded `magic` stream (ADR-8/ADR-20 — a mishap
## must reproduce from the run's seed). Returns the spell to actually cast, cloned when the
## mishap mutates geometry or target, because mutating the grimoire's copy would ratchet.
##   01-50  Success with Blood: casts perfectly; the strain cost is ALSO taken from health.
##   51-85  Over-Pressure: the geometric bounds double, up to the 15 m engine cap.
##   86-100 Syntax Inversion: the target logic reverses — the spell resolves on the caster.
func _roll_mishap(caster_row: int, spell: CompiledSpell) -> CompiledSpell:
	mishaps_rolled += 1
	var roll: int = RNGService.randi_range_in(&"magic", 1, 100)
	if roll <= 50:
		_mishap_wound(caster_row, spell.strain_cost, &"Bleeding")
		return spell
	if roll <= 85:
		var swollen: CompiledSpell = spell.clone()
		swollen.radius_m = minf(spell.radius_m * 2.0, WorldConstants.MAX_SPELL_RADIUS_M)
		swollen.caps_applied.append(&"mishap: over-pressure")
		return swollen
	var inverted: CompiledSpell = spell.clone()
	inverted.shape = RuneLibrary.SHAPE_SELF
	inverted.speed_mps = 0.0
	inverted.caps_applied.append(&"mishap: syntax inversion")
	return inverted


## THE MERCY CAP: no mishap may reduce Entity 0 below 1 HP. The excess is not forgiven — it
## converts into a trauma tag ([Arcane_Burn] / [Bleeding]) that cripples the rest recovery in
## `MetabolismSystem`, which is the spec's "cheap permadeath becomes expensive convalescence".
func _mishap_wound(row: int, amount: float, trauma: StringName) -> void:
	var body: BodyComponent = ECSManager.bodies.get(row)
	if body == null:
		return
	var floor_hp: float = 1.0 if row == WorldConstants.PLAYER_INDEX else 0.0
	var dealt: float = minf(amount, maxf(0.0, body.health - floor_hp))
	body.health -= dealt
	var chemistry: ChemistryComponent = ECSManager.chemistries.get(row)
	if chemistry != null:
		chemistry.add_tag(trauma)
		if amount > dealt:
			chemistry.add_tag(&"Arcane_Burn")
	_report(row, dealt, body.health, &"mishap")


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

	# The claim lifecycle's "no orphaned jobs" rule, honoured at the only moment it can be
	# broken: death. `release_jobs_of` existed, was documented, and had no production caller, so
	# a dead hauler's job stayed CLAIMED by a corpse forever.
	JobResolutionSystem.release_jobs_of(row)

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
		"mishaps_rolled": mishaps_rolled,
	}
