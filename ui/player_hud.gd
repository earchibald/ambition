## The player's always-on layer: vitals, the running log, the keybar, the load, the clock.
##
## THIS IS THE LAYER THE DEBUG OVERLAY WAS STANDING IN FOR. Until now, hiding the debug panel
## meant playing with no health bar, no stamina, no event feedback and no clock — every
## player-facing fact lived inside a developer tool, which is why the debug info "drowned": it
## could not be dismissed, because it was also the HUD. This file is the player's readout; the
## overlay goes back to being a diagnostic.
##
## LAYOUT is the HUD spec's default (`hud_and_main_interface_architecture.md` §2): vitals
## top-left with ghost bars, the running log bottom-left, the keybar bottom-center where the
## Quick-Belt will grow, the load bottom-right where the paper-doll will, the clock top-right.
##
## IT NEVER EATS INPUT. Every Control is `MOUSE_FILTER_IGNORE`. It reads the ECS and listens to
## ECSEvents; it never writes state (Prime Directive).
##
## ONE NAMING TRUTH: everything printed here goes through `EntityCard`, the same words the hover
## card and the debug feed use. TWO FEEDS, ONE LAW: this log shows what happened to YOU and near
## you, spam-aggregated per the HUD spec; the debug feed keeps the machine's full firehose.
class_name PlayerHUD
extends CanvasLayer

## Seconds between pulls of slow-moving state (vitals, load, clock). Event lines arrive by
## signal, not by poll. Bars animate their ghosts per-frame internally.
const REFRESH_INTERVAL_S: float = 0.25

## Log lines kept. The HUD spec asks for "the last 6-8 actions"; six keeps the corner quiet.
const FEED_CAPACITY: int = 6

## After this long, a log line trades its event colour for the muted tier. A ten-minute-old
## damage line burning DANGER-red forever made the log the loudest element on screen.
const LOG_FADE_MS: int = 10000

const EDGE_PX: float = 12.0
const BAR_SIZE := Vector2(280.0, 16.0)

## Encumbrance words, from the ADR-18 speed multiplier. Below these, silence — a light load is
## not information.
const LADEN_BELOW: float = 0.99
const OVERBURDENED_BELOW: float = 0.85

var _root: Control = null
var _vitals_panel: PanelContainer = null
var _log_panel: PanelContainer = null
var _load_pill: PanelContainer = null
var _clock_pill: PanelContainer = null
var _health: VitalBar = null
var _stamina: VitalBar = null
var _conditions: RichTextLabel = null
var _log: RichTextLabel = null
var _keybar: HBoxContainer = null
var _cast_slot: RichTextLabel = null
var _load: RichTextLabel = null
var _clock: RichTextLabel = null
var _feed: Array[Dictionary] = []
var _accumulator: float = REFRESH_INTERVAL_S
var _applied_font_size: int = -1


func _ready() -> void:
	_build()
	ECSEvents.entity_damaged.connect(_on_damaged)
	ECSEvents.entity_died.connect(_on_died)
	ECSEvents.item_taken.connect(_on_taken)
	ECSEvents.action_rejected.connect(_on_rejected)
	ECSEvents.entity_landed.connect(_on_landed)
	ECSEvents.entity_mutated.connect(_on_mutated)
	ECSEvents.runes_learned.connect(_on_runes_learned)
	ECSEvents.player_died.connect(_on_player_died)
	ECSEvents.player_reborn.connect(_on_player_reborn)
	ECSEvents.player_changed_floor.connect(_on_changed_floor)
	ECSEvents.spell_bound.connect(_on_spell_bound)


func _process(delta: float) -> void:
	if not World.booted:
		_root.visible = false
		return
	_root.visible = true
	_accumulator += delta
	if _accumulator >= REFRESH_INTERVAL_S:
		_accumulator = 0.0
		_apply_font_sizes()
		_refresh()
	_place()


## Explicit measure-and-place, the same pattern the hover card and pack use. Anchors are the
## spec's long-term answer (HUD edit mode saves viewport fractions), but anchored containers do
## not re-size themselves to fit content under a plain Control.
##
## `reset_size()` FIRST, then read `size`. A RichTextLabel with `fit_content` under-reports its
## minimum until it has been laid out at least once, so measuring the minimum directly placed
## every bottom-anchored element half off the screen — reset forces the layout, and the settled
## size is the truth.
func _place() -> void:
	var view: Vector2 = Vector2(get_viewport().get_visible_rect().size)
	for panel in [_vitals_panel, _log_panel, _keybar, _load_pill, _clock_pill]:
		panel.reset_size()

	_vitals_panel.position = Vector2(EDGE_PX, EDGE_PX)
	_log_panel.position = Vector2(EDGE_PX, view.y - _log_panel.size.y - EDGE_PX)
	_log_panel.visible = not _feed.is_empty()
	_keybar.position = Vector2(
		(view.x - _keybar.size.x) / 2.0, view.y - _keybar.size.y - EDGE_PX
	)
	# A long log line and the keybar share the bottom edge and can meet on a narrow window.
	# The log yields upward: the keybar is muscle memory and stays put.
	if _log_panel.position.x + _log_panel.size.x + float(UITheme.GAP_PX) > _keybar.position.x:
		_log_panel.position.y = _keybar.position.y - _log_panel.size.y - float(UITheme.GAP_PX)
	_load_pill.position = Vector2(
		view.x - _load_pill.size.x - EDGE_PX, view.y - _load_pill.size.y - EDGE_PX
	)
	# Same collision rule from the right: on a narrow window the load chip yields upward too.
	if _load_pill.position.x < _keybar.position.x + _keybar.size.x + float(UITheme.GAP_PX):
		_load_pill.position.y = _keybar.position.y - _load_pill.size.y - float(UITheme.GAP_PX)
	_clock_pill.position = Vector2(view.x - _clock_pill.size.x - EDGE_PX, EDGE_PX)


# --- composition, static so headless tests can assert the words --------------------------------


## What the keybar's cast slot says: the bound spell in the player's words, or the way to get one.
static func bound_spell_label(row: int) -> String:
	var mind: MindComponent = ECSManager.minds.get(row)
	if mind == null or mind.active_spell == &"":
		return "nothing bound"
	var spell: CompiledSpell = mind.grimoire.get(mind.active_spell)
	if spell == null:
		return String(mind.active_spell)
	return EntityCard.spell_name(spell)


## "12.4 / 30 kg", plus the slowdown once encumbrance actually bites.
static func load_text(mass_kg: float, capacity_kg: float, multiplier: float) -> String:
	var text: String = "%.1f / %.0f kg" % [mass_kg, capacity_kg]
	var word: String = laden_word(multiplier)
	if word != "":
		return "%s · %s" % [text, word]
	return text


static func laden_word(multiplier: float) -> String:
	if multiplier < OVERBURDENED_BELOW:
		return "overburdened"
	if multiplier < LADEN_BELOW:
		return "laden"
	return ""


## The player's condition line: the card's words, plus encumbrance. Empty when nothing is wrong,
## which is the common case and the quiet corner it buys.
static func condition_text(row: int) -> String:
	var words: Array[String] = EntityCard.conditions(row)
	var laden: String = laden_word(InventorySystem.speed_multiplier(row))
	if laden != "":
		words.append(laden)
	return ", ".join(words)


## A feed line with its repeat count. The HUD spec's spam aggregator: ten identical events are
## one line saying so, never ten lines.
static func feed_display(raw: String, count: int) -> String:
	return raw if count <= 1 else "%s (x%d)" % [raw, count]


static func floor_word(floor_index: int) -> String:
	return "the surface" if floor_index == 0 else "floor %d" % floor_index


# --- the frame ----------------------------------------------------------------------------------


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_build_vitals()
	_build_log()
	_build_keybar()
	_build_load()
	_build_clock()


func _build_vitals() -> void:
	_vitals_panel = PanelContainer.new()
	_vitals_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vitals_panel.add_theme_stylebox_override("panel", UITheme.panel_style())
	UITheme.decorate(_vitals_panel)
	_root.add_child(_vitals_panel)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 4)
	_vitals_panel.add_child(column)

	_health = _bar("Health", UITheme.HEALTH)
	column.add_child(_health)
	_stamina = _bar("Stamina", UITheme.STAMINA)
	column.add_child(_stamina)
	_conditions = _text_label()
	column.add_child(_conditions)


func _build_log() -> void:
	_log_panel = PanelContainer.new()
	_log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log_panel.add_theme_stylebox_override("panel", UITheme.log_style())
	_root.add_child(_log_panel)
	_log = _text_label()
	_log_panel.add_child(_log)


func _build_keybar() -> void:
	_keybar = HBoxContainer.new()
	_keybar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_keybar.add_theme_constant_override("separation", UITheme.GAP_PX)
	_root.add_child(_keybar)

	for slot in [["E", "take / use"], ["B", "grimoire"], ["I", "pack"], ["Shift", "careful"]]:
		var label: RichTextLabel = _text_label()
		label.text = "%s %s" % [
			UITheme.primary("[b]%s[/b]" % slot[0]), UITheme.muted(slot[1])
		]
		_keybar.add_child(_pill_holding(label))
	# The cast slot is kept, not rebuilt: it changes with every bind.
	_cast_slot = _text_label()
	_keybar.add_child(_pill_holding(_cast_slot))
	_refresh_cast_slot()


func _build_load() -> void:
	_load = _text_label()
	_load_pill = _pill_holding(_load)
	_root.add_child(_load_pill)


## Pilled like its diagonal twin the load chip, so the four corners share one anatomy.
func _build_clock() -> void:
	_clock = _text_label()
	_clock_pill = _pill_holding(_clock)
	_root.add_child(_clock_pill)


func _bar(label: String, colour_hex: String) -> VitalBar:
	var bar := VitalBar.new()
	bar.label = label
	bar.fill_colour = Color("#" + colour_hex)
	bar.custom_minimum_size = BAR_SIZE
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bar


## A small themed pill around one label — the keybar slots and the load chip.
func _pill_holding(label: RichTextLabel) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = UITheme.panel_style()
	style.set_content_margin_all(UITheme.GAP_PX)
	panel.add_theme_stylebox_override("panel", style)
	panel.add_child(label)
	return panel


func _text_label() -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 4)
	return label


## One text-size knob for every layer: the HUD follows the same `=`/`-` setting as the overlay.
func _apply_font_sizes() -> void:
	if _applied_font_size == DebugFlags.overlay_font_size:
		return
	_applied_font_size = DebugFlags.overlay_font_size
	var body: int = _applied_font_size
	var caption: int = maxi(12, _applied_font_size - 4)
	# The log takes CAPTION size like its peers. It had the only body-sized text on the HUD,
	# which put the loudest type on the least important element — inverted hierarchy.
	for label in [_conditions, _log, _cast_slot, _load, _clock]:
		label.add_theme_font_size_override("normal_font_size", caption)
		label.add_theme_font_size_override("bold_font_size", caption)
	# Width scales with the text knob too, or a 64 pt "100/100" collides with its own label
	# inside a bar sized for 20 pt.
	var bar_height: float = maxf(BAR_SIZE.y, float(body) - 2.0)
	var bar_width: float = BAR_SIZE.x * float(body) / 20.0
	_health.custom_minimum_size = Vector2(bar_width, bar_height)
	_stamina.custom_minimum_size = Vector2(bar_width, bar_height)
	for slot in _keybar.get_children():
		for child in slot.get_children():
			if child is RichTextLabel:
				child.add_theme_font_size_override("normal_font_size", caption)
				child.add_theme_font_size_override("bold_font_size", caption)


# --- the pull path ------------------------------------------------------------------------------


func _refresh() -> void:
	var row: int = ECSManager.resolve(ECSManager.player_handle())
	if row < 0:
		return
	var body: BodyComponent = ECSManager.bodies.get(row)
	if body != null:
		_health.set_vital(body.health, body.max_health)
		_stamina.set_vital(body.stamina, body.max_stamina, body.strain)
	_conditions.text = "[color=#%s]%s[/color]" % [UITheme.WARNING, condition_text(row)]
	_conditions.visible = condition_text(row) != ""
	_refresh_cast_slot()
	_refresh_load(row)
	if not _feed.is_empty():
		_redraw_log()
	_clock.text = UITheme.muted("%s · %s" % [
		GameClock.to_display_string(), floor_word(ECSManager.col_floor[row])
	])


func _refresh_cast_slot() -> void:
	var row: int = ECSManager.resolve(ECSManager.player_handle())
	if row < 0:
		return
	_cast_slot.text = "%s %s" % [
		UITheme.primary("[b]Q[/b]"), UITheme.muted(bound_spell_label(row))
	]


func _refresh_load(row: int) -> void:
	var inventory: InventoryComponent = ECSManager.inventories.get(row)
	var body: BodyComponent = ECSManager.bodies.get(row)
	if inventory == null or body == null:
		_load.text = ""
		return
	_load.text = UITheme.body(load_text(
		inventory.total_mass_kg,
		body.carry_capacity_kg(),
		InventorySystem.speed_multiplier(row)
	))


# --- the running log ----------------------------------------------------------------------------


## Newest first, clock-stamped, aggregated. `raw` is compared for aggregation BEFORE colour and
## stamp are applied, so the same event in a different minute still collapses.
func _remember(raw: String, colour_hex: String) -> void:
	if not _feed.is_empty() and String(_feed[0]["raw"]) == raw:
		_feed[0]["count"] = int(_feed[0]["count"]) + 1
		_feed[0]["born_ms"] = Time.get_ticks_msec()
	else:
		_feed.push_front({
			"raw": raw,
			"colour": colour_hex,
			"stamp": _stamp(),
			"count": 1,
			"born_ms": Time.get_ticks_msec(),
		})
		while _feed.size() > FEED_CAPACITY:
			_feed.pop_back()
	_redraw_log()


## Old lines go muted rather than staying in their event colour: the log reports, it does not
## alarm. Re-run from the refresh cycle so lines age without needing a new event.
func _redraw_log() -> void:
	var now: int = Time.get_ticks_msec()
	var lines: Array[String] = []
	for entry in _feed:
		var colour: String = String(entry["colour"])
		if now - int(entry.get("born_ms", now)) >= LOG_FADE_MS:
			colour = UITheme.TEXT_MUTED
		lines.append("%s [color=#%s]%s[/color]" % [
			UITheme.muted(String(entry["stamp"])),
			colour,
			feed_display(String(entry["raw"]), int(entry.get("count", 1))),
		])
	_log.text = "\n".join(lines)


func _stamp() -> String:
	return "%02d:00" % GameClock.hour


func _is_player(entity: int) -> bool:
	return entity == ECSManager.player_handle()


func _on_damaged(entity: int, amount: float, remaining: float, cause: StringName) -> void:
	# Falls report through `_on_landed`, which knows the speed too. One event, one line.
	if not _is_player(entity) or cause == &"fall":
		return
	_remember("you take %.0f damage — %.0f left" % [amount, remaining], UITheme.DANGER)


func _on_died(entity: int, _cause: StringName) -> void:
	# The player's own death gets the bigger line from `player_died`.
	if _is_player(entity):
		return
	_remember("%s dies" % EntityCard.title_or_last(entity), UITheme.TEXT_BODY)


func _on_taken(taker: int, item: int, _reason: StringName) -> void:
	if not _is_player(taker):
		return
	_remember("taken: %s" % EntityCard.title_or_last(item), UITheme.GOOD)


## Refusals and notices. "Silence is the worst possible feedback" is this project's oldest UI
## rule; the reasons are already written in the player's words at the emit sites.
func _on_rejected(actor: int, _action: StringName, reason: StringName) -> void:
	if not _is_player(actor):
		return
	_remember(String(reason), UITheme.WARNING)


func _on_landed(entity: int, _speed_mps: float, damage: float) -> void:
	if not _is_player(entity) or damage <= 0.0:
		return
	_remember("you land hard — %.0f damage" % damage, UITheme.DANGER)


func _on_mutated(entity: int, mutation: StringName) -> void:
	if not _is_player(entity):
		return
	_remember(
		"your body changes — %s" % String(mutation).replace("_", " "), UITheme.WARNING
	)


func _on_runes_learned(reader: int, runes: Array) -> void:
	if not _is_player(reader):
		return
	if runes.is_empty():
		_remember("the inscription holds nothing new", UITheme.TEXT_MUTED)
		return
	var names: Array[String] = []
	for rune in runes:
		names.append(String(rune).replace("_", " "))
	_remember("learned: %s" % ", ".join(names), UITheme.GOOD)


func _on_player_died(_corpse: int, _killer: int, lineage_generation: int) -> void:
	_remember("you die — generation %d ends here" % lineage_generation, UITheme.DANGER)


func _on_player_reborn(_player: int, lineage_generation: int) -> void:
	_remember(
		"a year passes — a new adventurer arrives (generation %d)" % lineage_generation,
		UITheme.TEXT_PRIMARY
	)


func _on_changed_floor(from_floor: int, to_floor: int) -> void:
	var verb: String = "descend" if to_floor < from_floor else "climb"
	_remember("you %s to %s" % [verb, floor_word(to_floor)], UITheme.TEXT_BODY)


func _on_spell_bound(caster: int, _spell_id: StringName, ok: bool, _reason: StringName) -> void:
	if ok and _is_player(caster):
		_refresh_cast_slot()
