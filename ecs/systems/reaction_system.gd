## The reaction matrix (Sprint 4 §1). Two incompatible tags meet, and something happens.
##
## RULES ARE DATA, KEYED BY THE SORTED TAG PAIR (review F2). `Burning+Volatile_Gas` and
## `Volatile_Gas+Burning` are the same rule and must never be authored twice; the index is built
## once from the sorted pair so the authoring order in `RULES` cannot matter. A flat dictionary
## of hand-written keys was the alternative and it drifts the moment content grows.
##
## SCOPE IS PART OF THE RULE, NOT AN ASSUMPTION.
##   * INTRA — both tags on ONE entity. A burning thing that is also wet puts itself out.
##   * INTER — two OVERLAPPING entities, found through the SpatialHash. A torch next to a spore
##     cloud is a different event from a torch that is itself sporing.
## Conflating the two gives a torch that extinguishes itself the instant it touches a puddle it
## is standing beside, which reads as a bug and is really a missing distinction.
##
## THE ANTI-RECURSION LOCK IS THE WHOLE REASON THIS SYSTEM IS SAFE TO RUN AT 60 Hz. A reaction
## writes result tags, and result tags are inputs to other rules, so without a lock a single
## explosion re-triggers itself every frame forever — the stack overflow the scaffolding warns
## about, except worse, because it is a live-lock rather than a crash and the frame budget simply
## disappears. Every participant gets `Reaction_Cooldown` for REACTION_COOLDOWN_FRAMES and is
## skipped entirely while it holds.
##
## ENERGY IS DERIVED, NOT DECLARED. A rule says WHAT burns, and `MaterialLibrary` says how much
## energy that releases per kilogram, so a spore cloud and a wooden barn do not release the same
## joules because someone typed 800 into a table. The ambient rise that follows is then real
## arithmetic over the chunk's air, which is why it is small for one cloud and obvious for a room
## full of them.
class_name ReactionSystem
extends RefCounted

const COOLDOWN_TAG: StringName = &"Reaction_Cooldown"

const SCOPE_INTRA: StringName = &"INTRA"
const SCOPE_INTER: StringName = &"INTER"

## Registered under BOTH keys. Fire spread needs it and the omission was a real hole: a fireball
## whose catalyst tags a spore cloud `Burning` leaves ONE entity carrying both `Burning` and
## `Spores`, and an INTER-only rule never matches a pair that lives on a single entity — so the
## roadmap's own success state, a torch into a room of spores, produced nothing at all. Authored
## once rather than as two near-identical rows, because two rows drift.
const SCOPE_BOTH: StringName = &"BOTH"

## How far apart two entities may be and still react. One tile: touching, not merely nearby.
const CONTACT_RADIUS_M: float = 1.0

## Bounded per tick. An entity in a dense crowd of reactants would otherwise pair with every
## neighbour in one frame, and the cost of that is quadratic in exactly the situation — a room
## full of spores — the feature exists to produce.
const MAX_REACTIONS_PER_TICK: int = 64

## `tags` is authored in any order and sorted at load. `burns` names the participant whose
## material supplies the combustion energy; `consumes` names participants destroyed outright.
## `blast_radius_m` of 0 means no kinetic event.
const RULES: Array[Dictionary] = [
	{
		"tags": [&"Burning", &"Volatile_Gas"],
		"scope": SCOPE_BOTH,
		"adds": [&"Explosion"],
		"removes": [],
		"burns": &"Volatile_Gas",
		"consumes": [&"Volatile_Gas"],
		"blast_radius_m": 6.0,
		"blast_impulse_ns": 900.0,
		"gas": &"",
	},
	{
		# The success state from the roadmap: a torch into a room of spores.
		"tags": [&"Burning", &"Spores"],
		"scope": SCOPE_BOTH,
		"adds": [&"Burning"],
		"removes": [&"Spores"],
		"burns": &"Spores",
		"consumes": [],
		"blast_radius_m": 4.0,
		"blast_impulse_ns": 120.0,
		"gas": &"Smoke",
	},
	{
		# THE QUENCH, and there is exactly ONE word for water: `Wet`. The build shipped with two —
		# `Apply_Water` applied the tag `Water`, the world's phase model and MAT_WATER's innate
		# tags said `Wet`, and this table keyed one rule on each — so the only water spell in the
		# game could not put out a fire it hit (the pair landed on ONE entity and the Water rule
		# was INTER-only), which is the identical single-entity blind spot as the spore fix above,
		# found by an audit in the rule the implementer did not think to re-check. SCOPE_BOTH and
		# one vocabulary close both holes at once.
		"tags": [&"Burning", &"Wet"],
		"scope": SCOPE_BOTH,
		"adds": [],
		"removes": [&"Burning", &"Wet"],
		"burns": &"",
		"consumes": [],
		"blast_radius_m": 0.0,
		"blast_impulse_ns": 0.0,
		"gas": &"Steam",
	},
]

## Result tags LAPSE. `Burning`, `Explosion` and `Smoke` were added with no expiry, so every
## survivor of an explosion carried `Explosion` forever, every smoke-touched entity stayed smoky
## for the run, and a thing set alight burned eternally with no fuel model — three permanent
## flags wearing event names. Frames at 60 Hz.
const RESULT_TAG_LIFETIME_FRAMES: Dictionary = {
	&"Burning": 900,
	&"Explosion": 120,
	&"Smoke": 600,
}

## The fire model (the other half of declared gap G-7, undeclared until the audit: `Burning`
## damaged nothing, consumed nothing and never went out). Per Micro frame, a burning entity
## heats its own surface, warms the chunk air, conducts into whatever it touches, and — if it is
## made of something combustible — takes damage until it burns out or dies.
const FIRE_SELF_HEAT_W: float = 15000.0
const FIRE_AIR_HEAT_W: float = 40000.0
const BURN_DPS: float = 4.0
const BURN_CONTACT_AREA_M2: float = 0.25
## Burning entities processed per tick. Bounds the per-frame hash queries in a burning crowd.
const MAX_BURNING_PER_TICK: int = 16

## Latent heat of vaporisation of water, J/kg. Quenching a fire costs this much energy per
## kilogram boiled off, which is why water works and why the room gets damp rather than cold.
const QUENCH_J_PER_KG: float = 2257000.0
## Kilograms of water a single quench reaction boils. One splash.
const QUENCH_MASS_KG: float = 1.0

## Sorted-pair key -> rule. Built once, lazily, so the sort cannot be skipped by an author.
static var _index: Dictionary = {}

var reactions_fired: int = 0
var cooldowns_held: int = 0
var tags_expired: int = 0
var energy_released_j: float = 0.0
var ambient_delta_c: float = 0.0
## Cumulative, like the mutation counters: fires are rare events and a per-tick reset reads as
## zero on every overlay frame that matters.
var ignitions: int = 0
var burn_deaths: int = 0
var sources_exhausted: int = 0

## Shares the thermodynamics conduction model rather than inventing a second one. This is the
## production caller `conduct_pair` never had: a fully-tested, stability-analysed body-to-body
## conduction path shipped in Sprint 1 and NEVER RAN — a fire could not heat the thing beside it.
var _thermo: ThermodynamicsSystem = ThermodynamicsSystem.new()


## Sorted-pair key for two tags. `A+B` and `B+A` produce the same string, which is the entire
## point of the convention (review F2).
static func key_for(a: StringName, b: StringName) -> String:
	var pair: Array[String] = [String(a), String(b)]
	pair.sort()
	return "%s+%s" % [pair[0], pair[1]]


static func rule_for(a: StringName, b: StringName, scope: StringName) -> Dictionary:
	_build_index()
	return _index.get("%s|%s" % [key_for(a, b), scope], {})


static func _build_index() -> void:
	if not _index.is_empty():
		return
	for rule in RULES:
		var tags: Array = rule["tags"]
		var key: String = key_for(tags[0], tags[1])
		var scope: StringName = rule["scope"]
		if scope == SCOPE_BOTH:
			_index["%s|%s" % [key, SCOPE_INTRA]] = rule
			_index["%s|%s" % [key, SCOPE_INTER]] = rule
			continue
		_index["%s|%s" % [key, scope]] = rule


## One pass over the Active chemistry set. Expiry first, then INTRA, then INTER — expiry first
## because a cooldown that lapsed last frame must not block this frame's reaction, and a lock
## that outlives its own deadline by a tick is indistinguishable in play from one that is stuck.
func run(
	micro_frame: int, chunk: ChunkData, hash: SpatialHash,
	combat: ActionResolutionSystem = null
) -> void:
	reactions_fired = 0
	cooldowns_held = 0
	energy_released_j = 0.0
	ambient_delta_c = 0.0
	tags_expired = _expire_all(micro_frame)

	var burn_budget: int = MAX_BURNING_PER_TICK
	var rows: PackedInt32Array = ECSManager.query(ComponentMask.CHEMISTRY)
	for i in rows.size():
		var row: int = rows[i]
		# `.get`, NOT `[row]`. A rule with a `consumes` clause destroys an entity mid-pass, and the
		# row list was snapshotted before that happened — indexing would crash on the corpse of a
		# spore cloud this very loop just detonated.
		var chemistry: ChemistryComponent = ECSManager.chemistries.get(row)
		if chemistry == null:
			continue
		# Combustion runs BEFORE the cooldown gate: the lock stops reactions re-triggering, and a
		# fire that pauses for 60 frames after every event reads as a fire that flickers off.
		if chemistry.has_tag(&"Burning") and burn_budget > 0:
			burn_budget -= 1
			_burn_tick(row, chemistry, micro_frame, chunk, hash, combat)
		elif _should_ignite(row, chemistry):
			ignitions += 1
			chemistry.add_tag(
				&"Burning", micro_frame + int(RESULT_TAG_LIFETIME_FRAMES[&"Burning"])
			)
		if chemistry.has_tag(COOLDOWN_TAG):
			cooldowns_held += 1
			continue
		if reactions_fired >= MAX_REACTIONS_PER_TICK:
			continue
		if not _react_intra(row, chemistry, micro_frame, chunk):
			_react_inter(row, chemistry, micro_frame, chunk, hash)


## Autoignition (declared gap G-7): hot enough IS alight, for materials with an ignition point.
## This is what lets a forge fire spread to the woodpile with no spell involved.
func _should_ignite(row: int, chemistry: ChemistryComponent) -> bool:
	if chemistry.has_tag(&"Wet"):
		return false
	var physical: PhysicalPropertyComponent = ECSManager.physicals.get(row)
	if physical == null:
		return false
	var threshold: float = MaterialLibrary.ignition_c(ECSManager.materials.get(row))
	return not is_nan(threshold) and physical.temperature_c() >= threshold


## One frame of being on fire. Self-heat, air heat, conduction into contacts, damage to
## combustible bodies, and the heat-source fuel drain that lets a brazier BURN DOWN.
func _burn_tick(
	row: int,
	chemistry: ChemistryComponent,
	micro_frame: int,
	chunk: ChunkData,
	hash: SpatialHash,
	combat: ActionResolutionSystem
) -> void:
	var dt: float = 1.0 / float(WorldConstants.MICRO_TICK_HZ)
	var physical: PhysicalPropertyComponent = ECSManager.physicals.get(row)
	var source: HeatSourceComponent = ECSManager.heat_sources.get(row)

	if source != null:
		# A fuelled fire spends its fuel. `output_j_per_tick` was declared, documented and read
		# by nothing, so a lit brazier burned forever for free.
		var released: float = source.consume(source.output_j_per_tick)
		_heat_the_air(chunk, released)
		if not source.is_lit():
			chemistry.remove_tag(&"Burning")
			sources_exhausted += 1
			return
	else:
		_heat_the_air(chunk, FIRE_AIR_HEAT_W * dt)

	if physical != null:
		ThermodynamicsSystem.apply_surface_energy(
			physical, ECSManager.materials.get(row), FIRE_SELF_HEAT_W * dt,
			_exposed_area_cm2(row)
		)
		# The source's ceiling is real now: a brazier is hot, not unboundedly hot.
		if source != null and physical.temperature_c() > source.max_temperature:
			physical.set_temperature_c(source.max_temperature)
		_conduct_to_contacts(row, physical, hash, dt)

	_char_the_body(row, micro_frame, combat)


## Fire spreads by TOUCH, through the same conduction model everything else uses. This is the
## production wire `ThermodynamicsSystem.conduct_pair` shipped without.
func _conduct_to_contacts(
	row: int, physical: PhysicalPropertyComponent, hash: SpatialHash, dt: float
) -> void:
	if hash == null:
		return
	var neighbours: PackedInt32Array = hash.query_radius(
		ECSManager.position_of(row), CONTACT_RADIUS_M
	)
	for i in neighbours.size():
		var other: int = neighbours[i]
		if other == row:
			continue
		var theirs: PhysicalPropertyComponent = ECSManager.physicals.get(other)
		if theirs != null:
			_thermo.conduct_pair(physical, theirs, BURN_CONTACT_AREA_M2, dt)


## Fire hurts what can burn. Stone survives standing in it; flesh and wood do not. Damage is
## reported once a second rather than sixty times, or one fire fills the whole outcome feed.
func _char_the_body(row: int, micro_frame: int, combat: ActionResolutionSystem) -> void:
	var body: BodyComponent = ECSManager.bodies.get(row)
	if body == null or not body.is_alive():
		return
	if MaterialLibrary.combustion_energy_j(
		ECSManager.physicals.get(row), ECSManager.materials.get(row)
	) <= 0.0:
		return
	var dt: float = 1.0 / float(WorldConstants.MICRO_TICK_HZ)
	body.health = maxf(0.0, body.health - BURN_DPS * dt)
	if micro_frame % WorldConstants.MICRO_TICK_HZ == 0:
		ECSEvents.entity_damaged.emit(
			ECSManager.handle_of(row), BURN_DPS, body.health, &"burning"
		)
	if body.is_alive() or row == WorldConstants.PLAYER_INDEX:
		# The player's death has one owner: the Simulation tick's death check and DeathLoopSystem.
		return
	burn_deaths += 1
	ECSEvents.entity_died.emit(ECSManager.handle_of(row), &"burned")
	if combat != null:
		combat._convert_to_corpse(row)


func _expire_all(micro_frame: int) -> int:
	var lapsed: int = 0
	for row in ECSManager.query(ComponentMask.CHEMISTRY):
		var chemistry: ChemistryComponent = ECSManager.chemistries.get(row)
		if chemistry != null:
			lapsed += chemistry.expire_tags(micro_frame)
	return lapsed


## Both tags on one entity. Returns true if something fired, so the caller does not then also
## look for a neighbour — one entity resolves at most one reaction per tick, which is what keeps
## the per-tick cost bounded and the ordering easy to reason about.
func _react_intra(
	row: int, chemistry: ChemistryComponent, micro_frame: int, chunk: ChunkData
) -> bool:
	var tags: Array[StringName] = chemistry.active_tags.duplicate()
	for a in tags.size():
		for b in range(a + 1, tags.size()):
			var rule: Dictionary = rule_for(tags[a], tags[b], SCOPE_INTRA)
			if rule.is_empty():
				continue
			# The owner map matters for INTRA too: `burns` and `consumes` name a TAG, and both
			# tags belong to this one entity. Passing null here made every INTRA reaction release
			# exactly zero energy, so a self-igniting spore cloud warmed nothing.
			_fire(rule, row, row, micro_frame, chunk, {tags[a]: row, tags[b]: row})
			return true
	return false


## Two overlapping entities. The SpatialHash is the only overlap primitive in the build; there
## are no Godot colliders anywhere in this path.
func _react_inter(
	row: int,
	chemistry: ChemistryComponent,
	micro_frame: int,
	chunk: ChunkData,
	hash: SpatialHash
) -> void:
	if hash == null:
		return
	var neighbours: PackedInt32Array = hash.query_radius(
		ECSManager.position_of(row), CONTACT_RADIUS_M
	)
	for i in neighbours.size():
		var other: int = neighbours[i]
		if other == row:
			continue
		var their: ChemistryComponent = ECSManager.chemistries.get(other)
		if their == null or their.has_tag(COOLDOWN_TAG):
			continue
		for mine in chemistry.active_tags:
			for theirs in their.active_tags:
				var rule: Dictionary = rule_for(mine, theirs, SCOPE_INTER)
				if rule.is_empty():
					continue
				# `mine` belongs to `row` and `theirs` to `other`, so the rule's `burns` and
				# `consumes` names resolve to a specific entity rather than to whichever one the
				# loop happened to reach first.
				_fire(rule, row, other, micro_frame, chunk, {mine: row, theirs: other})
				return


## Applies one rule. Everything a reaction can do happens here, in one place, so a new rule
## cannot quietly acquire a side effect no other rule has.
func _fire(
	rule: Dictionary,
	row: int,
	other: int,
	micro_frame: int,
	chunk: ChunkData,
	owners: Variant
) -> void:
	reactions_fired += 1
	var deadline: int = micro_frame + WorldConstants.REACTION_COOLDOWN_FRAMES
	var centre: Vector3 = ECSManager.position_of(row)

	var energy: float = _energy_of(rule, owners)
	energy_released_j += energy
	_apply_energy(row, energy)
	if other != row:
		_apply_energy(other, energy)
	_heat_the_air(chunk, energy)

	# An INTRA rule has ONE participant listed twice. Deduplicated here rather than guarded inside
	# the loop, because applying the lock twice is harmless and applying `removes` twice is not.
	var participants: Array[int] = [row]
	if other != row:
		participants.append(other)
	for participant in participants:
		var chemistry: ChemistryComponent = ECSManager.chemistries.get(participant)
		if chemistry == null:
			continue
		for tag in rule["removes"]:
			chemistry.remove_tag(tag)
		for tag in rule["adds"]:
			# Result tags carry their lifetime. Without this, `Explosion` was a permanent flag on
			# every survivor and `Burning` was eternal fire with no fuel.
			var lifetime: int = int(RESULT_TAG_LIFETIME_FRAMES.get(tag, 0))
			if lifetime > 0:
				chemistry.add_tag(tag, micro_frame + lifetime)
			else:
				chemistry.add_tag(tag)
		# THE LOCK. Applied to every participant, including one that was only removed FROM, so a
		# quench cannot be re-run against the same pair on the very next frame.
		chemistry.add_tag(COOLDOWN_TAG, deadline)

	_spawn_gas(rule, centre)
	_blast(rule, centre)
	_consume(rule, owners)


## Energy in joules. A rule names WHICH participant burns; the material library says how much
## that body's mass is worth. A rule with no `burns` participant is a quench, which ABSORBS.
func _energy_of(rule: Dictionary, owners: Variant) -> float:
	var burns: StringName = rule["burns"]
	if burns == &"":
		return -QUENCH_J_PER_KG * QUENCH_MASS_KG if rule["gas"] == &"Steam" else 0.0
	if not (owners is Dictionary) or not owners.has(burns):
		# INTRA rules have no per-tag owner map. Nothing burns that is not attributable.
		return 0.0
	var fuel_row: int = int(owners[burns])
	return MaterialLibrary.combustion_energy_j(
		ECSManager.physicals.get(fuel_row), ECSManager.materials.get(fuel_row)
	)


## Surface heating, not bulk (review H2 / thermodynamics §7). Distributing a fireball over total
## mass raises an iron sword by +1485C while raising a human by +4.1C from the same blast, which
## is backwards. The exposed area is derived from the entity's own bounds so a big thing catches
## more of it than a small one.
func _apply_energy(row: int, joules: float) -> void:
	if is_zero_approx(joules):
		return
	var physical: PhysicalPropertyComponent = ECSManager.physicals.get(row)
	var composition: MaterialCompositionComponent = ECSManager.materials.get(row)
	if physical == null or composition == null:
		return
	ThermodynamicsSystem.apply_surface_energy(
		physical, composition, joules, _exposed_area_cm2(row)
	)


## Frontal area in cm^2, from the bounds box. Falls back to a human-scale 2,500 cm^2 for an
## entity with no bounds rather than to zero, which would silently make it fireproof.
func _exposed_area_cm2(row: int) -> float:
	var bounds: BoundsComponent = ECSManager.bounds.get(row)
	if bounds == null:
		return 2500.0
	var half: Vector3 = bounds.half_extents
	return maxf(4.0 * half.x * half.y * 10000.0, 100.0)


## The chunk's air takes the energy the bodies did not.
##
## THE ARITHMETIC, because "raises the ambient temp" is otherwise unfalsifiable: a 64x64 m chunk
## with a 3 m ceiling holds 12,288 m^3 of air at 1,206 J/(m^3*K), so 14.8 MJ raises it by one
## degree. One 0.1 kg spore cloud releases 1.8 MJ and moves it 0.12 C — small, and correct. A
## room's worth of them is a couple of degrees, which is the roadmap's success state and is
## visible in the inspector. Capped per tick so a large blast cannot spike a value that then
## conducts into every entity in the chunk.
func _heat_the_air(chunk: ChunkData, joules: float) -> void:
	if chunk == null or is_zero_approx(joules):
		return
	var air_volume_m3: float = (
		WorldConstants.CHUNK_SIZE_M * WorldConstants.CHUNK_SIZE_M
		* WorldConstants.CHUNK_AIR_HEIGHT_M
	)
	var per_degree: float = air_volume_m3 * WorldConstants.AIR_J_PER_M3_PER_C
	var change: float = clampf(
		joules / per_degree, -WorldConstants.MAX_AMBIENT_STEP_C, WorldConstants.MAX_AMBIENT_STEP_C
	)
	chunk.ambient_temperature_c += change
	ambient_delta_c += change


## Gas is an EXPANDING AURA, not a second cellular automaton.
##
## The roadmap asks for "gas and temperature propagation (e.g. expanding radii)". The Ephemeral
## primitive already expands a radius and applies tags through the SpatialHash, with mandatory
## TTL cleanup, and ADR-2 plus the Sprint 4 scaffolding both say magic and auras reuse it. A
## parallel gas grid would be a second thing to keep conservative across the LoD boundary, and
## the fluid CA is where liquid conservation is asserted. Declared rather than assumed: gases in
## the CA are handled separately in FluidDynamicsSystem, and this is the reaction PRODUCT path.
func _spawn_gas(rule: Dictionary, centre: Vector3) -> void:
	var gas: StringName = rule["gas"]
	if gas == &"":
		return
	var tags: Array[StringName] = [gas]
	var handle: int = EphemeralSystem.spawn_aura(centre, tags, 1.0, 3.0, EH.INVALID)
	var row: int = EH.index_of(handle)
	var ephemeral: EphemeralComponent = ECSManager.ephemerals.get(row)
	if ephemeral != null:
		ephemeral.expansion_mps = 2.0


## The kinetic half. Pushes nearby bodies outward with an impulse that falls off with distance.
##
## Velocity, not position: the collision sweep integrates it next frame, so a blast cannot punch
## anything through a wall. Capped, because impulse over a light mass is a divide that produces
## an entity leaving the chunk in one frame.
func _blast(rule: Dictionary, centre: Vector3) -> void:
	var radius: float = float(rule["blast_radius_m"])
	var impulse: float = float(rule["blast_impulse_ns"])
	if radius <= 0.0 or impulse <= 0.0:
		return
	# Chemistry is loud. An unseen explosion turns nearby heads (INVESTIGATE), which is the
	# perception contract every other violent event already honours.
	EphemeralSystem.spawn_noise(centre, radius * 4.0, 0.5, EH.INVALID)
	for row in ECSManager.query(ComponentMask.MOVER):
		var offset: Vector3 = ECSManager.position_of(row) - centre
		var distance: float = offset.length()
		if distance > radius:
			continue
		var direction: Vector3 = Vector3.UP if distance < 0.001 else offset / distance
		var falloff: float = pow(
			1.0 - distance / radius, WorldConstants.BLAST_FALLOFF_EXPONENT
		)
		var physical: PhysicalPropertyComponent = ECSManager.physicals.get(row)
		var mass: float = 70.0 if physical == null else maxf(physical.mass_kg, 0.1)
		var speed: float = minf(
			impulse * falloff / mass, WorldConstants.MAX_BLAST_SPEED_MPS
		)
		ECSManager.set_velocity(row, ECSManager.velocity_of(row) + direction * speed)


## Destroys participants the rule consumes. Row 0 is never consumed: the player's death has
## exactly one owner (`DeathLoopSystem`), and a chemistry rule quietly deleting the reserved row
## is the same class of defect as the corpse conversion that broke ADR-14 in Sprint 3.
func _consume(rule: Dictionary, owners: Variant) -> void:
	if not (owners is Dictionary):
		return
	for tag in rule["consumes"]:
		if not owners.has(tag):
			continue
		var row: int = int(owners[tag])
		if row == WorldConstants.PLAYER_INDEX:
			continue
		ECSManager.destroy_entity(ECSManager.handle_of(row))


func counters() -> Dictionary:
	return {
		"reactions_fired": reactions_fired,
		"reaction_cooldowns": cooldowns_held,
		"reaction_energy_j": energy_released_j,
		"reaction_ambient_c": ambient_delta_c,
		"tags_expired": tags_expired,
		"ignitions": ignitions,
		"burn_deaths": burn_deaths,
		"heat_sources_exhausted": sources_exhausted,
	}
