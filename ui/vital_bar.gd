## A drawn vital bar: well, fill, tick marks, damage ghosting, and the strain dent.
##
## WHY DRAWN AND NOT TEXT. The HUD's health bar is the single most-read element on the screen,
## and block-character bars quantise to ten cells — a 3-damage hit on a 100-point bar is
## invisible. A drawn bar moves by the pixel, carries tick marks the player can COUNT damage
## against (25-unit steps), and can show the ghost of what was just lost.
##
## THE GHOST is the cheapest "feels finished" effect in the genre: on damage, the lost span
## lingers desaturated and drains over 0.6 s, so the magnitude of a hit registers even when the
## eye arrives late. Healing snaps the ghost instantly — anticipation is for losses only.
##
## THE STRAIN DENT. Casting strain is temporary damage to MAX stamina, not a spend of current
## stamina, so it is drawn as a dimmed amber region at the bar's right end: the part of you
## that is not available until you rest. A third bar would depict a resource that does not
## exist (decision #2 in the HUD plan).
##
## Reads nothing from the ECS. The HUD pushes values in; this Control only draws them, so a
## headless test can assert the geometry without a viewport.
class_name VitalBar
extends Control

## Seconds the ghost takes to drain the full bar width. Losses shorter than the full bar drain
## proportionally faster, which keeps the effect snappy for chip damage.
const GHOST_DRAIN_S: float = 0.6

## One tick every this many units of the resource, so a hit is countable, not just visible.
const TICK_EVERY_UNITS: float = 25.0

var label: String = ""
var fill_colour: Color = Color.WHITE

var _value: float = 0.0
var _maximum: float = 0.0
var _reserved: float = 0.0
var _ghost: float = 0.0


## The HUD's write path. `reserved` is the span at the top of the range that is temporarily
## unusable (strain); zero for bars that have no such concept.
func set_vital(value: float, maximum: float, reserved: float = 0.0) -> void:
	if value > _ghost:
		_ghost = value
	_value = value
	_maximum = maximum
	_reserved = reserved
	queue_redraw()


func _process(delta: float) -> void:
	if _ghost <= _value:
		return
	_ghost = ghost_step(_ghost, _value, _maximum, delta)
	queue_redraw()


## One frame of ghost decay: toward `value`, at a rate that would cross the whole bar in
## GHOST_DRAIN_S, never past it. Static so the timing law is assertable without a Control.
static func ghost_step(ghost: float, value: float, maximum: float, delta: float) -> float:
	if maximum <= 0.0:
		return value
	return maxf(value, ghost - maximum * delta / GHOST_DRAIN_S)


## Pixels of fill for a value, clamped into the well. Static for the same reason as above.
static func fill_px(value: float, maximum: float, width: float) -> float:
	if maximum <= 0.0:
		return 0.0
	return clampf(value / maximum, 0.0, 1.0) * width


## Where the tick marks sit, as fractions of the bar. Endpoints are excluded — a tick at 0 or
## at max marks nothing.
static func tick_fractions(maximum: float, step: float = TICK_EVERY_UNITS) -> Array[float]:
	var out: Array[float] = []
	if maximum <= 0.0 or step <= 0.0:
		return out
	var at: float = step
	while at < maximum - 0.001:
		out.append(at / maximum)
		at += step
	return out


func _draw() -> void:
	var well := StyleBoxFlat.new()
	well.bg_color = Color(0.043, 0.035, 0.027, 0.9)
	well.border_color = UITheme.PANEL_BORDER
	well.set_border_width_all(1)
	well.set_corner_radius_all(UITheme.RADIUS_PX - 1)
	draw_style_box(well, Rect2(Vector2.ZERO, size))

	var inner := Rect2(Vector2(1.0, 1.0), size - Vector2(2.0, 2.0))
	var width: float = inner.size.x

	# Ghost first, fill over it: the ghost is only ever the sliver past the live value.
	var ghost_px: float = fill_px(_ghost, _maximum, width)
	if ghost_px > 0.0:
		var ghost_colour := Color(fill_colour, 0.45).lerp(Color(0.5, 0.5, 0.5, 0.45), 0.5)
		draw_rect(Rect2(inner.position, Vector2(ghost_px, inner.size.y)), ghost_colour)
	var live_px: float = fill_px(_value, _maximum, width)
	if live_px > 0.0:
		draw_rect(Rect2(inner.position, Vector2(live_px, inner.size.y)), fill_colour)

	# The strain dent: the reserved span at the right end, dim amber.
	var reserved_px: float = fill_px(_reserved, _maximum, width)
	if reserved_px > 0.0:
		draw_rect(
			Rect2(
				inner.position + Vector2(width - reserved_px, 0.0),
				Vector2(reserved_px, inner.size.y)
			),
			Color(Color("#" + UITheme.STRAIN), 0.35)
		)

	# Dark ticks over the fill, pale ticks over the empty well — one colour vanishes against
	# the other's background, and a tick you cannot see at 75/100 defeats its purpose.
	for fraction in tick_fractions(_maximum):
		var x: float = inner.position.x + fraction * width
		var over_fill: bool = fraction * width <= live_px
		draw_line(
			Vector2(x, inner.position.y),
			Vector2(x, inner.position.y + inner.size.y),
			Color(0.0, 0.0, 0.0, 0.35) if over_fill else Color(1.0, 1.0, 1.0, 0.1)
		)

	_draw_text()


## Label inside-left, numbers inside-right, with the same 4 px outline every other HUD label
## wears — a 1 px shadow left "100/100" the thinnest text on screen over a full teal fill.
func _draw_text() -> void:
	var font: Font = ThemeDB.fallback_font
	var font_size: int = maxi(12, DebugFlags.overlay_font_size - 6)
	var baseline: float = (size.y + font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0
	var numbers: String = "%d/%d" % [int(round(_value)), int(round(_maximum - _reserved))]
	var numbers_x: float = size.x - 8.0 - font.get_string_size(
		numbers, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
	).x
	for entry in [[label, 8.0], [numbers, numbers_x]]:
		var text: String = entry[0]
		var x: float = entry[1]
		draw_string_outline(
			font, Vector2(x, baseline), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(0.0, 0.0, 0.0, 0.85)
		)
		draw_string(
			font, Vector2(x, baseline), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("#" + UITheme.TEXT_PRIMARY)
		)
