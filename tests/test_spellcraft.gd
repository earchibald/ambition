## The Grimoire back end: compilation, both caps, and casting (Sprint 4 §2/§3).
##
## The two caps fail DIFFERENTLY and that is the design, so both directions are asserted here:
## complexity REFUSES and geometry CLAMPS. A test suite that only checked "invalid spells are
## rejected" would pass against an implementation that refused an oversized radius, which would
## let a player author a spell they can never cast and never find out why.
extends GutTest

var _chunk: ChunkData
var _player_row: int
var _mind: MindComponent
var _compiler: SpellCompilerSystem


func before_each() -> void:
	GameLoopManager.set_physics_process(false)
	World.boot_scenario(World.SCENARIO_TEST_ARENA, 1)
	_chunk = World.active_chunk
	_player_row = ECSManager.resolve(ECSManager.player_handle())
	_mind = ECSManager.minds[_player_row]
	_compiler = SpellCompilerSystem.new()


func after_all() -> void:
	GameLoopManager.set_physics_process(true)


## The magic doc's standard fireball, verbatim, plus the ignition catalyst.
##
## TWO TRIGGERS, deliberately: the doc writes it as `On_Cast + Projectile(High) + On_Impact +
## Add_Temperature`, which is what forces the compiler to resolve trigger precedence rather than
## take whichever came last.
##
## `Add_Temperature` delivers JOULES and nothing else — there is no ignition-temperature model in
## the build, so heat alone does not set anything alight. A fireball meant to leave things burning
## has to say so. Complexity 8 against a starting budget of 15.
func _fireball() -> Array:
	return [&"On_Cast", &"Projectile", &"On_Impact", &"Add_Temperature", &"Apply_Burning"]


func _compile(runes: Array) -> Dictionary:
	return _compiler.compile(runes, _mind)


func _bind(runes: Array) -> CompiledSpell:
	var result: Dictionary = _compile(runes)
	assert_true(result["ok"], "the spell under test compiled: %s" % result["reason"])
	var spell: CompiledSpell = result["spell"]
	_mind.grimoire[spell.spell_id] = spell
	return spell


func _rebuild_hash() -> SpatialHash:
	var hash: SpatialHash = GameLoopManager.spatial_hash
	hash.rebuild(ECSManager.query(ComponentMask.SPATIAL))
	return hash


func _spawn_target(at: Vector3) -> int:
	var handle: int = ECSManager.allocate_entity()
	var row: int = EH.index_of(handle)
	ECSManager.set_position(row, at)
	ECSManager.add_component_bit(row, ComponentMask.POSITION)
	var bounds := BoundsComponent.new()
	bounds.half_extents = Vector3(0.4, 0.9, 0.4)
	ECSManager.bounds[row] = bounds
	ECSManager.add_component_bit(row, ComponentMask.BOUNDS)
	var physical := PhysicalPropertyComponent.new()
	physical.volume_cm3 = 66000.0
	var composition := MaterialCompositionComponent.new({MaterialLibrary.MAT_BIOMASS: 1.0})
	MaterialLibrary.recompute_mass(physical, composition)
	physical.set_temperature_c(37.0)
	ECSManager.physicals[row] = physical
	ECSManager.materials[row] = composition
	ECSManager.add_component_bit(row, ComponentMask.PHYSICAL | ComponentMask.MATERIAL)
	ECSManager.chemistries[row] = ChemistryComponent.new()
	ECSManager.add_component_bit(row, ComponentMask.CHEMISTRY)
	return row


# --- The bootstrap. Without this the whole layer is unreachable. ------------------------------


## An input audit found `Rune_Stability` named by the spec with no bootstrap value anywhere. At 0
## the complexity budget is 0 and NOTHING compiles, so the entire magic layer would ship built,
## tested through synthetic minds, and unreachable in play.
func test_a_new_adventurer_can_actually_compile_something() -> void:
	assert_gt(_mind.insight_in(&"Rune_Stability"), 0, "Rune_Stability has a bootstrap value")
	assert_gt(SpellCompilerSystem.complexity_budget(_mind), 0.0, "and it buys a real budget")
	assert_true(_compile(_fireball())["ok"], "a starting player can compile the standard fireball")


func test_the_starting_runes_are_all_real() -> void:
	for rune_id in RuneLibrary.STARTING_RUNES:
		assert_true(RuneLibrary.exists(rune_id), "%s is in the rune table" % rune_id)


# --- Structural validation --------------------------------------------------------------------


func test_an_empty_rune_array_is_refused() -> void:
	assert_eq(_compile([])["reason"], SpellCompilerSystem.REASON_NO_RUNES)


func test_a_spell_needs_a_trigger_a_shape_and_a_catalyst() -> void:
	assert_eq(
		_compile([&"Projectile", &"Add_Temperature"])["reason"],
		SpellCompilerSystem.REASON_NEEDS_TRIGGER
	)
	assert_eq(
		_compile([&"On_Cast", &"Add_Temperature"])["reason"],
		SpellCompilerSystem.REASON_NEEDS_SHAPE
	)
	assert_eq(
		_compile([&"On_Cast", &"Projectile"])["reason"],
		SpellCompilerSystem.REASON_NEEDS_CATALYST
	)


func test_an_invented_rune_is_refused() -> void:
	assert_eq(
		_compile([&"On_Cast", &"Projectile", &"Summon_Moon"])["reason"],
		SpellCompilerSystem.REASON_UNKNOWN_RUNE
	)


## Knowledge is diegetic (magic doc §1). A rune that exists but has not been excavated is not
## castable, or the DAG's ruined libraries have nothing to hold.
func test_a_rune_you_have_not_learned_is_refused() -> void:
	assert_false(_mind.known_runes.has(&"Apply_Filth"), "the starting grimoire is small")
	assert_eq(
		_compile([&"On_Cast", &"Projectile", &"Apply_Filth"])["reason"],
		SpellCompilerSystem.REASON_NOT_LEARNED
	)


func test_learning_a_rune_makes_it_compilable() -> void:
	_mind.known_runes.append(&"Apply_Filth")
	assert_true(
		_compile([&"On_Cast", &"Projectile", &"Apply_Filth"])["ok"],
		"excavating the knowledge is what unlocks it"
	)


# --- The complexity cap REFUSES ----------------------------------------------------------------


func test_a_spell_beyond_your_cognitive_limit_is_refused() -> void:
	_mind.insight[&"Rune_Stability"] = 1
	assert_eq(
		_compile(_fireball())["reason"],
		SpellCompilerSystem.REASON_TOO_COMPLEX,
		"complexity 8 against a budget of 1.5"
	)


func test_the_budget_is_exactly_rune_stability_times_the_multiplier() -> void:
	_mind.insight[&"Rune_Stability"] = 20
	assert_almost_eq(SpellCompilerSystem.complexity_budget(_mind), 30.0, 0.001, "20 * 1.5")


## The boundary. A spell exactly AT the budget compiles; one point over does not.
func test_the_complexity_gate_is_inclusive_at_the_budget() -> void:
	_mind.insight[&"Rune_Stability"] = 4
	# Budget 6.0. On_Cast(1) + Projectile(2) + Apply_Water(1) = 4, plus Apply_Burning(2) = 6.
	assert_true(
		_compile([&"On_Cast", &"Projectile", &"Apply_Water", &"Apply_Burning"])["ok"],
		"complexity 6 against a budget of 6.0 fits"
	)
	_mind.insight[&"Rune_Stability"] = 3
	assert_eq(
		_compile([&"On_Cast", &"Projectile", &"Apply_Water", &"Apply_Burning"])["reason"],
		SpellCompilerSystem.REASON_TOO_COMPLEX,
		"complexity 6 against a budget of 4.5 does not"
	)


func test_more_runes_than_the_hard_limit_are_refused() -> void:
	var many: Array = []
	for _i in WorldConstants.MAX_SPELL_RUNES + 1:
		many.append(&"On_Cast")
	assert_eq(_compile(many)["reason"], SpellCompilerSystem.REASON_TOO_MANY)


# --- The geometric caps CLAMP ------------------------------------------------------------------


func test_an_oversized_radius_is_clamped_rather_than_refused() -> void:
	_mind.insight[&"Rune_Stability"] = 40
	_mind.known_runes.append(&"Great_Aura")
	var result: Dictionary = _compile([&"On_Cast", &"Great_Aura", &"Add_Temperature"])
	assert_true(result["ok"], "a map-nuke radius is capped, NOT refused")
	var spell: CompiledSpell = result["spell"]
	assert_almost_eq(
		spell.radius_m, WorldConstants.MAX_SPELL_RADIUS_M, 0.001, "forced down to 15 m"
	)
	assert_true(
		spell.caps_applied.has(SpellCompilerSystem.CAP_RADIUS),
		"and the player is TOLD it was capped, rather than silently handed a different spell"
	)


func test_an_oversized_speed_is_clamped() -> void:
	_mind.insight[&"Rune_Stability"] = 40
	_mind.known_runes.append(&"Heavy_Projectile")
	var spell: CompiledSpell = _compile(
		[&"On_Cast", &"Heavy_Projectile", &"Add_Temperature"]
	)["spell"]
	assert_almost_eq(spell.speed_mps, WorldConstants.MAX_SPELL_SPEED_MPS, 0.001, "60 -> 40 m/s")
	assert_true(spell.caps_applied.has(SpellCompilerSystem.CAP_SPEED))


func test_the_lifetime_is_capped() -> void:
	_mind.insight[&"Rune_Stability"] = 40
	_mind.known_runes.append(&"Great_Aura")
	var spell: CompiledSpell = _compile([&"On_Cast", &"Great_Aura", &"Add_Temperature"])["spell"]
	assert_lte(spell.ttl_s, WorldConstants.MAX_SPELL_TTL_S, "magic must die")


## THE CAP THAT IS EASY TO GET WRONG. Capping the starting radius alone leaves an expanding aura
## free to grow past it, so the cap is defeated by any rune with an expansion rate.
func test_an_expanding_aura_cannot_grow_past_the_radius_cap() -> void:
	_mind.insight[&"Rune_Stability"] = 40
	_mind.known_runes.append(&"Great_Aura")
	var spell: CompiledSpell = _compile([&"On_Cast", &"Great_Aura", &"Add_Temperature"])["spell"]
	var final_extent: float = spell.radius_m + spell.expansion_mps * spell.ttl_s
	assert_lte(
		final_extent,
		WorldConstants.MAX_SPELL_RADIUS_M + 0.001,
		"the FINAL extent is what the SpatialHash query costs, so that is what must be capped"
	)


func test_an_ordinary_spell_is_not_capped_at_all() -> void:
	var spell: CompiledSpell = _compile(_fireball())["spell"]
	assert_false(spell.was_capped(), "the caps are anti-crash rules, not a tax on every spell")


func test_strain_scales_with_complexity() -> void:
	var spell: CompiledSpell = _compile(_fireball())["spell"]
	assert_eq(spell.complexity, 8, "1 + 2 + 1 + 2 + 2")
	assert_almost_eq(
		spell.strain_cost,
		8.0 * WorldConstants.STRAIN_PER_COMPLEXITY,
		0.001,
		"strain is complexity * 2.5"
	)


## Deterministic ids, so the same runes bind to the same Action_ID across a save/load and the
## response of the world is reproducible from seeds (ADR-20).
func test_the_same_runes_always_compile_to_the_same_id() -> void:
	assert_eq(
		_compile(_fireball())["spell"].spell_id,
		_compile(_fireball())["spell"].spell_id,
		"the Action_ID is a function of the runes, not of when it was compiled"
	)


# --- Casting -----------------------------------------------------------------------------------


func test_casting_an_unbound_id_is_refused_and_says_so() -> void:
	var rejections: Array[String] = []
	ECSEvents.action_rejected.connect(
		func(_a: int, _action: StringName, reason: StringName) -> void:
			rejections.append(String(reason))
	)
	assert_false(
		GameLoopManager.combat.resolve_cast(_player_row, &"Nothing_Bound", Vector3.FORWARD),
		"nothing is cast"
	)
	assert_eq(rejections, ["no spell bound"], "and the player is told why")


func test_a_cast_spawns_an_ephemeral_and_charges_strain() -> void:
	var spell: CompiledSpell = _bind(_fireball())
	var body: BodyComponent = ECSManager.bodies[_player_row]
	var stamina_before: float = body.stamina
	var before: int = ECSManager.query(ComponentMask.EPHEMERAL).size()

	assert_true(GameLoopManager.combat.resolve_cast(_player_row, spell.spell_id, Vector3.FORWARD))
	assert_eq(
		ECSManager.query(ComponentMask.EPHEMERAL).size(), before + 1, "a spell became an entity"
	)
	assert_almost_eq(
		body.stamina, stamina_before - spell.strain_cost, 0.001, "magic costs stamina, not mana"
	)


func test_a_cast_you_cannot_pay_for_is_refused() -> void:
	var spell: CompiledSpell = _bind(_fireball())
	var body: BodyComponent = ECSManager.bodies[_player_row]
	body.strain = body.max_stamina
	assert_false(
		GameLoopManager.combat.resolve_cast(_player_row, spell.spell_id, Vector3.FORWARD),
		"a cast you cannot pay for does not half-happen"
	)


func test_a_refused_cast_costs_nothing() -> void:
	var spell: CompiledSpell = _bind(_fireball())
	var body: BodyComponent = ECSManager.bodies[_player_row]
	body.strain = body.max_stamina
	GameLoopManager.combat.resolve_cast(_player_row, spell.spell_id, Vector3.FORWARD)
	assert_almost_eq(
		body.strain, body.max_stamina, 0.001, "no strain was added by the cast that did not run"
	)


## The roadmap's success state: the fireball travels, hits something, applies its tag, and
## deletes itself.
func test_a_fireball_travels_burns_what_it_hits_and_dies() -> void:
	var spell: CompiledSpell = _bind(_fireball())
	var origin: Vector3 = ECSManager.position_of(_player_row)
	var target: int = _spawn_target(origin + Vector3(0.0, 0.0, 6.0))
	GameLoopManager.combat.resolve_cast(_player_row, spell.spell_id, Vector3(0.0, 0.0, 1.0))

	var ephemerals := EphemeralSystem.new()
	ephemerals.sampler = World.sampler()
	var hit: bool = false
	for _frame in 60:
		ephemerals.run(1.0 / 60.0, _rebuild_hash())
		if ECSManager.chemistries[target].has_tag(&"Burning"):
			hit = true
			break
	assert_true(hit, "the projectile reached the target and applied its catalyst")
	# The detonation leaves a NOISE ephemeral behind on purpose — the bang outlives the bolt so
	# unseen listeners can INVESTIGATE. Let its half-second TTL lapse before asserting cleanup.
	for _echo in 31:
		ephemerals.run(1.0 / 60.0, _rebuild_hash())
	assert_eq(
		ECSManager.query(ComponentMask.EPHEMERAL).size(), 0, "and deleted itself on impact"
	)


func test_a_fireball_that_hits_nothing_still_expires() -> void:
	var spell: CompiledSpell = _bind(_fireball())
	GameLoopManager.combat.resolve_cast(_player_row, spell.spell_id, Vector3(0.0, 0.0, 1.0))
	var ephemerals := EphemeralSystem.new()
	ephemerals.sampler = World.sampler()
	for _frame in 400:
		ephemerals.run(1.0 / 60.0, _rebuild_hash())
	assert_eq(
		ECSManager.query(ComponentMask.EPHEMERAL).size(),
		0,
		"an ephemeral that never expires is a leak with a radius"
	)


## The fireball must not detonate in the caster's own hand. It spawns clear of them, and the
## contact test excludes its own source.
func test_a_projectile_does_not_detonate_on_its_caster() -> void:
	var spell: CompiledSpell = _bind(_fireball())
	GameLoopManager.combat.resolve_cast(_player_row, spell.spell_id, Vector3(0.0, 0.0, 1.0))
	var ephemerals := EphemeralSystem.new()
	ephemerals.sampler = World.sampler()
	ephemerals.run(1.0 / 60.0, _rebuild_hash())
	var chemistry: ChemistryComponent = ECSManager.chemistries.get(_player_row)
	assert_false(chemistry.has_tag(&"Burning"), "the caster is not set alight by their own spell")


func test_an_aura_applies_its_tag_to_everything_it_covers() -> void:
	_mind.known_runes.append(&"Apply_Water")
	var spell: CompiledSpell = _bind([&"On_Cast", &"Aura", &"Apply_Water"])
	var origin: Vector3 = ECSManager.position_of(_player_row)
	var near: int = _spawn_target(origin + Vector3(2.0, 0.0, 0.0))
	var far: int = _spawn_target(origin + Vector3(25.0, 0.0, 0.0))
	GameLoopManager.combat.resolve_cast(_player_row, spell.spell_id, Vector3.FORWARD)

	var ephemerals := EphemeralSystem.new()
	ephemerals.sampler = World.sampler()
	ephemerals.run(1.0 / 60.0, _rebuild_hash())
	assert_true(ECSManager.chemistries[near].has_tag(&"Wet"), "inside the radius")
	assert_false(ECSManager.chemistries[far].has_tag(&"Wet"), "25 m away is not inside 4 m")


# --- Absorb_Tag conservation (review D8) -------------------------------------------------------


func _light_a_campfire(at: Vector3, energy: float) -> int:
	var handle: int = ECSManager.allocate_entity()
	var row: int = EH.index_of(handle)
	ECSManager.set_position(row, at)
	ECSManager.add_component_bit(row, ComponentMask.POSITION)
	var source := HeatSourceComponent.new()
	source.stored_energy = energy
	ECSManager.heat_sources[row] = source
	ECSManager.add_component_bit(row, ComponentMask.HEAT_SOURCE)
	var chemistry := ChemistryComponent.new()
	chemistry.add_tag(&"Burning")
	ECSManager.chemistries[row] = chemistry
	ECSManager.add_component_bit(row, ComponentMask.CHEMISTRY)
	return row


func test_a_spell_with_nothing_to_absorb_fizzles() -> void:
	_mind.known_runes.append(&"Absorb_Heat")
	var spell: CompiledSpell = _bind([&"On_Cast", &"Projectile", &"Absorb_Heat"])
	var reasons: Array[String] = []
	ECSEvents.action_rejected.connect(
		func(_a: int, _action: StringName, reason: StringName) -> void:
			reasons.append(String(reason))
	)
	assert_false(GameLoopManager.combat.resolve_cast(_player_row, spell.spell_id, Vector3.FORWARD))
	assert_eq(reasons.size(), 1, "the fizzle is reported, not silent")
	assert_true(String(reasons[0]).contains("fizzled"), "and it says what went wrong")


func test_absorbing_consumes_the_resource_it_took() -> void:
	_mind.known_runes.append(&"Absorb_Heat")
	var spell: CompiledSpell = _bind([&"On_Cast", &"Projectile", &"Absorb_Heat"])
	var fire: int = _light_a_campfire(ECSManager.position_of(_player_row) + Vector3(1.0, 0, 0),
		500000.0)
	assert_true(GameLoopManager.combat.resolve_cast(_player_row, spell.spell_id, Vector3.FORWARD))
	assert_almost_eq(
		ECSManager.heat_sources[fire].stored_energy,
		300000.0,
		1.0,
		"the campfire is 200 kJ poorer — magic conserves, it does not conjure"
	)


## THE DOUBLE-SPEND. Two casters in one tick may not both draw the same campfire dry.
func test_two_casters_cannot_spend_the_same_campfire() -> void:
	_mind.known_runes.append(&"Absorb_Heat")
	var spell: CompiledSpell = _bind([&"On_Cast", &"Projectile", &"Absorb_Heat"])
	# Exactly one spell's worth of heat in the world.
	_light_a_campfire(ECSManager.position_of(_player_row) + Vector3(1.0, 0, 0), 200000.0)
	assert_true(
		GameLoopManager.combat.resolve_cast(_player_row, spell.spell_id, Vector3.FORWARD),
		"the first caster gets it"
	)
	assert_false(
		GameLoopManager.combat.resolve_cast(_player_row, spell.spell_id, Vector3.FORWARD),
		"the second finds it already spent and fizzles"
	)


## The source tag comes off only when the underlying quantity is gone. Ripping [Burning] from a
## bonfire because someone drew a candle's worth of heat is the bug quantifying it prevents.
func test_a_bonfire_keeps_burning_after_a_small_draw() -> void:
	_mind.known_runes.append(&"Absorb_Heat")
	var spell: CompiledSpell = _bind([&"On_Cast", &"Projectile", &"Absorb_Heat"])
	var fire: int = _light_a_campfire(ECSManager.position_of(_player_row) + Vector3(1.0, 0, 0),
		5000000.0)
	GameLoopManager.combat.resolve_cast(_player_row, spell.spell_id, Vector3.FORWARD)
	assert_true(
		ECSManager.chemistries[fire].has_tag(&"Burning"), "a bonfire survives being drawn on"
	)


func test_a_drained_fire_goes_out() -> void:
	_mind.known_runes.append(&"Absorb_Heat")
	var spell: CompiledSpell = _bind([&"On_Cast", &"Projectile", &"Absorb_Heat"])
	var fire: int = _light_a_campfire(ECSManager.position_of(_player_row) + Vector3(1.0, 0, 0),
		200000.0)
	GameLoopManager.combat.resolve_cast(_player_row, spell.spell_id, Vector3.FORWARD)
	assert_false(
		ECSManager.chemistries[fire].has_tag(&"Burning"),
		"drawing the last of it extinguishes it"
	)


func test_absorbed_energy_discounts_strain_but_never_refunds_it() -> void:
	_mind.known_runes.append(&"Absorb_Heat")
	var spell: CompiledSpell = _bind([&"On_Cast", &"Projectile", &"Absorb_Heat"])
	_light_a_campfire(
		ECSManager.position_of(_player_row) + Vector3(1.0, 0, 0), 900000000.0
	)
	var body: BodyComponent = ECSManager.bodies[_player_row]
	body.stamina = 100.0
	GameLoopManager.combat.resolve_cast(_player_row, spell.spell_id, Vector3.FORWARD)
	assert_lte(body.stamina, 100.0, "an enormous fire cannot pay the caster stamina")
	assert_gte(body.stamina, 100.0 - spell.strain_cost, "but it does discount the cost")


# --- Triggers actually do something ------------------------------------------------------------


## THE DEFECT THIS CLOSES. `trigger`, `delay_s` and `SHAPE_CONE` were all written by the compiler
## and read by nobody, so four trigger runes compiled, cost complexity, and produced identical
## behaviour — and a Cone was a sphere with a misleading name. Found by grepping for a second
## reference, not by any test, which is exactly how the last four instances of this were found.
func test_the_most_specific_trigger_wins_regardless_of_order() -> void:
	var forward: CompiledSpell = _compile(
		[&"On_Cast", &"On_Impact", &"Projectile", &"Apply_Burning"]
	)["spell"]
	var backward: CompiledSpell = _compile(
		[&"On_Impact", &"On_Cast", &"Projectile", &"Apply_Burning"]
	)["spell"]
	assert_eq(forward.trigger, &"On_Impact", "impact fires later than cast, so impact wins")
	assert_eq(
		backward.trigger,
		forward.trigger,
		"and the answer does not depend on which number key was pressed first"
	)


## An On_Cast projectile does NOT detonate. It trails its payload and rides out its TTL, which is
## a different spell from a fireball — and the difference is the point of having triggers at all.
func test_an_on_cast_projectile_trails_instead_of_detonating() -> void:
	var spell: CompiledSpell = _bind([&"On_Cast", &"Projectile", &"Apply_Burning"])
	var origin: Vector3 = ECSManager.position_of(_player_row)
	var target: int = _spawn_target(origin + Vector3(0.0, 0.0, 5.0))
	GameLoopManager.combat.resolve_cast(_player_row, spell.spell_id, Vector3(0.0, 0.0, 1.0))

	var ephemerals := EphemeralSystem.new()
	ephemerals.sampler = World.sampler()
	for _frame in 30:
		ephemerals.run(1.0 / 60.0, _rebuild_hash())
	assert_true(ECSManager.chemistries[target].has_tag(&"Burning"), "it still burns what it passes")
	assert_eq(ephemerals.detonations, 0, "but it never went off")


## The magic doc's "Trap": a physical landmine built from the same aura as a smoke cloud, waiting
## for somebody who is not its caster to walk into it.
func test_a_proximity_trap_waits_for_someone_to_step_on_it() -> void:
	_mind.insight[&"Rune_Stability"] = 20
	_mind.known_runes.append(&"On_Proximity")
	var spell: CompiledSpell = _bind([&"On_Proximity", &"Aura", &"Apply_Burning"])
	GameLoopManager.combat.resolve_cast(_player_row, spell.spell_id, Vector3.FORWARD)

	var ephemerals := EphemeralSystem.new()
	ephemerals.sampler = World.sampler()
	ephemerals.run(1.0 / 60.0, _rebuild_hash())
	assert_eq(ephemerals.detonations, 0, "the caster standing beside their own trap is not a victim")

	var victim: int = _spawn_target(ECSManager.position_of(_player_row) + Vector3(1.0, 0.0, 0.0))
	ephemerals.run(1.0 / 60.0, _rebuild_hash())
	assert_true(ECSManager.chemistries[victim].has_tag(&"Burning"), "somebody else set it off")


func test_a_timer_spell_waits_out_its_delay() -> void:
	_mind.insight[&"Rune_Stability"] = 20
	_mind.known_runes.append(&"On_Timer")
	var spell: CompiledSpell = _bind([&"On_Timer", &"Aura", &"Apply_Water"])
	assert_gt(spell.delay_s, 0.0, "the delay survived compilation")
	var target: int = _spawn_target(ECSManager.position_of(_player_row) + Vector3(1.0, 0.0, 0.0))
	GameLoopManager.combat.resolve_cast(_player_row, spell.spell_id, Vector3.FORWARD)

	var ephemerals := EphemeralSystem.new()
	ephemerals.sampler = World.sampler()
	for _frame in 30:
		ephemerals.run(1.0 / 60.0, _rebuild_hash())
	assert_false(ECSManager.chemistries[target].has_tag(&"Wet"), "half a second in, nothing yet")

	for _frame in 200:
		ephemerals.run(1.0 / 60.0, _rebuild_hash())
	assert_true(ECSManager.chemistries[target].has_tag(&"Wet"), "the fuse ran out")


## A cone is a wedge. Something behind the caster is inside the RADIUS and outside the ANGLE, and
## that difference is the only thing separating a Cone from an Aura.
func test_a_cone_hits_what_is_in_front_and_not_what_is_behind() -> void:
	_mind.insight[&"Rune_Stability"] = 20
	_mind.known_runes.append(&"Cone")
	var spell: CompiledSpell = _bind([&"On_Cast", &"Cone", &"Apply_Burning"])
	assert_gt(spell.cone_angle_deg, 0.0, "the angle survived compilation")

	var origin: Vector3 = ECSManager.position_of(_player_row)
	var ahead: int = _spawn_target(origin + Vector3(0.0, 0.0, 3.0))
	var behind: int = _spawn_target(origin + Vector3(0.0, 0.0, -3.0))
	GameLoopManager.combat.resolve_cast(_player_row, spell.spell_id, Vector3(0.0, 0.0, 1.0))

	var ephemerals := EphemeralSystem.new()
	ephemerals.sampler = World.sampler()
	ephemerals.run(1.0 / 60.0, _rebuild_hash())
	assert_true(ECSManager.chemistries[ahead].has_tag(&"Burning"), "in the wedge")
	assert_false(
		ECSManager.chemistries[behind].has_tag(&"Burning"),
		"inside the radius, outside the angle — which is what makes it a cone"
	)


## A one-shot must not fire twice. It is retired in the same pass it detonates, and `spent` is the
## belt to that braces.
func test_a_one_shot_detonates_exactly_once() -> void:
	_mind.insight[&"Rune_Stability"] = 20
	_mind.known_runes.append(&"On_Timer")
	var spell: CompiledSpell = _bind([&"On_Timer", &"Aura", &"Apply_Water"])
	GameLoopManager.combat.resolve_cast(_player_row, spell.spell_id, Vector3.FORWARD)
	var ephemerals := EphemeralSystem.new()
	ephemerals.sampler = World.sampler()
	# SUMMED over the run. `detonations` is a per-tick counter like the rest of the ephemeral
	# observability, so reading it after the last frame would report 0 and pass vacuously against
	# a spell that went off four hundred times.
	var total: int = 0
	for _frame in 400:
		ephemerals.run(1.0 / 60.0, _rebuild_hash())
		total += ephemerals.detonations
	assert_eq(total, 1, "one fuse, one bang")
