## The fire model and the strain model (2026-08-01 remediation of four audit blockers).
##
## Before this pass: `Burning` was an inert permanent tag — no damage, no fuel, no burnout, no
## heat into neighbours (`conduct_pair` was fully built and never ran); heat alone could not
## ignite anything; and casting Strain charged CURRENT stamina, which nothing in the build ever
## restored, so the starting fireball was castable five times per life.
extends GutTest

var _chunk: ChunkData


func before_each() -> void:
	GameLoopManager.set_physics_process(false)
	World.boot_scenario(World.SCENARIO_TEST_ARENA, 1)
	_chunk = World.active_chunk
	_chunk.ambient_temperature_c = 20.0


func after_all() -> void:
	GameLoopManager.set_physics_process(true)


func _spawn(at: Vector3, material_id: StringName, volume_cm3: float) -> int:
	var handle: int = ECSManager.allocate_entity()
	var row: int = EH.index_of(handle)
	ECSManager.set_position(row, at)
	ECSManager.add_component_bit(row, ComponentMask.POSITION)
	var bounds := BoundsComponent.new()
	bounds.half_extents = Vector3(0.3, 0.3, 0.3)
	ECSManager.bounds[row] = bounds
	ECSManager.add_component_bit(row, ComponentMask.BOUNDS)
	var physical := PhysicalPropertyComponent.new()
	physical.volume_cm3 = volume_cm3
	var composition := MaterialCompositionComponent.new({material_id: 1.0})
	MaterialLibrary.recompute_mass(physical, composition)
	physical.set_temperature_c(20.0)
	ECSManager.physicals[row] = physical
	ECSManager.materials[row] = composition
	ECSManager.add_component_bit(row, ComponentMask.PHYSICAL | ComponentMask.MATERIAL)
	ECSManager.chemistries[row] = ChemistryComponent.new()
	ECSManager.add_component_bit(row, ComponentMask.CHEMISTRY)
	return row


func _with_body(row: int, health: float = 100.0) -> BodyComponent:
	var body := BodyComponent.new()
	body.max_health = health
	body.health = health
	ECSManager.bodies[row] = body
	ECSManager.add_component_bit(row, ComponentMask.BODY)
	return body


func _run_frames(system: ReactionSystem, from_frame: int, count: int) -> void:
	var hash: SpatialHash = GameLoopManager.spatial_hash
	hash.rebuild(ECSManager.query(ComponentMask.SPATIAL))
	for frame in range(from_frame, from_frame + count):
		system.run(frame, _chunk, hash, GameLoopManager.combat)


# --- Burning is a process now -------------------------------------------------------------------

func test_a_burning_creature_takes_damage_over_time() -> void:
	var goblin: int = _spawn(Vector3(4.0, 0.0, 4.0), MaterialLibrary.MAT_BIOMASS, 66000.0)
	var body: BodyComponent = _with_body(goblin)
	ECSManager.chemistries[goblin].add_tag(&"Burning")
	_run_frames(ReactionSystem.new(), 1, 60)
	assert_almost_eq(
		body.health, 100.0 - ReactionSystem.BURN_DPS, 0.1,
		"one second alight costs BURN_DPS health — the roadmap's [Burning] tag DOES something"
	)


func test_a_stone_statue_does_not_burn_down() -> void:
	var statue: int = _spawn(Vector3(4.0, 0.0, 4.0), MaterialLibrary.MAT_STONE, 66000.0)
	var body: BodyComponent = _with_body(statue)
	ECSManager.chemistries[statue].add_tag(&"Burning")
	_run_frames(ReactionSystem.new(), 1, 60)
	assert_almost_eq(body.health, 100.0, 0.001, "nothing combustible, nothing charred")


func test_burning_to_death_leaves_a_corpse() -> void:
	var goblin: int = _spawn(Vector3(4.0, 0.0, 4.0), MaterialLibrary.MAT_BIOMASS, 66000.0)
	_with_body(goblin, 0.5)
	ECSManager.chemistries[goblin].add_tag(&"Burning")
	var system := ReactionSystem.new()
	_run_frames(system, 1, 30)
	assert_eq(system.burn_deaths, 1, "half a health point does not survive a fire")
	assert_true(
		ECSManager.chemistries[goblin].has_tag(&"Corpse"),
		"and the death routed through the one corpse path"
	)


func test_fire_heats_what_it_touches() -> void:
	var brazier: int = _spawn(Vector3(4.0, 0.0, 4.0), MaterialLibrary.MAT_STONE, 4000.0)
	var kettle: int = _spawn(Vector3(4.5, 0.0, 4.0), MaterialLibrary.MAT_IRON, 500.0)
	ECSManager.physicals[brazier].set_temperature_c(600.0)
	ECSManager.chemistries[brazier].add_tag(&"Burning")
	var before: float = ECSManager.physicals[kettle].temperature_c()
	_run_frames(ReactionSystem.new(), 1, 60)
	assert_gt(
		ECSManager.physicals[kettle].temperature_c(), before,
		"conduct_pair finally has a production caller: fire warms the kettle beside it"
	)


func test_result_tags_lapse() -> void:
	var survivor: int = _spawn(Vector3(4.0, 0.0, 4.0), MaterialLibrary.MAT_STONE, 66000.0)
	var chemistry: ChemistryComponent = ECSManager.chemistries[survivor]
	chemistry.add_tag(&"Explosion", 1 + int(ReactionSystem.RESULT_TAG_LIFETIME_FRAMES[&"Explosion"]))
	_run_frames(ReactionSystem.new(), 1, 1)
	assert_true(chemistry.has_tag(&"Explosion"), "fresh, it holds")
	_run_frames(
		ReactionSystem.new(), 2 + int(ReactionSystem.RESULT_TAG_LIFETIME_FRAMES[&"Explosion"]), 1
	)
	assert_false(
		chemistry.has_tag(&"Explosion"),
		"an EVENT tag that never lapsed made every blast survivor 'exploding' forever"
	)


# --- Fuel and ignition --------------------------------------------------------------------------

func test_a_brazier_burns_down_when_its_fuel_is_spent() -> void:
	var brazier: int = World.spawn_brazier(Vector3(4.0, 0.5, 4.0))
	var row: int = EH.index_of(brazier)
	var source: HeatSourceComponent = ECSManager.heat_sources[row]
	source.stored_energy = source.output_j_per_tick * 10.0
	var system := ReactionSystem.new()
	_run_frames(system, 1, 12)
	assert_false(source.is_lit(), "the fuel is gone")
	assert_false(
		ECSManager.chemistries[row].has_tag(&"Burning"),
		"and the flame went with it — a brazier no longer burns forever for free"
	)
	assert_eq(system.sources_exhausted, 1)


func test_hot_enough_is_alight_with_no_spell_involved() -> void:
	var woodpile: int = _spawn(Vector3(4.0, 0.0, 4.0), MaterialLibrary.MAT_BIOMASS, 66000.0)
	ECSManager.physicals[woodpile].set_temperature_c(300.0)
	var system := ReactionSystem.new()
	_run_frames(system, 1, 1)
	assert_true(
		ECSManager.chemistries[woodpile].has_tag(&"Burning"),
		"280 C biomass ignites — declared gap G-7, the ignition-temperature model"
	)
	assert_eq(system.ignitions, 1)


func test_wet_things_do_not_autoignite() -> void:
	var soaked: int = _spawn(Vector3(4.0, 0.0, 4.0), MaterialLibrary.MAT_BIOMASS, 66000.0)
	ECSManager.physicals[soaked].set_temperature_c(300.0)
	ECSManager.chemistries[soaked].add_tag(&"Wet")
	var system := ReactionSystem.new()
	_run_frames(system, 1, 1)
	assert_eq(system.ignitions, 0, "soaked wood steams; it does not catch")


func test_cold_stone_does_not_ignite() -> void:
	var statue: int = _spawn(Vector3(4.0, 0.0, 4.0), MaterialLibrary.MAT_STONE, 66000.0)
	ECSManager.physicals[statue].set_temperature_c(500.0)
	var system := ReactionSystem.new()
	_run_frames(system, 1, 1)
	assert_eq(system.ignitions, 0, "stone has no ignition point at any temperature")


# --- The water spell finally works --------------------------------------------------------------

func test_the_starting_water_spell_puts_out_a_fire_it_hits() -> void:
	var campfire: int = _spawn(Vector3(4.0, 0.0, 4.0), MaterialLibrary.MAT_CLOTH, 500.0)
	var chemistry: ChemistryComponent = ECSManager.chemistries[campfire]
	chemistry.add_tag(&"Burning")
	# What EphemeralSystem applies when an Apply_Water payload lands: the rune's tag, on the
	# TARGET. Both tags on ONE entity — the single-entity case the INTER-only rule never matched.
	chemistry.add_tag(RuneLibrary.RUNES[&"Apply_Water"]["params"]["apply_tag"])
	_run_frames(ReactionSystem.new(), 1, 1)
	assert_false(
		chemistry.has_tag(&"Burning"),
		"douse the fire, the obvious case for the starting spell, works"
	)


# --- Strain (magic doc §2, as specified) --------------------------------------------------------

func test_strain_dents_the_ceiling_not_the_tank() -> void:
	var body: BodyComponent = ECSManager.bodies[WorldConstants.PLAYER_INDEX]
	body.strain = 30.0
	assert_almost_eq(
		body.effective_max_stamina(), body.max_stamina - 30.0, 0.001,
		"strain is temporary damage to Max_Stamina, the quantity the magic doc names"
	)


func test_standing_still_recovers_stamina_and_strain() -> void:
	var body: BodyComponent = ECSManager.bodies[WorldConstants.PLAYER_INDEX]
	body.strain = 20.0
	body.stamina = 10.0
	ECSManager.set_velocity(WorldConstants.PLAYER_INDEX, Vector3.ZERO)
	var metabolism := MetabolismSystem.new()
	for _tick in 20:
		metabolism.run(_chunk)
	assert_gt(body.stamina, 10.0, "rest refills stamina — nothing in the build did, for anyone")
	assert_lt(body.strain, 20.0, "and heals strain, which is what makes casting sustainable")


func test_walking_does_not_recover() -> void:
	var body: BodyComponent = ECSManager.bodies[WorldConstants.PLAYER_INDEX]
	body.strain = 20.0
	ECSManager.set_velocity(WorldConstants.PLAYER_INDEX, Vector3(4.0, 0.0, 0.0))
	var metabolism := MetabolismSystem.new()
	for _tick in 5:
		metabolism.run(_chunk)
	assert_almost_eq(body.strain, 20.0, 0.001, "recovery is a rest activity, not a walk")


func test_a_fully_strained_caster_is_refused_until_rest() -> void:
	var body: BodyComponent = ECSManager.bodies[WorldConstants.PLAYER_INDEX]
	body.strain = body.max_stamina
	var watcher: Array = []
	var recorder: Callable = func(_a: int, _b: StringName, reason: StringName) -> void:
		watcher.append(reason)
	ECSEvents.action_rejected.connect(recorder)
	var mind: MindComponent = ECSManager.minds[WorldConstants.PLAYER_INDEX]
	mind.grimoire[&"test_bolt"] = _tiny_spell()
	assert_false(
		GameLoopManager.combat.resolve_cast(
			WorldConstants.PLAYER_INDEX, &"test_bolt", Vector3.FORWARD
		)
	)
	ECSEvents.action_rejected.disconnect(recorder)
	assert_has(watcher, &"too strained — rest first", "and the refusal says why")


func _tiny_spell() -> CompiledSpell:
	var spell := CompiledSpell.new()
	spell.spell_id = &"test_bolt"
	spell.strain_cost = 5.0
	spell.shape = RuneLibrary.SHAPE_SELF
	return spell
