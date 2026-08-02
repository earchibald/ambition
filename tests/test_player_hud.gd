## The player HUD, the pack, and the theme they are built from.
##
## Composition is tested through the same static, row-only functions the panels render — the
## HoverCard pattern — so a headless run asserts the words without a viewport. The theme test
## asserts the CONTRAST MATHS the palette's accessibility claims rest on: a palette that
## quietly drifts below WCAG AA should fail CI, not a play-tester's eyes.
extends GutTest

## The brightest world pixel a panel plausibly floats over: fire. The palette's worst case.
const FIRE_PIXEL := Color(0.910, 0.627, 0.314)

var _player_row: int


func before_each() -> void:
	GameLoopManager.set_physics_process(false)
	World.boot_scenario(World.SCENARIO_TEST_ARENA, 1)
	_player_row = ECSManager.resolve(ECSManager.player_handle())


func after_all() -> void:
	GameLoopManager.set_physics_process(true)


## BBCode stripped, so assertions read what a player reads. Colour codes legitimately contain
## `#` and brackets; the visible text is the surface under test.
func _visible(text: String) -> String:
	var regex := RegEx.new()
	regex.compile("\\[[^\\]]*\\]")
	return regex.sub(text, "", true)


# --- The theme's promises -----------------------------------------------------------------------


func test_text_tiers_pass_wcag_aa_over_the_brightest_world_pixel() -> void:
	var worst: Color = UITheme.composited_panel_over(FIRE_PIXEL)
	for tier in [
		["primary", UITheme.TEXT_PRIMARY, 7.0],
		["body", UITheme.TEXT_BODY, 7.0],
		["muted", UITheme.TEXT_MUTED, 4.5],
	]:
		var ratio: float = UITheme.contrast_ratio(Color("#" + String(tier[1])), worst)
		assert_gt(
			ratio, float(tier[2]),
			"%s text keeps >= %.1f:1 on the worst-case panel (got %.1f:1)"
			% [tier[0], tier[2], ratio]
		)


## The log panel is dimmer than the standard panel, so it gets its own assertion — a guarantee
## that only covers the surfaces it was computed for is how accessibility rots quietly.
func test_log_event_colours_pass_aa_over_the_dimmer_log_panel() -> void:
	var worst: Color = UITheme.composited_panel_over(FIRE_PIXEL, UITheme.LOG_BG_ALPHA)
	for tier in [UITheme.DANGER, UITheme.WARNING, UITheme.GOOD, UITheme.TEXT_BODY]:
		var ratio: float = UITheme.contrast_ratio(Color("#" + String(tier)), worst)
		assert_gt(
			ratio, 4.5,
			"log colour %s keeps AA on the dimmer log panel (got %.2f:1)" % [tier, ratio]
		)


func test_vital_fills_are_distinguishable_and_non_text_compliant() -> void:
	var worst: Color = UITheme.composited_panel_over(FIRE_PIXEL)
	for fill in [UITheme.HEALTH, UITheme.STAMINA]:
		assert_gt(
			UITheme.contrast_ratio(Color("#" + String(fill)), worst), 3.0,
			"bar fill %s clears the WCAG 1.4.11 non-text floor" % fill
		)
	# Red vs teal must differ in LUMINANCE, not just hue — hue alone dies with colourblindness.
	var health_l: float = UITheme.contrast_ratio(Color("#" + UITheme.HEALTH), Color.BLACK)
	var stamina_l: float = UITheme.contrast_ratio(Color("#" + UITheme.STAMINA), Color.BLACK)
	assert_gt(
		absf(health_l - stamina_l), 1.0,
		"health and stamina differ by luminance as well as hue"
	)


# --- The vital bar's geometry -------------------------------------------------------------------


func test_fill_is_proportional_and_clamped() -> void:
	assert_almost_eq(VitalBar.fill_px(50.0, 100.0, 280.0), 140.0, 0.01, "half is half")
	assert_eq(VitalBar.fill_px(-5.0, 100.0, 280.0), 0.0, "damage cannot underflow the well")
	assert_eq(VitalBar.fill_px(150.0, 100.0, 280.0), 280.0, "overheal cannot overflow it")
	assert_eq(VitalBar.fill_px(50.0, 0.0, 280.0), 0.0, "a zero maximum draws nothing")


func test_ticks_mark_every_25_units_excluding_endpoints() -> void:
	var ticks: Array[float] = VitalBar.tick_fractions(100.0)
	assert_eq(ticks.size(), 3, "100 max: ticks at 25, 50, 75 — never at 0 or 100")
	assert_almost_eq(ticks[1], 0.5, 0.001, "the middle tick sits at half")
	assert_eq(VitalBar.tick_fractions(0.0).size(), 0, "no maximum, no ticks")


func test_ghost_drains_toward_the_value_and_never_past_it() -> void:
	# A full-bar loss takes GHOST_DRAIN_S to cross the whole bar.
	var ghost: float = VitalBar.ghost_step(100.0, 0.0, 100.0, VitalBar.GHOST_DRAIN_S / 2.0)
	assert_almost_eq(ghost, 50.0, 0.01, "half the drain time crosses half the bar")
	assert_eq(
		VitalBar.ghost_step(51.0, 50.0, 100.0, 10.0), 50.0,
		"a long frame stops AT the value, not below it"
	)


# --- What the HUD says --------------------------------------------------------------------------


func test_the_cast_slot_names_the_bound_spell_in_player_words() -> void:
	assert_eq(
		PlayerHUD.bound_spell_label(_player_row), "nothing bound",
		"an empty slot names its state"
	)
	GameLoopManager.spells.bind(
		_player_row,
		[&"On_Cast", &"On_Impact", &"Projectile", &"Add_Temperature", &"Apply_Burning"]
	)
	var label: String = PlayerHUD.bound_spell_label(_player_row)
	assert_eq(label, "Fire bolt", "the fireball is called a fire bolt, not a rune list")
	assert_false(label.contains("+"), "the + joined id never reaches the player")


func test_spell_names_cover_payloads_shapes_and_instability() -> void:
	var spell := CompiledSpell.new()
	spell.shape = RuneLibrary.SHAPE_PROJECTILE
	spell.applies_tags = [&"Wet"] as Array[StringName]
	assert_eq(EntityCard.spell_name(spell), "Water bolt", "the water spell is water")
	spell.applies_tags = [] as Array[StringName]
	spell.energy_j = -400000.0
	spell.shape = RuneLibrary.SHAPE_CONE
	assert_eq(EntityCard.spell_name(spell), "Chilling wave", "pure cold reads as chilling")
	spell.unstable = true
	assert_string_contains(
		EntityCard.spell_name(spell), "Unstable", "an overclocked spell wears its brand"
	)


func test_load_text_stays_quiet_until_encumbrance_bites() -> void:
	assert_eq(PlayerHUD.load_text(3.2, 30.0, 1.0), "3.2 / 30 kg", "a light load is not news")
	assert_string_contains(
		PlayerHUD.load_text(28.0, 30.0, 0.9), "laden", "a heavy one is"
	)
	assert_string_contains(
		PlayerHUD.load_text(60.0, 30.0, 0.5), "overburdened", "and a crushing one says so"
	)


func test_conditions_include_the_cards_words_plus_encumbrance() -> void:
	assert_eq(PlayerHUD.condition_text(_player_row), "", "a healthy unburdened player: silence")
	ECSManager.needs[_player_row].hunger = 90.0
	assert_string_contains(
		PlayerHUD.condition_text(_player_row), "starving",
		"the HUD speaks the same words as the hover card"
	)


func test_the_feed_aggregates_spam_into_one_line() -> void:
	assert_eq(PlayerHUD.feed_display("you take 5 damage", 1), "you take 5 damage")
	assert_eq(
		PlayerHUD.feed_display("you take 5 damage", 10), "you take 5 damage (x10)",
		"ten identical events are one line saying so — the HUD spec's aggregator"
	)


func test_floors_are_named_for_people() -> void:
	assert_eq(PlayerHUD.floor_word(0), "the surface")
	assert_eq(PlayerHUD.floor_word(-2), "floor -2")


## The route in, not just the composition: signals reach the log and player-irrelevant ones
## do not. The HUD is instantiated headless — CanvasLayer needs no viewport to compose text.
func test_the_log_hears_the_player_and_ignores_strangers() -> void:
	var hud := PlayerHUD.new()
	add_child_autofree(hud)
	var player: int = ECSManager.player_handle()
	ECSEvents.action_rejected.emit(player, &"attack", &"nothing in reach")
	ECSEvents.action_rejected.emit(player, &"attack", &"nothing in reach")
	var rat: int = World.spawn_creature(
		ECSManager.position_of(_player_row) + Vector3(2.0, 0.0, 0.0)
	)
	ECSEvents.action_rejected.emit(rat, &"attack", &"nothing in reach")
	var text: String = _visible(hud._log.text)
	assert_string_contains(text, "nothing in reach (x2)", "the repeat collapsed to one line")
	assert_eq(
		text.count("nothing in reach"), 1,
		"the rat's refusal is the machine's business, not the player's log"
	)


func test_the_log_reports_a_pickup_by_name_even_after_the_merge_destroys_it() -> void:
	var hud := PlayerHUD.new()
	add_child_autofree(hud)
	var item: int = World.spawn_item(
		ECSManager.position_of(_player_row) + Vector3(1.0, 0.0, 0.0),
		MaterialLibrary.MAT_COPPER, 112.0, 5
	)
	# Seen once while alive (any surface naming it does this), then destroyed — the merge case.
	EntityCard.title_or_last(item)
	ECSManager.destroy_entity(item)
	ECSManager.flush_structural_changes()
	ECSEvents.item_taken.emit(ECSManager.player_handle(), item, &"take")
	assert_string_contains(
		_visible(hud._log.text), "taken: 5 Copper",
		"the last known name answers for the destroyed stack"
	)


# --- What the pack says -------------------------------------------------------------------------


func test_an_empty_pack_teaches_the_take_key() -> void:
	var text: String = _visible("\n".join(PackPanel.compose(_player_row)))
	assert_string_contains(text, "nothing — E takes", "empty is a state, not a blank")
	assert_string_contains(text, "Dropping is not built yet", "the limit is on its face")


func test_the_pack_lists_held_stacks_by_name_with_mass_and_volume() -> void:
	var item: int = World.spawn_item(
		ECSManager.position_of(_player_row) + Vector3(1.0, 0.0, 0.0),
		MaterialLibrary.MAT_COPPER, 112.0, 5
	)
	GameLoopManager.inventory.try_insert(_player_row, item)
	var text: String = _visible("\n".join(PackPanel.compose(_player_row)))
	assert_string_contains(text, "5 Copper", "the stack is named in the player's words")
	assert_false(text.contains("MAT_"), "no storage prefix reaches the pack")
	assert_string_contains(text, "kg", "mass is shown — it is what slows you")
	assert_string_contains(text, "L", "volume is shown — it is what fills the pack")


func test_the_pack_panel_opens_on_i_and_yields_the_mouse() -> void:
	var pack := PackPanel.new()
	add_child_autofree(pack)
	assert_false(pack.is_open(), "closed at boot")
	var press := InputEventAction.new()
	press.action = &"inventory"
	press.pressed = true
	pack._unhandled_input(press)
	assert_true(pack.is_open(), "I opens it")
	pack._unhandled_input(press)
	assert_false(pack.is_open(), "I again closes it")
