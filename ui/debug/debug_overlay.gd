## Read-only observability surface (debugging spec section 9, Sprint 1 deliverable).
##
## Reads ECS state and NEVER mutates it. The UI is a dumb listener.
##
## Without an entity inspector every bug is a print-statement expedition, so the inspector is the
## highest-value item here, and it selects THROUGH PickSystem so it dogfoods the pick path.
class_name DebugOverlay
extends CanvasLayer

## Pages, cycled with F1. The live counters are page one because that is what you want while
## moving; the rest answer questions you ask while standing still.
## HIDDEN is a real page, not an absence. Cycling round to it dismisses the panel entirely, so
## one key both drives the tool and gets it out of the way — asked for during play-testing, and
## the alternative is a second key that does nothing else.
enum Page { LIVE, HISTORY, FACTIONS, MAP, HIDDEN }

const REFRESH_INTERVAL_S: float = 0.25

## How many outcome events the feed keeps. Enough to see a fight, short enough to read.
const FEED_CAPACITY: int = 8

## Tallest the panel may grow before it starts scrolling, as a fraction of the window. Leaves
## enough of the world visible that the overlay never becomes the whole screen.
const MAX_PANEL_SCREEN_FRACTION: float = 0.8

var _panel: PanelContainer = null
var _header: Label = null
var _scroll: ScrollContainer = null
var _label: RichTextLabel = null
var _minimap: MinimapView = null
var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _selected_row: int = -1
var _accumulator: float = 0.0
var _feed: Array[String] = []
## Worst micro-tick duration since the panel last redrew, fed by the per-frame signal.
var _worst_micro_ms: float = 0.0
var _page: Page = Page.LIVE
var _lmb_presses: int = 0
var _rmb_presses: int = 0


func _ready() -> void:
	# Godot readies CHILDREN before their parent, so this runs before `Main._ready` — which is
	# where DebugFlags was being initialised. Every flag read below was therefore reading a
	# default, and a font size set in `debug_config.json` silently never applied. `initialize`
	# is idempotent, so asking here costs nothing and removes the ordering dependency.
	DebugFlags.initialize()
	_build_panel()
	_page = clampi(DebugFlags.boot_overlay_page, 0, Page.size() - 1) as Page
	# HIDDEN at boot since the player HUD took over the player-facing duties. `F1` summons the
	# panel at `boot_overlay_page` exactly as before; captures that need it up from frame one set
	# `overlay_visible_on_boot` in the config alongside the page.
	if not DebugFlags.overlay_visible_on_boot:
		_page = Page.HIDDEN
	_panel.visible = _page != Page.HIDDEN
	visible = DebugFlags.tick_counters_enabled

	# Listen only. The overlay never writes ECS state (Prime Directive / invariants §2).
	ECSEvents.entity_damaged.connect(_on_damaged)
	ECSEvents.entity_died.connect(_on_died)
	ECSEvents.item_taken.connect(_on_taken)
	ECSEvents.action_rejected.connect(_on_rejected)
	ECSEvents.entity_landed.connect(_on_landed)
	ECSEvents.faction_decided.connect(_on_faction_decided)
	ECSEvents.faction_thinking.connect(_on_faction_thinking)
	ECSEvents.player_died.connect(_on_player_died)
	ECSEvents.player_reborn.connect(_on_player_reborn)
	ECSEvents.faction_leader_succeeded.connect(_on_leader_succeeded)
	ECSEvents.faction_schism.connect(_on_schism)
	ECSEvents.caravan_departed.connect(_on_caravan_departed)
	ECSEvents.caravan_arrived.connect(_on_caravan_arrived)
	ECSEvents.caravan_lost.connect(_on_caravan_lost)
	ECSEvents.player_changed_floor.connect(_on_changed_floor)
	ECSEvents.faction_relationship_changed.connect(_on_relationship_changed)
	ECSEvents.spell_cast.connect(_on_spell_cast)
	ECSEvents.spell_detonated.connect(_on_spell_detonated)
	ECSEvents.entity_mutated.connect(_on_mutated)
	ECSEvents.runes_learned.connect(_on_runes_learned)
	ECSEvents.tick_completed.connect(_on_tick_completed)


## A DRAGGABLE, NON-MODAL panel rather than text painted on the screen.
##
## Two problems with the bare label it replaces. It sat over the top-left corner of the world
## permanently, and there was no way to move it off whatever you were trying to look at. And a
## click anywhere — including on the text — went straight through to the game and swung a weapon.
##
## MONOSPACE IS NOT COSMETIC. The `F1` map is a grid of characters, and in a proportional font the
## columns do not line up, so the map is unreadable as a map. Every other page benefits too:
## numbers that change each frame stop jittering sideways.
func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.position = Vector2(12, 12)
	# STOP, deliberately: a click on the panel belongs to the panel. Without it, reading the
	# overlay means attacking whatever is behind it.
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.07, 0.78)
	style.border_color = Color(0.45, 0.45, 0.55, 0.9)
	style.set_border_width_all(1)
	style.set_content_margin_all(8)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var column := VBoxContainer.new()
	_panel.add_child(column)

	_header = Label.new()
	_header.text = "  ☰  debug  —  drag me    [F1] page / hide    [G] gizmos    [=/-] size"
	_header.mouse_filter = Control.MOUSE_FILTER_STOP
	_header.add_theme_color_override("font_color", Color(0.72, 0.78, 0.95))
	column.add_child(_header)

	# SCROLLABLE. The chronicle and the faction list are both longer than a screen, and a panel
	# that simply runs off the bottom hides exactly the recent events you opened it to read.
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	column.add_child(_scroll)

	# RICH TEXT, not a plain Label: the panel needs per-value colour and that is the only way to
	# get it without one Control per row.
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 4)
	_scroll.add_child(_label)

	# The map is DRAWN, not spelled out. See MinimapView for why the ASCII version was the wrong
	# tool: it depended on a monospace font to line up at all, and a grid of letters is a poor
	# answer to a spatial question in an engine that can simply draw one.
	_minimap = MinimapView.new()
	_minimap.visible = false
	column.add_child(_minimap)
	_apply_font_size()


## True while the pointer is over the panel, so gameplay input can ignore that click.
##
## The input bridge POLLS `Input.is_action_just_pressed` rather than consuming events, so marking
## an event handled does not reach it. It has to ask.
func wants_mouse() -> bool:
	if not visible or _panel == null or not _panel.visible:
		return false
	return _panel.get_global_rect().has_point(_panel.get_global_mouse_position())


## Dragging is handled here rather than on the header, because the pointer routinely leaves the
## header's rect mid-drag and a Control only receives `_gui_input` while the pointer is inside it.
func _input(event: InputEvent) -> void:
	if not visible or _panel == null or not _panel.visible:
		return
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed and _header.get_global_rect().has_point(button.position):
			_dragging = true
			_drag_offset = _panel.position - button.position
			get_viewport().set_input_as_handled()
		elif not button.pressed:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		var motion: InputEventMouseMotion = event
		# Clamped so the panel can never be dragged entirely off-screen and stranded.
		var limit: Vector2 = get_viewport().get_visible_rect().size - Vector2(60, 24)
		_panel.position = (motion.position + _drag_offset).clamp(Vector2.ZERO, limit)
		get_viewport().set_input_as_handled()


## Text size is adjustable at runtime, because "edit a JSON file in the user data directory and
## restart" is not a real answer to "I cannot read this".
func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_pressed():
		return
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.button_index == MOUSE_BUTTON_LEFT:
			_lmb_presses += 1
		elif button.button_index == MOUSE_BUTTON_RIGHT:
			_rmb_presses += 1
		return
	var delta: int = 0
	if event.is_action(&"cycle_debug_page"):
		_page = ((_page + 1) % Page.size()) as Page
		# HIDDEN dismisses the panel rather than drawing an empty one.
		_panel.visible = _page != Page.HIDDEN
		_accumulator = REFRESH_INTERVAL_S
		get_viewport().set_input_as_handled()
		return
	if event.is_action(&"overlay_text_bigger"):
		delta = 2
	elif event.is_action(&"overlay_text_smaller"):
		delta = -2
	if delta == 0:
		return
	DebugFlags.overlay_font_size = clampi(
		DebugFlags.overlay_font_size + delta,
		DebugFlags.MIN_OVERLAY_FONT_SIZE,
		DebugFlags.MAX_OVERLAY_FONT_SIZE
	)
	_apply_font_size()
	DebugFlags.save_config()
	get_viewport().set_input_as_handled()


## Grows the panel to fit its text, up to a ceiling, then scrolls.
##
## A Control has no `max_size`, so the height is computed: take what the label wants, and clamp it
## to a fraction of the viewport. Below the ceiling the panel is exactly as tall as its content
## and there is no scrollbar to notice; above it, the wheel works.
func _fit_scroll() -> void:
	if _scroll == null or _label == null:
		return
	var ceiling: float = get_viewport().get_visible_rect().size.y * MAX_PANEL_SCREEN_FRACTION
	_scroll.custom_minimum_size.y = minf(_label.get_combined_minimum_size().y, ceiling)


## MONOSPACE. The `F1` map is a grid of characters and a proportional font shreds its columns,
## which is what made the map "very poorly rendered and not aligned". A system monospace font is
## requested by name so the panel does not depend on a font asset being present.
func _apply_font_size() -> void:
	if _label == null:
		return
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(
		["JetBrains Mono", "SF Mono", "Menlo", "DejaVu Sans Mono", "Consolas", "monospace"]
	)
	# RichTextLabel keys its fonts by role. `normal_font` and `bold_font` must BOTH be set, or a
	# [b] heading silently falls back to a proportional face and the columns under it stop
	# lining up — which is the exact failure the monospace switch was made to fix.
	for role in ["normal_font", "bold_font", "italics_font", "mono_font"]:
		_label.add_theme_font_override(role, mono)
	_label.add_theme_font_size_override("normal_font_size", DebugFlags.overlay_font_size)
	_label.add_theme_font_size_override("bold_font_size", DebugFlags.overlay_font_size)
	if _header != null:
		_header.add_theme_font_override("font", mono)
		_header.add_theme_font_size_override("font_size", DebugFlags.overlay_font_size)


func _process(delta: float) -> void:
	if not visible or _panel == null or not _panel.visible:
		return
	_accumulator += delta
	if _accumulator < REFRESH_INTERVAL_S:
		return
	_accumulator = 0.0
	var on_map: bool = _page == Page.MAP
	_scroll.visible = not on_map
	_minimap.visible = on_map
	if on_map:
		_minimap.refresh()
	else:
		_label.text = _compose()
		_fit_scroll()


func _compose() -> String:
	var header: String = "[F1] %s   (%d of %d)\n" % [
		Page.keys()[_page], int(_page) + 1, Page.size()
	]
	match _page:
		Page.HISTORY:
			return header + WorldInspector.history_text()
		Page.FACTIONS:
			return header + WorldInspector.factions_text()
		Page.MAP:
			return header + WorldInspector.map_text()
		_:
			return header + _compose_live()


func _compose_live() -> String:
	var counters: Dictionary = GameLoopManager.counters()
	var fps: float = maxf(float(Engine.get_frames_per_second()), 1.0)
	var out: Array[String] = []

	out.append(PanelFormat.heading("world"))
	out.append(PanelFormat.row("time", PanelFormat.plain(String(counters["clock"]))))
	out.append(PanelFormat.row("scenario", PanelFormat.accent(String(World.scenario))))
	out.append(PanelFormat.row(
		"frame",
		"%s %s" % [
			PanelFormat.plain("%d fps" % int(fps)),
			PanelFormat.muted("(%.1f ms)" % (1000.0 / fps)),
		]
	))

	out.append(PanelFormat.heading("you"))
	for line in _player_rows():
		out.append(line)

	out.append(PanelFormat.heading("cursor"))
	out.append(PanelFormat.row("pointing", _cursor_value()))
	out.append(PanelFormat.row(
		"mouse",
		PanelFormat.tally([
			["LMB " + ("down" if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) else "up"), ""],
			["RMB " + ("down" if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) else "up"), ""],
			[_lmb_presses, "clicks"],
		])
	))

	out.append(PanelFormat.heading("performance"))
	out.append(PanelFormat.row("micro", PanelFormat.against_budget(
		float(counters["last_micro_ms"]), float(counters["micro_budget_ms"]), "ms"
	)))
	# Fed by the `tick_completed` SIGNAL, which fires every frame — the poll above samples
	# whichever frame the overlay happened to redraw on, so a 12 ms spike between redraws was
	# invisible. The signal existed for overlays since Sprint 0 and had zero listeners.
	out.append(PanelFormat.row("worst", "%.2f ms since last redraw" % _worst_micro_ms))
	_worst_micro_ms = 0.0
	out.append(PanelFormat.row("other", PanelFormat.tally([
		["%.2f" % counters["last_sim_ms"], "sim"],
		["%.2f" % counters["last_fluid_ms"], "fluid"],
		["%.2f" % counters["last_spatial_ms"], "spatial"],
	])))

	out.append(PanelFormat.heading("world state"))
	out.append(PanelFormat.row("entities", PanelFormat.tally([
		[counters["alive_count"], "alive"],
		[counters.get("lod_active_entities", 0), "active"],
		[WorldConstants.ACTIVE_ENTITY_HARD_CAP, "cap"],
		[counters["free_rows"], "free rows"],
	])))
	out.append(PanelFormat.row("movement", PanelFormat.tally([
		[counters.get("movers_processed", 0), "movers"],
		[counters.get("walkers", 0), "walking"],
		[counters.get("tile_collisions", 0), "wall hits"],
		[counters.get("entity_collisions", 0), "bumps"],
	])))
	out.append(PanelFormat.row("fluids", PanelFormat.tally([
		[counters.get("ca_cell_updates", 0), "updates"],
		[counters.get("ca_dirty_cells", 0), "dirty"],
		[counters.get("ca_pumped_units", 0), "pumped"],
	])))
	out.append(PanelFormat.row("senses", PanelFormat.tally([
		[counters.get("total_los_marches", 0), "LoS"],
		[counters.get("total_perceived", 0), "perceived"],
		[counters.get("witness_events", 0), "witnesses"],
	])))
	out.append(PanelFormat.row("chemistry", PanelFormat.tally([
		[counters.get("reactions_fired", 0), "reactions"],
		[counters.get("reaction_cooldowns", 0), "locked"],
		["%.0fC" % counters.get("reaction_ambient_c", 0.0), "air"],
		[counters.get("ca_gas_cells", 0), "gas cells"],
	])))
	out.append(PanelFormat.row("magic", PanelFormat.tally([
		[counters.get("casts_resolved", 0), "cast"],
		[counters.get("casts_fizzled", 0), "fizzled"],
		[counters.get("spell_detonations", 0), "detonations"],
		[counters.get("ephemerals_active", 0), "in flight"],
		[counters.get("mutations", 0), "mutations"],
	])))
	out.append(PanelFormat.row("factions", PanelFormat.tally([
		[counters.get("plans_made", 0), "plans"],
		[counters.get("reason_dispatched", 0), "thoughts"],
		[counters.get("llm_hallucinated_targets", 0), "rejected"],
	])))

	var stale: int = int(counters["stale_handle_rejections"])
	out.append(PanelFormat.row(
		"handles",
		# Stale rejections are the one counter here that should ALWAYS be zero. Anything else is
		# a handle outliving its generation, so it earns red rather than sitting in a grey list.
		(PanelFormat.bad("%d stale" % stale) if stale > 0 else PanelFormat.tally([
			[stale, "stale"], [counters["destroy_count"], "destroyed"]
		]))
	))

	if _selected_row >= 0:
		out.append(PanelFormat.heading("inspecting"))
		out.append(_inspect(_selected_row))
	if not _feed.is_empty():
		out.append(PanelFormat.heading("recent"))
		for entry in _feed:
			out.append("  " + entry)
	return "\n".join(out)


## The player block: position, condition, and what is under their feet.
func _player_rows() -> Array[String]:
	var row: int = ECSManager.resolve(ECSManager.player_handle())
	if row < 0:
		return [PanelFormat.row("status", PanelFormat.bad("no player entity"))] as Array[String]

	var position: Vector3 = ECSManager.position_of(row)
	var chunk: ChunkData = World.chunk_containing(position)
	var out: Array[String] = []
	if chunk != null:
		var tile: Vector2i = chunk.world_to_tile(position)
		out.append(PanelFormat.row(
			"at",
			"%s %s" % [
				PanelFormat.plain("tile %d, %d" % [tile.x, tile.y]),
				PanelFormat.muted("(%.1f, %.1f, %.1f)" % [position.x, position.y, position.z]),
			]
		))
		out.append(PanelFormat.row("standing", PanelFormat.plain(_tile_readout(chunk, tile))))

	var body: BodyComponent = ECSManager.bodies.get(row)
	if body != null:
		out.append(PanelFormat.row("health", PanelFormat.bar(body.health, body.max_health)))
		out.append(PanelFormat.row("stamina", PanelFormat.bar(body.stamina, body.max_stamina)))

	var velocity: Vector3 = ECSManager.velocity_of(row)
	var state: String = PanelFormat.plain("grounded")
	if velocity.y < -0.05:
		state = PanelFormat.bad("FALLING %.1f m/s" % -velocity.y)
	elif velocity.y > 0.05:
		state = PanelFormat.plain("rising")
	out.append(PanelFormat.row(
		"state",
		"%s %s" % [
			state, PanelFormat.muted("safe fall < %.0f m/s" % WorldConstants.SAFE_FALL_MPS)
		]
	))
	return out


func _cursor_value() -> String:
	var chunk: ChunkData = World.active_chunk
	var camera: Camera3D = get_viewport().get_camera_3d()
	if chunk == null or camera == null:
		return PanelFormat.muted("no camera")
	var tile: Vector2i = _cursor_tile(chunk, camera)
	if tile.x < 0:
		return PanelFormat.muted("not over the world")
	var owner: ChunkData = _owner_for(camera)
	return "%s %s" % [
		PanelFormat.plain("tile %d, %d" % [tile.x, tile.y]),
		PanelFormat.muted(_tile_readout(owner if owner != null else chunk, tile)),
	]


## Newest-first ring of outcome events. Bounded, so a long session cannot grow it without limit.
func _remember(text: String) -> void:
	_feed.push_front("%s  %s" % [GameClock.to_display_string(), text])
	while _feed.size() > FEED_CAPACITY:
		_feed.pop_back()


func _on_damaged(entity: int, amount: float, remaining: float, cause: StringName) -> void:
	# Falls are reported by `_on_landed`, which knows the impact speed as well as the damage.
	# Reporting both would print two lines for one event.
	if cause == &"fall":
		return
	_remember(
		"%s took %.1f damage (%s), %.1f left"
		% [_name_of(entity), amount, cause, remaining]
	)


## A survivable fall is a RESULT, not an absence of one. Reporting only damaging landings made
## "I fell and nothing happened" indistinguishable from "the fall was never detected" — which is
## precisely how the fall system looked while it was genuinely broken.
func _on_landed(entity: int, speed_mps: float, damage: float) -> void:
	if damage > 0.0:
		_remember("%s landed at %.1f m/s — %.1f damage" % [_name_of(entity), speed_mps, damage])
		return
	_remember(
		"%s landed at %.1f m/s — unhurt (safe below %.0f)"
		% [_name_of(entity), speed_mps, WorldConstants.SAFE_FALL_MPS]
	)


func _on_died(entity: int, cause: StringName) -> void:
	_remember("%s DIED (%s)" % [_name_of(entity), cause])


func _on_taken(taker: int, item: int, _reason: StringName) -> void:
	_remember("%s picked up %s" % [_name_of(taker), _name_of(item)])


func _on_rejected(actor: int, action: StringName, reason: StringName) -> void:
	_remember("%s: %s refused — %s" % [_name_of(actor), action, reason])


## The "thinking" bark (roadmap review F1). Deliberation used to be invisible until the answer
## landed, so a leader mid-decision looked identical to a leader doing nothing — and with a slow
## remote provider that could be many seconds of apparent inertness. The decided line below is
## what replaces this one when the response arrives.
func _on_faction_thinking(faction_id: int, is_crisis: bool) -> void:
	var why: String = "URGENTLY " if is_crisis else ""
	_remember("faction %d is %sdeliberating..." % [faction_id, why])


## Factions talk. Without this the entire reasoning layer runs invisibly and the only evidence
## it exists at all is that NPCs occasionally walk somewhere different.
func _on_faction_decided(faction_id: int, objective: String, declaration: String) -> void:
	if declaration == "":
		_remember("faction %d -> %s" % [faction_id, objective])
		return
	_remember("faction %d -> %s: \"%s\"" % [faction_id, objective, declaration])


## Turning hostile is a story beat, not a statistic. It gets its own line.
func _on_relationship_changed(
	faction_id: int, about_faction: int, score: float, now_hostile: bool
) -> void:
	if not now_hostile:
		return
	var who: String = "you" if about_faction == WorldConstants.PLAYER_FACTION_ID else (
		"faction %d" % about_faction
	)
	_remember("faction %d is now HOSTILE to %s (%.0f)" % [faction_id, who, score])


func _on_spell_cast(caster: int, spell_id: StringName, strain: float) -> void:
	_remember("%s cast %s (%.1f strain)" % [_name_of(caster), spell_id, strain])


## The detonation is a SEPARATE line from the cast. A fireball that leaves the hand and never
## goes off is the exact failure the projectile path can have, and one combined line could not
## tell the two apart.
func _on_spell_detonated(_caster: int, spell_id: StringName, at: Vector3) -> void:
	_remember("%s went off at (%.1f, %.1f)" % [spell_id, at.x, at.z])


## A permanent change to your body earns a line of its own. It is also the moment the faction
## consequence starts, so the feed showing it makes the delay before the village reacts legible
## as a delay rather than as nothing happening.
func _on_mutated(entity: int, mutation: StringName) -> void:
	_remember("%s MUTATED — %s" % [_name_of(entity), mutation])


## The biggest event in the game had NO LISTENER anywhere — `player_died` was emitted into
## silence, so the run ending produced no feed line and the freeze that follows (the loop pauses
## on death) read as a crash. Found by the dead-symbol sweep, not by any test or play session.
func _on_player_died(_corpse: int, _killer: int, lineage_generation: int) -> void:
	_remember("YOU DIED — generation %d ends here" % lineage_generation)


func _on_player_reborn(_player: int, lineage_generation: int) -> void:
	_remember("a new adventurer arrives — generation %d" % lineage_generation)


func _on_leader_succeeded(faction_id: int, _new_leader: int, prestige: float) -> void:
	_remember("faction %d has a new leader (prestige %.0f)" % [faction_id, prestige])


func _on_schism(parent_faction: int, splinter_faction: int, defectors: int) -> void:
	_remember(
		"SCHISM — %d citizens of faction %d break away as faction %d"
		% [defectors, parent_faction, splinter_faction]
	)


func _on_caravan_departed(from_faction: int, to_faction: int, _carrier: int) -> void:
	_remember("caravan: faction %d -> faction %d departs" % [from_faction, to_faction])


func _on_caravan_arrived(
	from_faction: int, to_faction: int, material: StringName, quantity: int
) -> void:
	_remember(
		"caravan: %d %s delivered, faction %d -> %d"
		% [quantity, material, from_faction, to_faction]
	)


func _on_caravan_lost(from_faction: int, to_faction: int) -> void:
	_remember("caravan: faction %d -> %d LOST on the road" % [from_faction, to_faction])


func _on_tick_completed(
	tick_class: StringName, duration_ms: float, _entities: int
) -> void:
	if tick_class == &"micro":
		_worst_micro_ms = maxf(_worst_micro_ms, duration_ms)


func _on_runes_learned(_reader: int, runes: Array) -> void:
	if runes.is_empty():
		_remember("you read the inscription — nothing new")
		return
	var names: Array[String] = []
	for rune in runes:
		names.append(String(rune))
	_remember("LEARNED: %s" % ", ".join(names))


func _on_changed_floor(from_floor: int, to_floor: int) -> void:
	var verb: String = "descend" if to_floor < from_floor else "climb"
	_remember("you %s to floor %d" % [verb, to_floor])


## A handle is not a name. Without this the feed reads "entity 4294967296 took 3.2 damage".
## Delegated to `EntityCard.title_or_last` — one naming truth AND one last-known-name memory,
## shared with the player HUD's log, so the two feeds can never call one object two things.
func _name_of(entity: int) -> String:
	return EntityCard.title_or_last(entity)


## What a thing IS, in words. Delegated to `EntityCard` so the inspector header, the event feed
## and the hover card cannot drift apart — three names for one object is how "you picked up
## Item #2 / you picked up <gone>" happened. The debug-only detail (the raw handle) is appended
## by the caller, not baked in here.
func _label_for(row: int) -> String:
	return EntityCard.title(row)


## Selects an entity for inspection, or clears with a negative row. Called by the input bridge
## via PickSystem.
func select_row(row: int) -> void:
	_selected_row = row


## What is currently being inspected, or -1 for nothing. The input bridge needs this to decide
## whether a Tab press is a re-select of the same target (which clears) or a new one.
func selected_row() -> int:
	return _selected_row


## The chunk under the cursor, so the readout describes the tile it names.
func _owner_for(camera: Camera3D) -> ChunkData:
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var hit: Dictionary = GameLoopManager.picking.cursor_ground(
		camera.project_ray_origin(mouse), camera.project_ray_normal(mouse), World.sampler()
	)
	return null if not hit["hit"] else World.chunk_containing(hit["point"])


## Steps along the camera ray until it meets terrain: either the side of a solid tile, or the
## floor surface of an open one. Returns (-1, -1) if it leaves the chunk without hitting.
func _cursor_tile(_chunk: ChunkData, camera: Camera3D) -> Vector2i:
	var mouse: Vector2 = get_viewport().get_mouse_position()
	# Marched through the SAMPLER, so the readout stays correct across a chunk seam rather than
	# reporting "outside chunk" the moment the cursor leaves the player's own chunk.
	var hit: Dictionary = GameLoopManager.picking.cursor_ground(
		camera.project_ray_origin(mouse), camera.project_ray_normal(mouse), World.sampler()
	)
	if not hit["hit"]:
		return Vector2i(-1, -1)
	var owner: ChunkData = World.chunk_containing(hit["point"])
	return Vector2i(-1, -1) if owner == null else owner.world_to_tile(hit["point"])


## Kind, elevation and fluid for one tile. Elevation is what the step-up and drop rules read,
## and fluid is what the CA moves, so these are the two numbers worth seeing while walking.
func _tile_readout(chunk: ChunkData, tile: Vector2i) -> String:
	if not _in_chunk(tile):
		return "<outside chunk>"
	var units: int = chunk.fluid_at(tile.x, tile.y)
	var kind: String = "open"
	if chunk.is_solid(tile.x, tile.y):
		kind = "SOLID"
	elif chunk.tile_map[WorldConstants.cell_index(tile.x, tile.y)] == ChunkData.TILE_STAIRS:
		kind = "STAIRS (press E)"
	return "%s  elev %+.2fm  fluid %d" % [
		kind,
		chunk.height_at(tile.x, tile.y),
		units,
	]


func _in_chunk(tile: Vector2i) -> bool:
	return (
		tile.x >= 0
		and tile.y >= 0
		and tile.x < WorldConstants.CHUNK_TILES
		and tile.y < WorldConstants.CHUNK_TILES
	)


func _format_tile(tile: Vector2i) -> String:
	return "(%d, %d)" % [tile.x, tile.y]


## "Why did this entity do that?" — the explainability record.
func _inspect(row: int) -> String:
	var handle: int = ECSManager.handle_of(row)
	if not EH.is_valid(handle):
		return "inspector: <stale row %d>" % row
	var lines: Array[String] = []
	# The handle SECOND. "e51:g1" told a play-tester nothing about what they were looking at, and
	# an inspector whose first line is an opaque id makes them work out the answer some other way.
	lines.append("--- %s  [%s] ---" % [_label_for(row), EH.to_debug_string(handle)])
	lines.append("components: %s" % ComponentMask.describe(ECSManager.mask_of(row)))
	var pos: Vector3 = ECSManager.position_of(row)
	var chunk: ChunkData = World.chunk_containing(pos)
	var tile_text: String = ""
	if chunk != null:
		tile_text = "  tile %s" % _format_tile(chunk.world_to_tile(pos))
	lines.append("pos %v%s   vel %v" % [pos, tile_text, ECSManager.velocity_of(row)])

	var body: BodyComponent = ECSManager.bodies.get(row)
	if body != null:
		lines.append(
			"health %.1f/%.1f  stamina %.1f  strength %.1f" % [
				body.health, body.max_health, body.stamina, body.strength
			]
		)
	var need: NeedsComponent = ECSManager.needs.get(row)
	if need != null:
		lines.append(
			"hunger %.1f  energy %.1f  morale %.1f" % [need.hunger, need.energy, need.morale]
		)
	var physical: PhysicalPropertyComponent = ECSManager.physicals.get(row)
	if physical != null:
		lines.append(
			"mass %.3fkg  vol %.0fcm3  temp %.1fC  phase %s  qty %d" % [
				physical.mass_kg,
				physical.volume_cm3,
				physical.temperature_c(),
				_enum_name(ECSEnums.Phase, physical.phase),
				physical.quantity,
			]
		)
	# Tags carry their COUNTDOWN where they have one. `Reaction_Cooldown` with no number beside it
	# cannot be told from a lock that is stuck, which is the single most likely Sprint 4 bug and
	# the one the inspector should be able to answer on sight.
	var chemistry: ChemistryComponent = ECSManager.chemistries.get(row)
	if chemistry != null and not chemistry.active_tags.is_empty():
		lines.append("tags: %s" % ", ".join(_tags_with_countdowns(chemistry)))
	if body != null and not body.mutations.is_empty():
		lines.append("mutations: %s" % ", ".join(body.mutations))
	if body != null and not body.exposure.is_empty():
		lines.append("exposure: %s" % _exposure_text(body))
	var mind: MindComponent = ECSManager.minds.get(row)
	if mind != null and mind.active_spell != &"":
		lines.append("bound spell: %s  (%d known runes)" % [
			mind.active_spell, mind.known_runes.size()
		])
	var perception: PerceptionComponent = ECSManager.perceptions.get(row)
	if perception != null:
		lines.append(
			"awareness %s  known targets %d" % [
				_enum_name(ECSEnums.AwarenessState, perception.awareness_state),
				perception.last_known_targets.size(),
			]
		)
	var job: JobComponent = ECSManager.jobs.get(row)
	if job != null:
		lines.append(
			"job %s  status %s  score %.2f" % [
				job.current_action,
				_enum_name(ECSEnums.JobStatus, job.status),
				job.score_at_claim,
			]
		)
	var lod: LoDComponent = ECSManager.lods.get(row)
	if lod != null:
		lines.append("LoD %s" % _enum_name(ECSEnums.LoD, lod.current_state))
	return "\n".join(lines)


## Tag list with `(Nf)` after anything that is counting down.
func _tags_with_countdowns(chemistry: ChemistryComponent) -> Array[String]:
	var now: int = GameLoopManager.micro_frames
	var out: Array[String] = []
	for tag in chemistry.active_tags:
		var left: int = chemistry.frames_left(tag, now)
		out.append(String(tag) if left < 0 else "%s(%df)" % [tag, left])
	return out


## Exposure as a percentage of the mutation threshold, because 47.3 means nothing on its own and
## "47%" says how close the next permanent change is.
func _exposure_text(body: BodyComponent) -> String:
	var parts: Array[String] = []
	for track in body.exposure:
		parts.append("%s %d%%" % [
			track,
			int(
				100.0 * float(body.exposure[track])
				/ WorldConstants.EXPOSURE_MUTATION_THRESHOLD
			),
		])
	return ", ".join(parts)


## Enums printed as raw integers are unreadable, and worse, they invite guesses: `awareness 0`
## was read during play-testing as the entity being asleep. It is UNAWARE, and there is no sleep
## state in Sprint 1 at all.
func _enum_name(enum_dict: Dictionary, value: int) -> String:
	for key in enum_dict:
		if enum_dict[key] == value:
			return "%s(%d)" % [key, value]
	return "UNKNOWN(%d)" % value
