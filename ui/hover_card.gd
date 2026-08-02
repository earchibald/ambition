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

## Pixels between the pointer and the card's near corner.
const CURSOR_OFFSET := Vector2(18.0, 18.0)
const EDGE_MARGIN_PX: float = 8.0

## Cells in the little health bar. Short enough to read at a glance as a shape rather than a
## number, which is the whole point of drawing one.
const BAR_CELLS: int = 10

## Frames between content refreshes while the pointer stays on one target. The card must stay
## live — a burning rat loses health continuously — but rebuilding BBCode at 60 Hz to redraw the
## same string is waste. Six frames is a tenth of a second and reads as instant.
const REFRESH_EVERY_FRAMES: int = 6

@export var camera_path: NodePath = NodePath("../CameraRig/Camera3D")
@export var overlay_path: NodePath = NodePath("../DebugOverlay")
@export var grimoire_path: NodePath = NodePath("../GrimoirePanel")

var _panel: PanelContainer = null
var _label: RichTextLabel = null
var _camera: Camera3D = null
var _overlay: Node = null
var _grimoire: Node = null
var _shown_handle: int = EH.INVALID
var _frames_since_refresh: int = 0


func _ready() -> void:
	_build()
	_camera = get_node_or_null(camera_path) as Camera3D
	_overlay = get_node_or_null(overlay_path)
	_grimoire = get_node_or_null(grimoire_path)


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.09, 0.92)
	style.border_color = Color(0.35, 0.42, 0.55, 0.95)
	style.set_border_width_all(1)
	style.set_content_margin_all(9)
	style.set_corner_radius_all(4)
	_panel.add_theme_stylebox_override("panel", style)
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
		"[b][color=#%s]%s[/color][/b]" % [PanelFormat.VALUE, EntityCard.title(row)]
	]
	var kind: String = EntityCard.kind_line(row)
	var standing: Dictionary = EntityCard.standing(row)
	if kind == "" and standing.is_empty():
		pass
	elif standing.is_empty():
		lines.append("[color=#%s]%s[/color]" % [PanelFormat.MUTED, kind])
	else:
		lines.append("[color=#%s]%s[/color]  [color=#%s]%s[/color]" % [
			PanelFormat.MUTED, kind, String(standing["colour"]), String(standing["text"])
		])
	for vital in EntityCard.vitals(row):
		lines.append(_vital_line(vital))
	var conditions: Array[String] = EntityCard.conditions(row)
	if not conditions.is_empty():
		lines.append(
			"[color=#%s]%s[/color]" % [PanelFormat.ACCENT, ", ".join(conditions)]
		)
	var facts: Array[String] = EntityCard.facts(row)
	if not facts.is_empty():
		lines.append("[color=#%s]%s[/color]" % [PanelFormat.MUTED, "  ".join(facts)])
	return "\n".join(lines)


static func _vital_line(vital: Dictionary) -> String:
	var value: float = float(vital["value"])
	var maximum: float = float(vital["max"])
	var colour: String = EntityCard.vital_colour(value, maximum)
	var filled: int = 0
	if maximum > 0.0:
		filled = clampi(int(round(value / maximum * float(BAR_CELLS))), 0, BAR_CELLS)
	var bar: String = "%s%s" % ["=".repeat(filled), ".".repeat(BAR_CELLS - filled)]
	return "[color=#%s]%s[/color] [color=#%s]%s  %d/%d[/color]" % [
		PanelFormat.LABEL, String(vital["label"]), colour, bar, int(round(value)),
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
