## The Grimoire panel and the route from a key press to a spell in the world.
##
## THE POINT OF THIS FILE. Every system in this build that shipped broken shipped with green
## tests of the system and no test of the ROUTE IN — `resolve_fall` had no caller, `select_row`
## had no caller, `on_timeout` had no caller. `test_spellcraft.gd` proves the compiler and the
## cast path work when called directly, which is exactly the shape of proof that has been wrong
## before. These tests start where the player starts.
extends GutTest

var _player_row: int
var _panel: GrimoirePanel


func before_each() -> void:
	GameLoopManager.set_physics_process(false)
	World.boot_scenario(World.SCENARIO_TEST_ARENA, 1)
	_player_row = ECSManager.resolve(ECSManager.player_handle())
	_panel = GrimoirePanel.new()
	add_child_autofree(_panel)


func after_all() -> void:
	GameLoopManager.set_physics_process(true)


## Drains the intent queue the way the Micro tick does, so a pushed intent actually resolves.
func _pump_intents() -> void:
	for intent in ECSManager.take_intents(_player_row):
		match intent.type:
			ActionIntent.BIND:
				GameLoopManager.spells.bind(_player_row, intent.name_list)
			ActionIntent.CAST:
				GameLoopManager.combat.resolve_cast(
					_player_row, intent.name_data, intent.vector_data
				)


func _press(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	_panel._unhandled_input(event)


func _open_and_select_a_fireball() -> void:
	_panel._open = true
	# The list is the player's known runes, sorted. Selected by NAME rather than by index, so a
	# change to the starting grimoire cannot silently make this test bind something else.
	for rune_id in [&"On_Cast", &"On_Impact", &"Projectile", &"Add_Temperature", &"Apply_Burning"]:
		_panel._toggle(_panel._known().find(rune_id))


# --- The input map ------------------------------------------------------------------------------


func test_the_grimoire_and_cast_keys_are_mapped() -> void:
	assert_true(InputMap.has_action(&"grimoire"), "B opens the Grimoire")
	assert_true(InputMap.has_action(&"cast"), "Q casts")


# --- The panel ----------------------------------------------------------------------------------


func test_the_panel_starts_closed() -> void:
	assert_false(_panel.is_open(), "the Grimoire does not obstruct the view until asked for")


func test_a_number_key_adds_a_rune_and_pressing_it_again_removes_it() -> void:
	_panel._open = true
	_press(KEY_1)
	assert_eq(_panel._selected.size(), 1, "one rune selected")
	_press(KEY_1)
	assert_eq(_panel._selected.size(), 0, "the same key takes it back off — never a duplicate")


func test_backspace_clears_the_whole_selection() -> void:
	_open_and_select_a_fireball()
	_press(KEY_BACKSPACE)
	assert_eq(_panel._selected.size(), 0, "an ordering mistake is cheap to undo")


func test_a_number_beyond_the_list_does_nothing() -> void:
	_panel._open = true
	_press(KEY_9)
	assert_lte(_panel._selected.size(), 1, "a key past the end of the list is not an error")


## THE DRY RUN. The preview is the pure compiler, so what the panel shows is what a Bind would
## produce — including a refusal, before the player commits to it.
func test_the_preview_reports_a_refusal_before_you_bind() -> void:
	_panel._open = true
	_panel._toggle(_panel._known().find(&"Projectile"))
	var text: String = "\n".join(_panel._compose())
	assert_true(
		text.contains("will not compile"),
		"a shape with no trigger is refused in the preview, not on the Bind"
	)


func test_the_preview_costs_nothing() -> void:
	var body: BodyComponent = ECSManager.bodies[_player_row]
	var stamina: float = body.stamina
	var mind: MindComponent = ECSManager.minds[_player_row]
	_open_and_select_a_fireball()
	assert_true(
		"\n".join(_panel._compose()).contains("strain"), "the preview really did compile something"
	)
	assert_almost_eq(body.stamina, stamina, 0.001, "a Dry Run costs zero Strain")
	assert_true(mind.grimoire.is_empty(), "and binds nothing")


func test_the_preview_warns_when_a_cap_would_fire() -> void:
	var mind: MindComponent = ECSManager.minds[_player_row]
	mind.insight[&"Rune_Stability"] = 40
	mind.known_runes.append(&"Great_Aura")
	_panel._open = true
	for rune_id in [&"On_Cast", &"Great_Aura", &"Add_Temperature"]:
		_panel._toggle(_panel._known().find(rune_id))
	assert_true(
		"\n".join(_panel._compose()).contains("capped"),
		"the player is told the engine changed their spell, rather than silently handed another"
	)


# --- Binding goes through the ECS, not around it ------------------------------------------------


## The panel is a listener that sends requests. It must not write a CompiledSpell into a
## MindComponent itself (Prime Directive).
func test_pressing_bind_pushes_an_intent_rather_than_writing_state() -> void:
	_open_and_select_a_fireball()
	_press(KEY_ENTER)
	assert_true(
		ECSManager.minds[_player_row].grimoire.is_empty(),
		"nothing is bound until the ECS runs the intent"
	)
	assert_eq(
		ECSManager.action_queues.get(_player_row, []).size(), 1, "a BIND intent is queued"
	)


func test_the_full_bind_route_registers_a_castable_spell() -> void:
	_open_and_select_a_fireball()
	_press(KEY_ENTER)
	_pump_intents()
	var mind: MindComponent = ECSManager.minds[_player_row]
	assert_eq(mind.grimoire.size(), 1, "the spell was compiled and registered")
	assert_ne(mind.active_spell, &"", "and is what the cast key will fire")


func test_a_refused_bind_is_reported_to_the_panel() -> void:
	_panel._open = true
	_panel._toggle(_panel._known().find(&"Projectile"))
	_press(KEY_ENTER)
	_pump_intents()
	assert_true(
		"\n".join(_panel._compose()).contains("refused"),
		"a Bind button that fails silently is the same defect as a silent cast"
	)


# --- The cast key -------------------------------------------------------------------------------


## The whole route: open, select, bind, aim, cast, and something exists in the world.
func test_press_bind_then_cast_and_a_spell_enters_the_world() -> void:
	_open_and_select_a_fireball()
	_press(KEY_ENTER)
	_pump_intents()

	var bridge := PlayerInputBridge.new()
	add_child_autofree(bridge)
	bridge._push_cast(_player_row, Vector3(0.0, 0.0, 1.0))
	_pump_intents()
	assert_eq(
		ECSManager.query(ComponentMask.EPHEMERAL).size(),
		1,
		"the key press became an entity in the world"
	)


func test_casting_with_nothing_bound_says_where_to_bind_one() -> void:
	var reasons: Array[String] = []
	ECSEvents.action_rejected.connect(
		func(_a: int, _action: StringName, reason: StringName) -> void:
			reasons.append(String(reason))
	)
	var bridge := PlayerInputBridge.new()
	add_child_autofree(bridge)
	bridge._push_cast(_player_row, Vector3.FORWARD)
	assert_eq(reasons.size(), 1, "the refusal is announced")
	assert_true(String(reasons[0]).contains("B"), "and names the key that fixes it")


## The cast key reads the bound id from the MIND, so the viewer holds no magic state of its own
## and a bind is castable on the very next frame.
func test_the_cast_key_holds_no_state_of_its_own() -> void:
	_open_and_select_a_fireball()
	_press(KEY_ENTER)
	_pump_intents()

	# A DIFFERENT bridge instance, which has never seen the bind.
	var fresh := PlayerInputBridge.new()
	add_child_autofree(fresh)
	fresh._push_cast(_player_row, Vector3.FORWARD)
	assert_eq(
		ECSManager.action_queues.get(_player_row, []).size(),
		1,
		"a bridge that never saw the bind still knows what to cast"
	)


# --- The play-tester's route, end to end -------------------------------------------------------


## EXACTLY WHAT RUNNING.md TELLS A PLAY-TESTER TO DO. Boot the arena, bind a fireball, shoot the
## spore cloud, and watch the flash-fire. If this test goes red, the instructions in RUNNING.md
## are wrong, which is a defect in its own right — the file is a contract.
func test_the_documented_flash_fire_demo_actually_works() -> void:
	var spore_row: int = EH.index_of(
		World.spawn_reactant(
			ECSManager.position_of(_player_row) + Vector3(0.0, 0.0, 8.0),
			MaterialLibrary.MAT_BIOMASS,
			100.0,
			&"Spores"
		)
	)
	_open_and_select_a_fireball()
	_press(KEY_ENTER)
	_pump_intents()

	var bridge := PlayerInputBridge.new()
	add_child_autofree(bridge)
	bridge._push_cast(_player_row, Vector3(0.0, 0.0, 1.0))
	_pump_intents()

	var ephemerals := EphemeralSystem.new()
	ephemerals.sampler = World.sampler()
	var reactions := ReactionSystem.new()
	var before_air: float = World.active_chunk.ambient_temperature_c
	var burned: bool = false
	for frame in 120:
		var hash: SpatialHash = GameLoopManager.spatial_hash
		hash.rebuild(ECSManager.query(ComponentMask.SPATIAL))
		ephemerals.run(1.0 / 60.0, hash)
		reactions.run(frame, World.active_chunk, hash)
		var chemistry: ChemistryComponent = ECSManager.chemistries.get(spore_row)
		if chemistry != null and chemistry.has_tag(&"Burning"):
			burned = true
			break
	assert_true(burned, "the fireball reached the spores and set them alight")
	assert_gt(
		World.active_chunk.ambient_temperature_c,
		before_air,
		"and the burning biomass warmed the room, which is the roadmap's success state"
	)


## The other documented target. Same route, different reactant, visibly different outcome — which
## is the point of having a reaction MATRIX rather than one hardcoded effect.
func test_the_documented_explosion_demo_throws_a_bystander() -> void:
	var origin: Vector3 = ECSManager.position_of(_player_row)
	World.spawn_reactant(
		origin + Vector3(0.0, 0.0, 8.0), MaterialLibrary.MAT_SULFUR, 1000.0, &"Volatile_Gas"
	)
	var bystander: int = EH.index_of(
		World.spawn_creature(origin + Vector3(2.0, 0.0, 8.0), &"SPC_CORPSE_RAT")
	)
	_open_and_select_a_fireball()
	_press(KEY_ENTER)
	_pump_intents()

	var bridge := PlayerInputBridge.new()
	add_child_autofree(bridge)
	bridge._push_cast(_player_row, Vector3(0.0, 0.0, 1.0))
	_pump_intents()

	var ephemerals := EphemeralSystem.new()
	ephemerals.sampler = World.sampler()
	var reactions := ReactionSystem.new()
	var thrown: bool = false
	for frame in 120:
		var hash: SpatialHash = GameLoopManager.spatial_hash
		hash.rebuild(ECSManager.query(ComponentMask.SPATIAL))
		ephemerals.run(1.0 / 60.0, hash)
		reactions.run(frame, World.active_chunk, hash)
		if ECSManager.velocity_of(bystander).length() > 1.0:
			thrown = true
			break
	assert_true(thrown, "the blast threw the bystander rather than only recolouring a tag")


## The brazier exists so `Absorb_Heat` has something to draw on. If it ships without stored
## energy, the rune fizzles every time and reads as broken.
func test_the_arena_brazier_has_heat_to_absorb() -> void:
	var row: int = EH.index_of(
		World.spawn_brazier(ECSManager.position_of(_player_row) + Vector3(-4.0, 0.0, 4.0))
	)
	var source: HeatSourceComponent = ECSManager.heat_sources.get(row)
	assert_not_null(source, "the brazier is a heat source")
	assert_gt(
		source.stored_energy,
		RuneLibrary.params_of(&"Absorb_Heat")["absorb_j"],
		"and holds more than one Absorb_Heat draw, or the rune can never succeed"
	)
	assert_true(ECSManager.chemistries[row].has_tag(&"Burning"), "and it is actually alight")


## The hazard key. Mutation has no naturally-occurring source in either scenario, so `H` is the
## only route to the ecology loop — and a debug key with no effect is worse than none.
func test_the_hazard_key_makes_the_chunk_hazardous_and_back() -> void:
	var bridge := PlayerInputBridge.new()
	add_child_autofree(bridge)
	World.active_chunk.hazard_tags.clear()

	bridge._debug_toggle_hazard()
	assert_true(World.active_chunk.hazard_tags.has(&"Spores"), "H fills the chunk with spores")

	var system := MutationSystem.new()
	system.run(0.5, World.active_chunk)
	assert_gt(
		float(ECSManager.bodies[_player_row].exposure.get(&"FUNGAL", 0.0)),
		0.0,
		"and standing in it actually exposes you"
	)

	bridge._debug_toggle_hazard()
	assert_false(World.active_chunk.hazard_tags.has(&"Spores"), "pressing it again clears the air")
