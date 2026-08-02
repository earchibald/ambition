## The player layer's one visual voice.
##
## Every player-facing panel — the HUD, the hover card, the pack, the Grimoire — draws from
## this file, so "consistent" is a property of the code rather than a discipline. The palette,
## the anatomy and the contrast maths are the beauty standard recorded in
## `docs/ui_information_architecture_and_hud_plan.md` Appendix A; a unit test asserts the
## contrast claims, because a palette that quietly drifts below AA is how accessibility rots.
##
## TWO VISUAL VOICES, ON PURPOSE. This warm parchment-on-charcoal is the GAME talking. The debug
## overlay keeps its cool monospace `PanelFormat` voice — the MACHINE talking — so the player
## always knows which layer they are reading. Do not "unify" them.
class_name UITheme
extends RefCounted

## Text tiers, as BBCode hex. Verified against the worst case: the panel colour composited over
## a bright fire pixel. PRIMARY 13.4:1, BODY 9.3:1, MUTED 5.1:1 — all pass WCAG AA for text.
const TEXT_PRIMARY := "ede3ce"
const TEXT_BODY := "c9bfa9"
const TEXT_MUTED := "968c7a"

## Vitals. Stamina is TEAL rather than the genre-reflex green: red/green collapses under
## deuteranopia, red/teal survives it by both hue and luminance. Strain is the amber dent.
const HEALTH := "c4453c"
const STAMINA := "2e9e8f"
const STRAIN := "c99a4b"
const MAGIC := "7b8ce0"

## Semantic states. Reserved for meaning, never decoration — same law as PanelFormat.
const DANGER := "ff6b4a"
const WARNING := "e8b44c"
const GOOD := "8fbc5c"

## Panel anatomy. One radius project-wide; mixed radii is the loudest "programmer art" tell.
const PANEL_BG := Color(0.086, 0.071, 0.055, 0.94)
const PANEL_BORDER := Color(0.227, 0.196, 0.165)
const RADIUS_PX: int = 3
const PAD_PX: int = 12
const GAP_PX: int = 8
## Margin between any UI element and the screen edge. One number, or the corners disagree.
const EDGE_PX: int = 12

## The log panel's alpha. Dimmer than the standard panel so the world stays readable through
## it, but no dimmer than keeps the event colours (worst: DANGER) at WCAG AA over a bright fire
## pixel — asserted by test. The muted stamps dip below AA there and are carried by their 4 px
## outline instead; that mechanism is deliberate and this comment is its record.
const LOG_BG_ALPHA: float = 0.82

## Cells in a text-drawn bar (the pack's capacity rows). Matches the hover card's ten.
const TEXT_BAR_CELLS: int = 10


## The standard player panel. `summoned` panels (pack, Grimoire) get a drop shadow so they
## separate from the world; HUD chrome does not — it belongs to the frame, not the scene.
static func panel_style(summoned: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = PANEL_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(RADIUS_PX)
	style.set_content_margin_all(PAD_PX)
	if summoned:
		style.shadow_size = 8
		style.shadow_color = Color(0.0, 0.0, 0.0, 0.4)
		style.shadow_offset = Vector2(0.0, 2.0)
	return style


## A quieter panel for the running log: the world must stay readable through it.
static func log_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = panel_style()
	style.bg_color = Color(PANEL_BG.r, PANEL_BG.g, PANEL_BG.b, LOG_BG_ALPHA)
	style.set_content_margin_all(GAP_PX)
	return style


## The 1 px top-edge highlight that turns a flat rectangle into material. StyleBoxFlat has one
## border colour, so the highlight is drawn onto the panel after its stylebox.
static func decorate(panel: Control) -> void:
	panel.draw.connect(func() -> void:
		var width: float = panel.size.x - 2.0 * float(RADIUS_PX)
		if width <= 0.0:
			return
		panel.draw_line(
			Vector2(float(RADIUS_PX), 1.0),
			Vector2(float(RADIUS_PX) + width, 1.0),
			Color(1.0, 1.0, 1.0, 0.05)
		)
	)


## The shared monospace stack, for columnar data only (the Grimoire list, the debug panel).
## Prose never uses it — proportional reads faster.
static func mono_font() -> SystemFont:
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(
		["JetBrains Mono", "SF Mono", "Menlo", "DejaVu Sans Mono", "Consolas", "monospace"]
	)
	return mono


## ALL-CAPS with thin-space (U+2009) tracking: zero-asset gravitas, straight from the genre.
## The spacing character is typed into the string because BBCode has no letter-spacing tag.
static func title(text: String) -> String:
	var spaced: String = " ".join(text.to_upper().split(""))
	return "[b][color=#%s]%s[/color][/b]" % [TEXT_PRIMARY, spaced]


static func primary(text: String) -> String:
	return "[color=#%s]%s[/color]" % [TEXT_PRIMARY, text]


static func body(text: String) -> String:
	return "[color=#%s]%s[/color]" % [TEXT_BODY, text]


static func muted(text: String) -> String:
	return "[color=#%s]%s[/color]" % [TEXT_MUTED, text]


## A proportion drawn as text cells, warm-palette twin of `PanelFormat.bar`. The numbers ride
## beside it because a bar alone cannot tell 99 from 100.
static func bar(current: float, maximum: float, colour_hex: String) -> String:
	if maximum <= 0.0:
		return muted("n/a")
	var fraction: float = clampf(current / maximum, 0.0, 1.0)
	var filled: int = int(round(fraction * float(TEXT_BAR_CELLS)))
	return "[color=#%s]%s[/color][color=#%s]%s[/color] %s" % [
		colour_hex,
		"█".repeat(filled),
		TEXT_MUTED,
		"░".repeat(TEXT_BAR_CELLS - filled),
		body("%.1f/%.1f" % [current, maximum]),
	]


## WCAG 2.x contrast ratio. Lives here rather than in a test so the palette's own file carries
## the maths its guarantees depend on.
static func contrast_ratio(foreground: Color, background: Color) -> float:
	var lighter: float = maxf(_luminance(foreground), _luminance(background))
	var darker: float = minf(_luminance(foreground), _luminance(background))
	return (lighter + 0.05) / (darker + 0.05)


## The panel colour as actually seen: alpha-composited over a world pixel. `alpha` defaults to
## the standard panel; pass LOG_BG_ALPHA to test the log surface.
static func composited_panel_over(world: Color, alpha: float = PANEL_BG.a) -> Color:
	return Color(
		PANEL_BG.r * alpha + world.r * (1.0 - alpha),
		PANEL_BG.g * alpha + world.g * (1.0 - alpha),
		PANEL_BG.b * alpha + world.b * (1.0 - alpha)
	)


static func _luminance(colour: Color) -> float:
	return 0.2126 * _linear(colour.r) + 0.7152 * _linear(colour.g) + 0.0722 * _linear(colour.b)


static func _linear(channel: float) -> float:
	if channel <= 0.04045:
		return channel / 12.92
	return pow((channel + 0.055) / 1.055, 2.4)
