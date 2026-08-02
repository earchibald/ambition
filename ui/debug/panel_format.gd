## Layout vocabulary for the debug panel.
##
## The panel used to print one flat line per fact — the equivalent of console output pasted onto
## the screen. Everything was the same size, the same colour, and the same importance, so finding
## the one number you cared about meant reading all of them. A diagnostic tool you have to parse
## is a diagnostic tool you stop opening.
##
## Three ideas do the work here:
##   * GROUPING. Related facts sit under a heading, so you look in a place rather than scanning.
##   * ALIGNMENT. Labels are padded to a fixed width, so values form a column your eye can run
##     down. This is why the panel font is monospace.
##   * COLOUR THAT MEANS SOMETHING. Green, amber and red are reserved for values measured against
##     a threshold. Nothing is coloured for decoration, or the colours stop carrying information.
class_name PanelFormat
extends RefCounted

const LABEL_WIDTH: int = 10

const HEADING := "8ab4f8"
const LABEL := "9aa3b2"
const VALUE := "e6e9ef"
const MUTED := "6f7789"
const GOOD := "7ee2a8"
const WARN := "ffd479"
const BAD := "ff7b72"
const ACCENT := "ffc65c"

## Fraction of a budget above which a value is amber rather than green.
const WARN_FRACTION: float = 0.75


static func heading(text: String) -> String:
	return "\n[color=#%s][b]%s[/b][/color]" % [HEADING, text.to_upper()]


## One aligned row. The label is padded rather than tab-separated because tabs in a RichTextLabel
## depend on tab stops nobody has configured.
static func row(label: String, value: String) -> String:
	return "  [color=#%s]%s[/color] %s" % [LABEL, label.rpad(LABEL_WIDTH), value]


static func plain(text: String) -> String:
	return "[color=#%s]%s[/color]" % [VALUE, text]


static func muted(text: String) -> String:
	return "[color=#%s]%s[/color]" % [MUTED, text]


static func accent(text: String) -> String:
	return "[color=#%s]%s[/color]" % [ACCENT, text]


static func good(text: String) -> String:
	return "[color=#%s]%s[/color]" % [GOOD, text]


static func bad(text: String) -> String:
	return "[color=#%s]%s[/color]" % [BAD, text]


## A measurement against a ceiling, coloured by how close it is. This is the whole reason colour
## is in the panel at all: "0.92 / 8.00 ms" tells you nothing at a glance, and a green 0.92 tells
## you everything.
static func against_budget(value: float, budget: float, unit: String) -> String:
	var text: String = "%.2f / %.2f %s" % [value, budget, unit]
	if budget <= 0.0:
		return plain(text)
	if value > budget:
		return "[color=#%s]%s  OVER[/color]" % [BAD, text]
	if value > budget * WARN_FRACTION:
		return "[color=#%s]%s[/color]" % [WARN, text]
	return "[color=#%s]%s[/color]" % [GOOD, text]


## A proportion drawn as a bar. Ten cells of block characters read faster than two numbers, and
## the numbers are kept beside it because a bar alone cannot tell you 99 from 100.
static func bar(current: float, maximum: float, width: int = 10) -> String:
	if maximum <= 0.0:
		return muted("n/a")
	var fraction: float = clampf(current / maximum, 0.0, 1.0)
	var filled: int = int(round(fraction * float(width)))
	var colour: String = GOOD
	if fraction < 0.25:
		colour = BAD
	elif fraction < 0.6:
		colour = WARN
	return "[color=#%s]%s[/color][color=#%s]%s[/color] %s" % [
		colour,
		"█".repeat(filled),
		MUTED,
		"░".repeat(width - filled),
		plain("%.0f/%.0f" % [current, maximum]),
	]


## Groups related counters onto one line as "12 movers · 3 hits", so a section is four rows rather
## than twelve. Zero-valued entries are kept: a zero that should not be zero is information, and
## hiding it is how "perceived 0" went unnoticed for a sprint.
static func tally(pairs: Array) -> String:
	var parts: Array[String] = []
	for pair in pairs:
		parts.append("%s %s" % [plain(str(pair[0])), muted(String(pair[1]))])
	return " · ".join(parts)
