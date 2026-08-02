## TTL, motion, and payload application for the ONE shared transient primitive.
##
## Noise events, [Alert] auras, bard morale auras, and Sprint 4 magic effects all flow through
## here. TTL cleanup is mandatory: an ephemeral that never expires is a leak with a radius.
##
## THE TRIGGER DECIDES WHEN, THE SHAPE DECIDES WHERE, and separating them is what makes the magic
## doc's examples composable rather than hardcoded:
##   * `On_Cast` applies the payload to whatever it overlaps, every tick, until it expires.
##   * `On_Impact` travels and goes off once, on the first entity or wall it meets.
##   * `On_Timer` waits out its delay wherever it is, then goes off once — a fuse.
##   * `On_Proximity` waits for somebody who is not the caster to come inside its radius. That
##     is the magic doc's "Trap": a physical landmine, built from the same aura as a smoke cloud.
## Every one of them still dies on TTL, and a one-shot that never found a target goes off on
## expiry rather than vanishing — a spell that silently evaporates reads as one never cast.
##
## Projectiles are advanced HERE rather than through CollisionResolveSystem on purpose. That
## system slides a body along a wall and steps it up a ledge, which is exactly right for a person
## and exactly wrong for a fireball: a spell that slid along the wall it was aimed at would never
## go off. The trade is that this path does no substepping, so a projectile at the
## MAX_SPELL_SPEED_MPS cap moves 0.67 m per Micro frame — under a tile, which is why the cap is
## an anti-crash rule rather than a balance one.
class_name EphemeralSystem
extends RefCounted

var active: int = 0
var expired: int = 0
var tags_applied: int = 0
var detonations: int = 0

## Set by the caller each tick so wall hits can be resolved. Null in tests that only exercise
## auras, which never read it.
var sampler: TileSampler = null


func run(delta: float, hash: SpatialHash) -> void:
	active = 0
	expired = 0
	tags_applied = 0
	detonations = 0
	var rows: PackedInt32Array = ECSManager.query(ComponentMask.EPHEMERAL)
	var doomed: PackedInt32Array = PackedInt32Array()

	for i in rows.size():
		var row: int = rows[i]
		var ephemeral: EphemeralComponent = ECSManager.ephemerals.get(row)
		if ephemeral == null:
			continue
		ephemeral.advance(delta)
		if ephemeral.is_expired():
			# A one-shot that ran out of TTL still goes off. Otherwise a fireball that misses
			# vanishes without a sound, which reads as the spell never having been cast.
			if ephemeral.detonates():
				_detonate(row, ephemeral, hash)
			doomed.append(row)
			continue
		active += 1
		if ephemeral.speed_mps > 0.0 and _advance_projectile(row, ephemeral, delta, hash):
			doomed.append(row)
			continue
		if not ephemeral.has_payload() or ephemeral.radius_m <= 0.0:
			continue
		if not ephemeral.detonates():
			_apply_aura(row, ephemeral, hash)
		elif _should_fire(row, ephemeral, hash):
			_detonate(row, ephemeral, hash)
			doomed.append(row)

	for i in doomed.size():
		expired += 1
		ECSManager.destroy_entity(ECSManager.handle_of(doomed[i]))


## Whether a stationary one-shot's condition has been met this tick.
##
## `On_Impact` is handled by the projectile path, so a STATIONARY impact spell has nothing to
## strike and simply waits out its TTL — deliberate, and the reason this returns false for it
## rather than firing immediately.
func _should_fire(row: int, ephemeral: EphemeralComponent, hash: SpatialHash) -> bool:
	if ephemeral.trigger == RuneLibrary.TRIGGER_ON_TIMER:
		return ephemeral.arm_after_s <= 0.0
	if ephemeral.trigger != RuneLibrary.TRIGGER_ON_PROXIMITY:
		return false
	# A mine that its own caster set off by standing next to it would be useless, so the caster
	# is excluded — as are other ephemerals, or two traps trigger each other on contact.
	return _first_contact(row, ephemeral, hash) >= 0


## Moves a projectile one step and reports whether it went off. Returns true when the caller
## should retire it.
func _advance_projectile(
	row: int, ephemeral: EphemeralComponent, delta: float, hash: SpatialHash
) -> bool:
	var from: Vector3 = ECSManager.position_of(row)
	var to: Vector3 = from + ephemeral.heading * ephemeral.speed_mps * delta
	ECSManager.set_position(row, to)

	if sampler != null and sampler.solid_at_world(to):
		# Detonate at the last open position, not inside the wall, or the blast is centred a
		# half-metre into solid rock and reaches nothing on the near side of it.
		ECSManager.set_position(row, from)
		_detonate(row, ephemeral, hash)
		return true
	if not ephemeral.detonates():
		return false
	if _first_contact(row, ephemeral, hash) < 0:
		return false
	_detonate(row, ephemeral, hash)
	return true


## The nearest entity the projectile is touching, or -1. Excludes its own caster, so a spell does
## not detonate in the hand that cast it, and excludes other ephemerals, so two spells in flight
## do not shoot each other down.
func _first_contact(row: int, ephemeral: EphemeralComponent, hash: SpatialHash) -> int:
	if hash == null:
		return -1
	var caster_row: int = EH.index_of(ephemeral.source_entity)
	var centre: Vector3 = ECSManager.position_of(row)
	for other in hash.query_radius(centre, maxf(ephemeral.radius_m, 0.25)):
		if other == row or other == caster_row:
			continue
		if ECSManager.ephemerals.has(other):
			continue
		return other
	return -1


## Everything a spell does on contact, in one place: tags on, tags off, energy in.
func _detonate(row: int, ephemeral: EphemeralComponent, hash: SpatialHash) -> void:
	if ephemeral.spent:
		return
	ephemeral.spent = true
	detonations += 1
	if hash == null or not ephemeral.has_payload():
		return
	var centre: Vector3 = ECSManager.position_of(row)
	var radius: float = maxf(ephemeral.blast_radius_m, ephemeral.radius_m)
	for other in hash.query_radius(centre, radius):
		if other == row or ECSManager.ephemerals.has(other):
			continue
		if not _within_cone(centre, other, ephemeral):
			continue
		_apply_payload(other, ephemeral)
	ECSEvents.spell_detonated.emit(
		ephemeral.source_entity, StringName(ephemeral.payload.get("spell_id", &"")), centre
	)
	# A detonation is LOUD. `spawn_noise` shipped in Sprint 1 documented as "how an unseen impact
	# produces INVESTIGATE rather than omniscient combat" and had zero callers — so every
	# explosion in the build was silent to everyone not looking at it. The noise outlives the
	# spell by design: the ephemeral dies this frame, the ringing ears do not.
	EphemeralSystem.spawn_noise(centre, radius * 4.0, 0.5, ephemeral.source_entity)


func _apply_aura(row: int, ephemeral: EphemeralComponent, hash: SpatialHash) -> void:
	var centre: Vector3 = ECSManager.position_of(row)
	var overlapped: PackedInt32Array = hash.query_radius(centre, ephemeral.radius_m)
	for i in overlapped.size():
		var other: int = overlapped[i]
		if other == row or not _within_cone(centre, other, ephemeral):
			continue
		_apply_payload(other, ephemeral)


## The wedge test. A Cone that did not read its own angle would be a sphere with a misleading
## name, which is exactly what it was until this existed.
##
## Measured on the FLAT plane, like the melee arc, because the camera is top-down and a target's
## height above the caster is not what a player means by "in front of me".
func _within_cone(centre: Vector3, other: int, ephemeral: EphemeralComponent) -> bool:
	if ephemeral.cone_angle_deg <= 0.0:
		return true
	var facing := Vector3(ephemeral.heading.x, 0.0, ephemeral.heading.z)
	if facing.length() < 0.001:
		# A cone with no direction is not a cone. Spherical beats silently hitting nothing.
		return true
	var to: Vector3 = ECSManager.position_of(other) - centre
	var flat := Vector3(to.x, 0.0, to.z)
	if flat.length() < 0.001:
		return true
	return (
		rad_to_deg(facing.normalized().angle_to(flat.normalized())) <= ephemeral.cone_angle_deg
	)


## One entity, one payload. Energy goes through the surface model rather than being added to bulk
## enthalpy, for the reason the thermodynamics system already documents: distributing a fireball
## over total mass melts an iron sword and leaves a human unharmed.
func _apply_payload(other: int, ephemeral: EphemeralComponent) -> void:
	var chemistry: ChemistryComponent = ECSManager.chemistries.get(other)
	if chemistry != null:
		for tag in ephemeral.applies_tags:
			if chemistry.add_tag(tag):
				tags_applied += 1
		for tag in ephemeral.removes_tags:
			chemistry.remove_tag(tag)
	if is_zero_approx(ephemeral.energy_j):
		return
	var physical: PhysicalPropertyComponent = ECSManager.physicals.get(other)
	var composition: MaterialCompositionComponent = ECSManager.materials.get(other)
	if physical == null or composition == null:
		return
	ThermodynamicsSystem.apply_surface_energy(
		physical, composition, ephemeral.energy_j, _exposed_area_cm2(other)
	)


func _exposed_area_cm2(row: int) -> float:
	var bounds: BoundsComponent = ECSManager.bounds.get(row)
	if bounds == null:
		return 2500.0
	return maxf(4.0 * bounds.half_extents.x * bounds.half_extents.y * 10000.0, 100.0)


## Spawns a noise event at a location. This is how an unseen impact produces INVESTIGATE rather
## than omniscient combat.
static func spawn_noise(position: Vector3, radius_m: float, ttl: float, source: int) -> int:
	var handle: int = ECSManager.allocate_entity()
	var row: int = EH.index_of(handle)
	ECSManager.set_position(row, position)
	ECSManager.add_component_bit(row, ComponentMask.POSITION)

	var ephemeral := EphemeralComponent.new()
	ephemeral.time_to_live = ttl
	ephemeral.source_entity = source
	ECSManager.ephemerals[row] = ephemeral
	ECSManager.add_component_bit(row, ComponentMask.EPHEMERAL)

	var emitter := SensoryEmitterComponent.new()
	emitter.noise_radius_m = radius_m
	ECSManager.emitters[row] = emitter
	ECSManager.add_component_bit(row, ComponentMask.SENSORY_EMITTER)
	return handle


## Spawns an expanding tag-applying aura. Bard morale, guard alerts, and magic all use this.
static func spawn_aura(
	position: Vector3, tags: Array[StringName], radius_m: float, ttl: float, source: int
) -> int:
	var handle: int = ECSManager.allocate_entity()
	var row: int = EH.index_of(handle)
	ECSManager.set_position(row, position)
	ECSManager.add_component_bit(row, ComponentMask.POSITION)

	var ephemeral := EphemeralComponent.new()
	ephemeral.time_to_live = ttl
	ephemeral.radius_m = radius_m
	ephemeral.applies_tags = tags
	ephemeral.source_entity = source
	ECSManager.ephemerals[row] = ephemeral
	ECSManager.add_component_bit(row, ComponentMask.EPHEMERAL)
	# Announced to the viewer: a smoke cloud that blocks NPC sight while being invisible to the
	# PLAYER would be the perception system cheating in reverse.
	var visual_tags: Array[StringName] = [&"Aura"]
	visual_tags.append_array(tags)
	ECSEvents.emit_entity_created(handle, visual_tags, position)
	return handle


## Spawns a compiled spell's physical form. THE ONE PLACE magic becomes an entity, so the TTL is
## set from the capped value rather than from anything a rune asked for.
##
## Bounds are attached so the SpatialHash bins it, which is what makes the detonation query and
## the aura overlap work at all — the hash is built from `ComponentMask.SPATIAL`, and an entity
## with a position and no bounds is invisible to every proximity query in the build.
static func spawn_spell(
	spell: CompiledSpell, position: Vector3, heading: Vector3, source: int
) -> int:
	var handle: int = ECSManager.allocate_entity()
	var row: int = EH.index_of(handle)
	ECSManager.set_position(row, position)
	ECSManager.add_component_bit(row, ComponentMask.POSITION)

	var bounds := BoundsComponent.new()
	var extent: float = maxf(WorldConstants.MIN_ENTITY_EXTENT, spell.radius_m * 0.5)
	bounds.half_extents = Vector3(extent, extent, extent)
	ECSManager.bounds[row] = bounds
	ECSManager.add_component_bit(row, ComponentMask.BOUNDS)

	var ephemeral := EphemeralComponent.new()
	ephemeral.time_to_live = spell.ttl_s
	ephemeral.source_entity = source
	ephemeral.radius_m = spell.radius_m
	ephemeral.expansion_mps = spell.expansion_mps
	ephemeral.applies_tags = spell.applies_tags.duplicate()
	ephemeral.removes_tags = spell.removes_tags.duplicate()
	ephemeral.energy_j = spell.energy_j
	ephemeral.payload = {"spell_id": spell.spell_id}
	# The trigger and the heading are carried whatever the shape is: a stationary cone still needs
	# a direction to be a cone, and a mine still needs to know it is a mine.
	ephemeral.trigger = spell.trigger
	ephemeral.arm_after_s = spell.delay_s
	ephemeral.cone_angle_deg = spell.cone_angle_deg
	ephemeral.heading = heading.normalized()
	ephemeral.blast_radius_m = spell.radius_m
	if spell.shape == RuneLibrary.SHAPE_PROJECTILE:
		ephemeral.speed_mps = spell.speed_mps
	ECSManager.ephemerals[row] = ephemeral
	ECSManager.add_component_bit(row, ComponentMask.EPHEMERAL)

	# The payload tags ride along so the viewer can colour the bolt by WHAT IT DOES (declared
	# gap G-4: a cast spawned an ordinary box, indistinguishable from a dropped crate).
	var tags: Array[StringName] = [&"Kinetic_Ephemeral", &"Spell"]
	tags.append_array(spell.applies_tags)
	ECSEvents.emit_entity_created(handle, tags, position)
	return handle


func counters() -> Dictionary:
	return {
		"ephemerals_active": active,
		"ephemerals_expired": expired,
		"aura_tags": tags_applied,
		"spell_detonations": detonations,
	}
