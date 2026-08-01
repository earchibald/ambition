## The reaction matrix, the anti-recursion lock, and gas in the fluid grid (Sprint 4 §1).
##
## Every test here drives the systems by hand with the autoload clock stopped. The reaction
## system reads the SpatialHash for overlap, so a test that skips the rebuild is testing nothing:
## `_react_inter` finds no neighbours and every INTER rule silently does not fire, which looks
## exactly like a passing test of a rule that never ran.
extends GutTest

var _chunk: ChunkData


func before_each() -> void:
	GameLoopManager.set_physics_process(false)
	World.boot_scenario(World.SCENARIO_TEST_ARENA, 1)
	_chunk = World.active_chunk
	_chunk.ambient_temperature_c = 20.0


func after_all() -> void:
	GameLoopManager.set_physics_process(true)


## An entity that is a real body: chemistry to react, physical/material to carry energy, bounds
## so the SpatialHash can bin it.
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


func _tag(row: int, tag: StringName) -> void:
	ECSManager.chemistries[row].add_tag(tag)


func _run(frame: int) -> ReactionSystem:
	var system := ReactionSystem.new()
	var hash: SpatialHash = GameLoopManager.spatial_hash
	hash.rebuild(ECSManager.query(ComponentMask.SPATIAL))
	system.run(frame, _chunk, hash)
	return system


# --- The sorted-pair key (review F2) -------------------------------------------------------


func test_the_reaction_key_does_not_depend_on_tag_order() -> void:
	assert_eq(
		ReactionSystem.key_for(&"Burning", &"Water"),
		ReactionSystem.key_for(&"Water", &"Burning"),
		"A+B and B+A are the same key"
	)


func test_a_rule_is_found_from_either_side() -> void:
	var forward: Dictionary = ReactionSystem.rule_for(
		&"Burning", &"Water", ReactionSystem.SCOPE_INTER
	)
	var backward: Dictionary = ReactionSystem.rule_for(
		&"Water", &"Burning", ReactionSystem.SCOPE_INTER
	)
	assert_false(forward.is_empty(), "the quench rule exists")
	assert_eq(forward, backward, "authoring order does not change which rule is found")


## Scope is part of the identity, not a hint. Burning+Water is an INTER rule; asking for it as
## INTRA must find nothing, or a torch extinguishes itself for being near a puddle.
func test_scope_is_part_of_the_rule_identity() -> void:
	assert_true(
		ReactionSystem.rule_for(&"Burning", &"Water", ReactionSystem.SCOPE_INTRA).is_empty(),
		"the INTER quench rule is not reachable as an INTRA rule"
	)
	assert_false(
		ReactionSystem.rule_for(&"Burning", &"Wet", ReactionSystem.SCOPE_INTRA).is_empty(),
		"the self-quench rule IS an INTRA rule"
	)


# --- INTRA and INTER --------------------------------------------------------------------------


func test_a_wet_burning_thing_puts_itself_out() -> void:
	var row: int = _spawn(Vector3(4.0, 0.0, 4.0), MaterialLibrary.MAT_CLOTH, 1000.0)
	_tag(row, &"Burning")
	_tag(row, &"Wet")

	var system: ReactionSystem = _run(1)
	assert_eq(system.reactions_fired, 1, "one INTRA reaction fired")
	var chemistry: ChemistryComponent = ECSManager.chemistries[row]
	assert_false(chemistry.has_tag(&"Burning"), "the fire is out")
	assert_false(chemistry.has_tag(&"Wet"), "the water was used up doing it")


func test_a_torch_beside_a_puddle_is_extinguished() -> void:
	var torch: int = _spawn(Vector3(4.0, 0.0, 4.0), MaterialLibrary.MAT_CLOTH, 500.0)
	var puddle: int = _spawn(Vector3(4.5, 0.0, 4.0), MaterialLibrary.MAT_WATER, 1000.0)
	_tag(torch, &"Burning")
	_tag(puddle, &"Water")

	_run(1)
	assert_false(
		ECSManager.chemistries[torch].has_tag(&"Burning"), "the neighbouring water put it out"
	)


## The distance rule is real. Two reactants a room apart must not react.
func test_reactants_out_of_contact_do_not_react() -> void:
	var torch: int = _spawn(Vector3(4.0, 0.0, 4.0), MaterialLibrary.MAT_CLOTH, 500.0)
	var puddle: int = _spawn(Vector3(12.0, 0.0, 4.0), MaterialLibrary.MAT_WATER, 1000.0)
	_tag(torch, &"Burning")
	_tag(puddle, &"Water")

	var system: ReactionSystem = _run(1)
	assert_eq(system.reactions_fired, 0, "8 metres apart is not touching")
	assert_true(ECSManager.chemistries[torch].has_tag(&"Burning"), "the torch still burns")


# --- The anti-recursion lock ------------------------------------------------------------------


func test_a_reaction_locks_its_participants_out() -> void:
	var row: int = _spawn(Vector3(4.0, 0.0, 4.0), MaterialLibrary.MAT_CLOTH, 1000.0)
	_tag(row, &"Burning")
	_tag(row, &"Wet")

	_run(1)
	var chemistry: ChemistryComponent = ECSManager.chemistries[row]
	assert_true(chemistry.has_tag(ReactionSystem.COOLDOWN_TAG), "the participant is locked")
	assert_eq(
		chemistry.frames_left(ReactionSystem.COOLDOWN_TAG, 1),
		WorldConstants.REACTION_COOLDOWN_FRAMES,
		"the lock lasts exactly the specified 60 Micro frames"
	)


## THE FAILURE THIS GUARD EXISTS FOR. A reaction writes tags, and those tags are inputs to other
## rules, so without the lock the same pair re-fires every frame forever — a live-lock that eats
## the whole frame budget and never crashes, which is worse than crashing.
func test_the_same_pair_cannot_react_again_next_frame() -> void:
	var torch: int = _spawn(Vector3(4.0, 0.0, 4.0), MaterialLibrary.MAT_CLOTH, 500.0)
	var spores: int = _spawn(Vector3(4.5, 0.0, 4.0), MaterialLibrary.MAT_BIOMASS, 100.0)
	_tag(torch, &"Burning")
	_tag(spores, &"Spores")

	var first: ReactionSystem = _run(1)
	assert_eq(first.reactions_fired, 1, "it fires once")

	var second: ReactionSystem = _run(2)
	assert_eq(second.reactions_fired, 0, "and not again on the very next frame")
	assert_gt(second.cooldowns_held, 0, "because the participants are still locked")


func test_the_lock_lifts_when_it_expires() -> void:
	var row: int = _spawn(Vector3(4.0, 0.0, 4.0), MaterialLibrary.MAT_CLOTH, 1000.0)
	_tag(row, &"Burning")
	_tag(row, &"Wet")
	_run(1)

	_run(1 + WorldConstants.REACTION_COOLDOWN_FRAMES)
	assert_false(
		ECSManager.chemistries[row].has_tag(ReactionSystem.COOLDOWN_TAG),
		"a lock that never lifts is an inert entity, not a guard"
	)


## Tag expiry is stored ON the component so a recycled row cannot inherit the previous
## occupant's cooldown. A system-side dictionary keyed by row would.
func test_a_destroyed_entity_does_not_leave_its_cooldown_behind() -> void:
	var row: int = _spawn(Vector3(4.0, 0.0, 4.0), MaterialLibrary.MAT_CLOTH, 1000.0)
	_tag(row, &"Burning")
	_tag(row, &"Wet")
	_run(1)
	ECSManager.destroy_entity(ECSManager.handle_of(row))

	var reused: int = EH.index_of(ECSManager.allocate_entity())
	ECSManager.chemistries[reused] = ChemistryComponent.new()
	ECSManager.add_component_bit(reused, ComponentMask.CHEMISTRY)
	assert_false(
		ECSManager.chemistries[reused].has_tag(ReactionSystem.COOLDOWN_TAG),
		"a fresh occupant of a recycled row starts unlocked"
	)


# --- Energy, and the roadmap's success state --------------------------------------------------


## The flash-fire. Energy is DERIVED from the burning material's heat of combustion, not typed
## into the rule table, so a spore cloud and a barn do not release the same joules.
func test_burning_spores_release_their_own_combustion_energy() -> void:
	var torch: int = _spawn(Vector3(4.0, 0.0, 4.0), MaterialLibrary.MAT_CLOTH, 500.0)
	# 100 cm3 of biomass at 0.00106 kg/cm3 is 0.106 kg; at 18 MJ/kg that is ~1.9 MJ.
	var spores: int = _spawn(Vector3(4.5, 0.0, 4.0), MaterialLibrary.MAT_BIOMASS, 100.0)
	_tag(torch, &"Burning")
	_tag(spores, &"Spores")

	var system: ReactionSystem = _run(1)
	assert_almost_eq(system.energy_released_j, 1908000.0, 1000.0, "0.106 kg of biomass at 18 MJ/kg")


func test_the_flash_fire_spreads_the_fire_and_consumes_the_spores() -> void:
	var torch: int = _spawn(Vector3(4.0, 0.0, 4.0), MaterialLibrary.MAT_CLOTH, 500.0)
	var spores: int = _spawn(Vector3(4.5, 0.0, 4.0), MaterialLibrary.MAT_BIOMASS, 100.0)
	_tag(torch, &"Burning")
	_tag(spores, &"Spores")

	_run(1)
	assert_true(ECSManager.chemistries[spores].has_tag(&"Burning"), "the biomass caught")
	assert_false(ECSManager.chemistries[spores].has_tag(&"Spores"), "and stopped being spores")


## "Raises the ambient temp" is otherwise unfalsifiable, so the arithmetic is asserted. A 64x64 m
## chunk with a 3 m ceiling holds 12,288 m^3 of air at 1,206 J/(m^3*K) = 14.8 MJ per degree.
func test_a_flash_fire_raises_the_chunks_ambient_temperature() -> void:
	var before: float = _chunk.ambient_temperature_c
	var torch: int = _spawn(Vector3(4.0, 0.0, 4.0), MaterialLibrary.MAT_CLOTH, 500.0)
	var spores: int = _spawn(Vector3(4.5, 0.0, 4.0), MaterialLibrary.MAT_BIOMASS, 100.0)
	_tag(torch, &"Burning")
	_tag(spores, &"Spores")

	_run(1)
	assert_gt(_chunk.ambient_temperature_c, before, "the air got warmer")
	assert_almost_eq(
		_chunk.ambient_temperature_c - before,
		0.129,
		0.01,
		"1.9 MJ over 14.8 MJ per degree is 0.13 C — one cloud is small, a room of them is not"
	)


## A quench ABSORBS energy: boiling a kilogram of water off a fire costs 2.26 MJ. Without this
## the reaction table would be able to extinguish a fire for free.
func test_quenching_a_fire_cools_the_room() -> void:
	var before: float = _chunk.ambient_temperature_c
	var torch: int = _spawn(Vector3(4.0, 0.0, 4.0), MaterialLibrary.MAT_CLOTH, 500.0)
	var puddle: int = _spawn(Vector3(4.5, 0.0, 4.0), MaterialLibrary.MAT_WATER, 1000.0)
	_tag(torch, &"Burning")
	_tag(puddle, &"Water")

	var system: ReactionSystem = _run(1)
	assert_lt(system.energy_released_j, 0.0, "the reaction consumed energy rather than making it")
	assert_lt(_chunk.ambient_temperature_c, before, "the room cooled")


## The ambient cap. A blast big enough to exceed it must still be capped, because ambient feeds
## conduction into every entity in the chunk.
func test_the_ambient_step_is_capped() -> void:
	var torch: int = _spawn(Vector3(4.0, 0.0, 4.0), MaterialLibrary.MAT_CLOTH, 500.0)
	# 20 tonnes of biomass: 360 GJ, which uncapped would be +24,000 C.
	var pyre: int = _spawn(Vector3(4.5, 0.0, 4.0), MaterialLibrary.MAT_BIOMASS, 20000000.0)
	_tag(torch, &"Burning")
	_tag(pyre, &"Spores")

	var before: float = _chunk.ambient_temperature_c
	_run(1)
	assert_almost_eq(
		_chunk.ambient_temperature_c - before,
		WorldConstants.MAX_AMBIENT_STEP_C,
		0.001,
		"one reaction may not spike the temperature of the whole chunk without limit"
	)


# --- The kinetic half -------------------------------------------------------------------------


func test_an_explosion_pushes_bodies_outward() -> void:
	var torch: int = _spawn(Vector3(4.0, 0.0, 4.0), MaterialLibrary.MAT_CLOTH, 500.0)
	var gas: int = _spawn(Vector3(4.5, 0.0, 4.0), MaterialLibrary.MAT_SULFUR, 1000.0)
	var bystander: int = _spawn(Vector3(7.0, 0.0, 4.0), MaterialLibrary.MAT_BIOMASS, 70000.0)
	_tag(torch, &"Burning")
	_tag(gas, &"Volatile_Gas")

	_run(1)
	var pushed: Vector3 = ECSManager.velocity_of(bystander)
	assert_gt(pushed.x, 0.0, "the bystander was thrown AWAY from the blast, not toward it")


func test_a_blast_cannot_impart_an_unbounded_speed() -> void:
	var torch: int = _spawn(Vector3(4.0, 0.0, 4.0), MaterialLibrary.MAT_CLOTH, 500.0)
	var gas: int = _spawn(Vector3(4.5, 0.0, 4.0), MaterialLibrary.MAT_SULFUR, 1000.0)
	# A feather right next to the blast: impulse over a tiny mass is what needs the cap.
	var mote: int = _spawn(Vector3(4.2, 0.0, 4.0), MaterialLibrary.MAT_CLOTH, 1.0)
	_tag(torch, &"Burning")
	_tag(gas, &"Volatile_Gas")

	_run(1)
	assert_lte(
		ECSManager.velocity_of(mote).length(),
		WorldConstants.MAX_BLAST_SPEED_MPS + 0.001,
		"nothing leaves the chunk in a single frame"
	)


func test_a_consumed_reactant_is_destroyed() -> void:
	var torch: int = _spawn(Vector3(4.0, 0.0, 4.0), MaterialLibrary.MAT_CLOTH, 500.0)
	var gas: int = _spawn(Vector3(4.5, 0.0, 4.0), MaterialLibrary.MAT_SULFUR, 1000.0)
	_tag(torch, &"Burning")
	_tag(gas, &"Volatile_Gas")
	var handle: int = ECSManager.handle_of(gas)

	_run(1)
	assert_false(ECSManager.is_alive(handle), "the volatile gas was consumed by exploding")


## Row 0 is never consumed by a chemistry rule. `DeathLoopSystem` is the single owner of what
## happens to the player, and Sprint 3 already shipped one bug where another system forgot that.
func test_a_reaction_never_consumes_the_player_row() -> void:
	var player: int = WorldConstants.PLAYER_INDEX
	if not ECSManager.chemistries.has(player):
		ECSManager.chemistries[player] = ChemistryComponent.new()
		ECSManager.add_component_bit(player, ComponentMask.CHEMISTRY)
	ECSManager.chemistries[player].add_tag(&"Volatile_Gas")
	var torch: int = _spawn(ECSManager.position_of(player) + Vector3(0.4, 0.0, 0.0),
		MaterialLibrary.MAT_CLOTH, 500.0)
	_tag(torch, &"Burning")

	_run(1)
	assert_true(
		ECSManager.is_alive(ECSManager.player_handle()),
		"a chemistry rule may not delete the reserved player row"
	)


# --- Gas in the fluid grid --------------------------------------------------------------------


func test_water_is_a_liquid_at_room_temperature() -> void:
	_chunk.ambient_temperature_c = 20.0
	_chunk.add_fluid(10, 10, 400, MaterialLibrary.MAT_WATER)
	var fluids := FluidDynamicsSystem.new()
	fluids.run(_chunk)
	assert_eq(fluids.gas_cells, 0, "a puddle at 20 C is not a gas")
	assert_eq(fluids.dissipated_units, 0, "and it does not evaporate away")


## The temperature coupling. The same grid, the same material, above the boiling point.
func test_water_above_its_boiling_point_is_treated_as_gas() -> void:
	_chunk.ambient_temperature_c = 150.0
	_chunk.add_fluid(10, 10, 400, MaterialLibrary.MAT_WATER)
	var fluids := FluidDynamicsSystem.new()
	fluids.run(_chunk)
	assert_gt(fluids.gas_cells, 0, "past 100 C the puddle is steam")
	assert_gt(fluids.dissipated_units, 0, "and steam thins out")


## Gas climbs; liquid does not. This is the one behavioural difference the height term buys.
func test_gas_climbs_a_ledge_that_water_pools_below() -> void:
	_chunk.set_tile(20, 20, ChunkData.TILE_OPEN, 0.0)
	_chunk.set_tile(21, 20, ChunkData.TILE_OPEN, 1.0)

	_chunk.ambient_temperature_c = 20.0
	_chunk.add_fluid(20, 20, 400, MaterialLibrary.MAT_WATER)
	var liquid := FluidDynamicsSystem.new()
	liquid.run(_chunk)
	assert_eq(_chunk.fluid_at(21, 20), 0, "water does not flow up a 1 m step")

	_chunk.volume_map.fill(0)
	_chunk.dirty_cells.clear()
	_chunk.ambient_temperature_c = 150.0
	_chunk.add_fluid(20, 20, 400, MaterialLibrary.MAT_WATER)
	var gas := FluidDynamicsSystem.new()
	gas.run(_chunk)
	assert_gt(_chunk.fluid_at(21, 20), 0, "steam fills the volume regardless of the floor")


## The conservation property Sprint 2 asserts is about LIQUIDS, and it must still hold exactly.
## Dissipation is a deliberate, scoped break — if it ever leaks into the liquid path, every
## puddle in the world starts quietly evaporating.
func test_liquid_volume_is_still_exactly_conserved() -> void:
	_chunk.ambient_temperature_c = 20.0
	_chunk.add_fluid(30, 30, 900, MaterialLibrary.MAT_WATER)
	var before: int = _chunk.total_fluid_volume()
	var fluids := FluidDynamicsSystem.new()
	for _tick in 20:
		fluids.run(_chunk)
	assert_eq(_chunk.total_fluid_volume(), before, "not one unit of water was created or lost")


func test_a_gas_cloud_eventually_clears() -> void:
	_chunk.ambient_temperature_c = 150.0
	_chunk.add_fluid(30, 30, 600, MaterialLibrary.MAT_WATER)
	var fluids := FluidDynamicsSystem.new()
	for _tick in 200:
		fluids.run(_chunk)
	assert_eq(
		_chunk.total_fluid_volume(), 0, "a fog bank the player can never clear is not a feature"
	)


# --- Dual-scope rules ---------------------------------------------------------------------------


## THE HOLE THIS CLOSES. A fireball's `Apply_Burning` catalyst tags a spore cloud, leaving ONE
## entity carrying both `Burning` and `Spores`. An INTER-only rule never matches a pair that lives
## on a single entity, so the roadmap's own success state produced nothing at all — and every unit
## test passed, because they all arranged the tags on two neighbouring entities.
##
## Found by running the documented play route end to end, not by reading the rules.
func test_fire_spread_rules_match_both_on_one_entity_and_across_two() -> void:
	for scope in [ReactionSystem.SCOPE_INTRA, ReactionSystem.SCOPE_INTER]:
		assert_false(
			ReactionSystem.rule_for(&"Burning", &"Spores", scope).is_empty(),
			"the flash-fire rule is reachable as %s" % scope
		)
		assert_false(
			ReactionSystem.rule_for(&"Burning", &"Volatile_Gas", scope).is_empty(),
			"the explosion rule is reachable as %s" % scope
		)


func test_a_single_entity_that_is_burning_and_sporing_flashes_over() -> void:
	var cloud: int = _spawn(Vector3(4.0, 0.0, 4.0), MaterialLibrary.MAT_BIOMASS, 100.0)
	_tag(cloud, &"Spores")
	_tag(cloud, &"Burning")

	var system: ReactionSystem = _run(1)
	assert_eq(system.reactions_fired, 1, "one entity, both tags, one reaction")
	assert_false(ECSManager.chemistries[cloud].has_tag(&"Spores"), "the spores burned away")


## An INTRA reaction must release its energy too. Passing no owner map made `burns` unresolvable,
## so a self-igniting cloud warmed nothing and the ambient assertion silently held at zero.
func test_a_self_igniting_cloud_still_releases_its_combustion_energy() -> void:
	var cloud: int = _spawn(Vector3(4.0, 0.0, 4.0), MaterialLibrary.MAT_BIOMASS, 100.0)
	_tag(cloud, &"Spores")
	_tag(cloud, &"Burning")

	var before: float = _chunk.ambient_temperature_c
	var system: ReactionSystem = _run(1)
	assert_almost_eq(system.energy_released_j, 1908000.0, 1000.0, "0.106 kg of biomass at 18 MJ/kg")
	assert_gt(_chunk.ambient_temperature_c, before, "and the room got warmer for it")


## The self-quench rule stays INTRA-only. If it went dual-scope, a torch would put itself out for
## standing beside a puddle it is not touching, which is the distinction scope exists to draw.
func test_the_self_quench_rule_is_not_promoted_to_inter() -> void:
	assert_true(
		ReactionSystem.rule_for(&"Burning", &"Wet", ReactionSystem.SCOPE_INTER).is_empty(),
		"BOTH is applied per rule, not to the whole table"
	)
