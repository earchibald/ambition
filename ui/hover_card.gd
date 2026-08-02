## A player-facing tooltip: point at something, read what it is.
##
## THE PROBLEM IT SOLVES. Until now the only way to identify anything on the playfield was `Tab`,
## which selects an entity and appends a raw component dump to the debug panel. That is a
## programmer's tool. A player looking at a small red box needs to know it is a rat, that it is
## on fire, and that it is nearly dead — without pressing a key, without opening a panel, and
## without having learned that `MAT_BIOMASS` and `Volatile_Gas` are things.
##
## NOT A DEBUG SURFACE. It is not on the `F1` page cycle, it is not gated behind `DebugFlags`, and
## it says nothing about rows, handles, masks, or tick counters. `EntityCard` decides the words;
## this file only draws them and decides when to get out of the way.
##
## PROPORTIONAL FONT, DELIBERATELY. Every other panel in the build is monospace because it prints
## aligned columns. This one prints a name and a short phrase, where a proportional face is
## simply easier to read — so it does not inherit the debug panel's typography.
##
## IT NEVER EATS INPUT. Every Control here is `MOUSE_FILTER_IGNORE`, and the card hides itself
## whenever the debug overlay or the Grimoire wants the pointer. A tooltip that swallows a click
## is worse than no tooltip.
class_name HoverCard
extends CanvasLayer

## Pixels between the pointer and the card's near corner. On the 4/8/12 grid, like everything.
const CURSOR_OFFSET := Vector2(16.0, 16.0)
const EDGE_MARGIN_PX: float = 12.0

## Frames between content refreshes while the pointer stays on one target. The card must stay
## live — a burning rat loses health continuously — but rebuilding BBCode at 60 Hz to redraw the
## same string is waste. Six frames is a tenth of a second and reads as instant.
const REFRESH_EVERY_FRAMES: int = 6

@export var camera_path: NodePath = NodePath("../CameraRig/Camera3D")
@export var overlay_path: NodePath = NodePath("../DebugOverlay")
@export var grimoire_path: NodePath = NodePath("../GrimoirePanel")
@export var pack_path: NodePath = NodePath("../PackPanel")

var _panel: PanelContainer = null
var _label: RichTextLabel = null
var _camera: Camera3D = null
var _overlay: Node = null
var _grimoire: Node = null
var _pack: Node = null
var _shown_handle: int = EH.INVALID
var _frames_since_refresh: int = 0


func _ready() -> void:
	_build()
	_camera = get_node_or_null(camera_path) as Camera3D
	_overlay = get_node_or_null(overlay_path)
	_grimoire = get_node_or_null(grimoire_path)
	_pack = get_node_or_null(pack_path)


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", UITheme.panel_style())
	UITheme.decorate(_panel)
	_panel.visible = false
	add_child(_panel)

	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("normal_font_size", DebugFlags.overlay_font_size)
	_label.add_theme_font_size_override("bold_font_size", DebugFlags.overlay_font_size + 2)
	# The bar span renders through [code], so the block cells land in a face that stacks them
	# evenly. Prose stays proportional; only the bar is columnar.
	_label.add_theme_font_override("mono_font", UITheme.mono_font())
	_panel.add_child(_label)


func _process(_delta: float) -> void:
	var row: int = _target_row()
	if row < 0:
		_hide()
		return
	var handle: int = ECSManager.handle_of(row)
	_frames_since_refresh += 1
	if handle != _shown_handle or _frames_since_refresh >= REFRESH_EVERY_FRAMES:
		_shown_handle = handle
		_frames_since_refresh = 0
		# Re-applied on refresh rather than only at build, so `=`/`-` reach this card too.
		_label.add_theme_font_size_override("normal_font_size", DebugFlags.overlay_font_size)
		_label.add_theme_font_size_override("bold_font_size", DebugFlags.overlay_font_size + 2)
		_label.text = card_text(row)
	_panel.visible = true
	_place()


## The row under the pointer, or -1 when the card should not be showing at all.
##
## The player is NOT excluded, unlike the `Tab` pick: "what is my own health" is a fair question
## to answer by pointing at yourself, and the interaction reasons for excluding the actor from a
## reach query do not apply to a tooltip.
func _target_row() -> int:
	if not World.booted or _camera == null or _panel == null:
		return -1
	if _overlay != null and _overlay.has_method("wants_mouse") and _overlay.wants_mouse():
		return -1
	if _grimoire != null and _grimoire.has_method("is_open") and _grimoire.is_open():
		return -1
	if _pack != null and _pack.has_method("is_open") and _pack.is_open():
		return -1
	var mouse: Vector2 = _camera.get_viewport().get_mouse_position()
	var handle: int = GameLoopManager.picking.cursor_target(
		_camera.project_ray_origin(mouse),
		_camera.project_ray_normal(mouse),
		GameLoopManager.spatial_hash,
		World.sampler(),
		-1
	)
	return ECSManager.resolve(handle)


## The whole card, as BBCode. Static and row-only so a headless test can assert it.
static func card_text(row: int) -> String:
	var lines: Array[String] = [
		"[b][color=#%s]%s[/color][/b]" % [UITheme.TEXT_PRIMARY, EntityCard.title(row)]
	]
	var kind: String = EntityCard.kind_line(row)
	var standing: Dictionary = EntityCard.standing(row)
	if kind == "" and standing.is_empty():
		pass
	elif standing.is_empty():
		lines.append("[color=#%s]%s[/color]" % [UITheme.TEXT_MUTED, kind])
	else:
		lines.append("[color=#%s]%s[/color]  [color=#%s]%s[/color]" % [
			UITheme.TEXT_MUTED, kind, String(standing["colour"]), String(standing["text"])
		])
	for vital in EntityCard.vitals(row):
		lines.append(_vital_line(vital))
	var conditions: Array[String] = EntityCard.conditions(row)
	if not conditions.is_empty():
		lines.append(
			"[color=#%s]%s[/color]" % [UITheme.WARNING, ", ".join(conditions)]
		)
	var facts: Array[String] = EntityCard.facts(row)
	if not facts.is_empty():
		lines.append("[color=#%s]%s[/color]" % [UITheme.TEXT_MUTED, "  ".join(facts)])
	return "\n".join(lines)


## Solid block cells, not `=` and `.` — typewriter glyphs on the most-read element were the
## loudest programmer-art tell in the build's own beauty review.
static func _vital_line(vital: Dictionary) -> String:
	var value: float = float(vital["value"])
	var maximum: float = float(vital["max"])
	var colour: String = EntityCard.vital_colour(value, maximum)
	var cells: int = UITheme.TEXT_BAR_CELLS
	var filled: int = 0
	if maximum > 0.0:
		filled = clampi(int(round(value / maximum * float(cells))), 0, cells)
	var bar: String = "[code][color=#%s]%s[/color][color=#%s]%s[/color][/code]" % [
		colour, "█".repeat(filled), UITheme.TEXT_MUTED, "░".repeat(cells - filled)
	]
	return "[color=#%s]%s[/color] %s [color=#%s]%d/%d[/color]" % [
		UITheme.TEXT_BODY, String(vital["label"]), bar, colour, int(round(value)),
		int(round(maximum))
	]


## Follows the pointer, and flips to the other side rather than sliding off the screen.
func _place() -> void:
	var viewport: Vector2 = Vector2(get_viewport().get_visible_rect().size)
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var size: Vector2 = _panel.get_combined_minimum_size()
	var at: Vector2 = mouse + CURSOR_OFFSET
	if at.x + size.x > viewport.x - EDGE_MARGIN_PX:
		at.x = mouse.x - CURSOR_OFFSET.x - size.x
	if at.y + size.y > viewport.y - EDGE_MARGIN_PX:
		at.y = mouse.y - CURSOR_OFFSET.y - size.y
	_panel.position = at.max(Vector2(EDGE_MARGIN_PX, EDGE_MARGIN_PX))


func _hide() -> void:
	if _panel != null:
		_panel.visible = false
	_shown_handle = EH.INVALID
