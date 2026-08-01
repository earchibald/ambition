## The Grimoire (Sprint 4, scope doc: "spell compiler PLUS the Grimoire UI that fronts it").
##
## THIS EXISTS BECAUSE THE COMPILER WOULD OTHERWISE BE UNREACHABLE. The Sprint 4 roadmap says
## "No UI yet, just data validation", and every previous sprint in this project has shipped at
## least one system that was implemented, tested, and had no route in from the keyboard —
## `resolve_fall`, `DebugOverlay.select_row`, `on_timeout`, `report_crime`. The scope document
## assigns the Grimoire UI to this sprint, so building it is following the spec rather than
## exceeding it, and it is what makes the rest of the sprint play-testable at all.
##
## WHAT IT IS NOT: the node-graph editor, the Dry Run hologram's 3D SubViewport, and the
## translation-cipher minigame from `inventory_and_grimoire_mechanics_specification.md` §2. Those
## are a real UI sprint. This is a keyboard-driven list at debug-panel fidelity, and it is
## declared as such in RUNNING.md rather than left for a play-tester to discover.
##
## IT NEVER WRITES ECS STATE. Binding goes out as an `ActionIntent.BIND` and comes back as an
## `ECSEvents.spell_bound` signal, exactly like every other UI-to-sim path (Prime Directive). The
## live preview is the one direct call, and it is to `SpellCompilerSystem.compile`, which is pure
## — it reads a MindComponent and returns a value. That IS the "Dry Run": zero Strain, no
## materials, and the same code the real compile runs, rather than a second implementation that
## can disagree with it.
class_name GrimoirePanel
extends CanvasLayer

## Digit keys pick runes. Nine is what fits on a keyboard row and comfortably exceeds the
## MAX_SPELL_RUNES limit of 8, so the list is never the thing that constrains a spell.
const MAX_LISTED: int = 9

var _panel: PanelContainer = null
var _label: RichTextLabel = null
var _selected: Array[StringName] = []
var _last_result: String = ""
var _open: bool = false


func _ready() -> void:
	_build()
	ECSEvents.spell_bound.connect(_on_bound)
	ECSEvents.spell_cast.connect(_on_cast)
	_refresh()


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.position = Vector2(12, 12)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.04, 0.09, 0.88)
	style.border_color = Color(0.62, 0.5, 0.85, 0.95)
	style.set_border_width_all(1)
	style.set_content_margin_all(8)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.visible = false
	add_child(_panel)

	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Monospace for the same reason the debug overlay uses it: these are aligned columns, and a
	# proportional face shreds them.
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(
		["JetBrains Mono", "SF Mono", "Menlo", "DejaVu Sans Mono", "Consolas", "monospace"]
	)
	for role in ["normal_font", "bold_font", "italics_font", "mono_font"]:
		_label.add_theme_font_override(role, mono)
	_label.add_theme_font_size_override("normal_font_size", DebugFlags.overlay_font_size)
	_label.add_theme_font_size_override("bold_font_size", DebugFlags.overlay_font_size)
	_panel.add_child(_label)


## True while the panel is up, so the input bridge can ignore a click that belongs to it.
func is_open() -> bool:
	return _open


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if event.is_action(&"grimoire"):
		_open = not _open
		_panel.visible = _open
		_refresh()
		get_viewport().set_input_as_handled()
		return
	if not _open or not (event is InputEventKey):
		return
	_handle_key(event as InputEventKey)


func _handle_key(key: InputEventKey) -> void:
	var code: int = key.physical_keycode
	if code >= KEY_1 and code <= KEY_9:
		_toggle(code - KEY_1)
	elif code == KEY_ENTER or code == KEY_KP_ENTER:
		_request_bind()
	elif code == KEY_BACKSPACE:
		_selected.clear()
		_refresh()
	elif code == KEY_ESCAPE:
		_open = false
		_panel.visible = false
	else:
		return
	get_viewport().set_input_as_handled()


## Toggling is what makes an ordering mistake cheap to undo. Selecting an already-selected rune
## removes it rather than adding a duplicate, because two copies of `On_Cast` is never what a
## number key press meant.
func _toggle(index: int) -> void:
	var runes: Array[StringName] = _known()
	if index < 0 or index >= runes.size():
		return
	var rune_id: StringName = runes[index]
	if _selected.has(rune_id):
		_selected.erase(rune_id)
	else:
		_selected.append(rune_id)
	_refresh()


func _request_bind() -> void:
	var row: int = ECSManager.resolve(ECSManager.player_handle())
	if row < 0:
		return
	# A REQUEST, not a write. The compiler runs on the next Micro tick and answers on the bus.
	ECSManager.push_intent(row, ActionIntent.bind(_selected))


func _known() -> Array[StringName]:
	var mind: MindComponent = _mind()
	if mind == null:
		return [] as Array[StringName]
	var out: Array[StringName] = []
	for rune_id in mind.known_runes:
		out.append(rune_id)
	out.sort()
	if out.size() > MAX_LISTED:
		out.resize(MAX_LISTED)
	return out


func _mind() -> MindComponent:
	var row: int = ECSManager.resolve(ECSManager.player_handle())
	return null if row < 0 else ECSManager.minds.get(row)


func _on_bound(_caster: int, spell_id: StringName, ok: bool, reason: StringName) -> void:
	_last_result = (
		"[color=#8fe08f]bound %s[/color]" % spell_id
		if ok
		else "[color=#e08f8f]refused — %s[/color]" % reason
	)
	_refresh()


func _on_cast(_caster: int, spell_id: StringName, strain: float) -> void:
	_last_result = "[color=#8fbfe0]cast %s (%.1f strain)[/color]" % [spell_id, strain]
	_refresh()


func _refresh() -> void:
	if not _open or _label == null:
		return
	_label.text = "\n".join(_compose())
	_panel.reset_size()


func _compose() -> Array[String]:
	var mind: MindComponent = _mind()
	var out: Array[String] = []
	out.append("[b]GRIMOIRE[/b]   [1-9] add/remove   [Enter] bind   [Backspace] clear   [B] close")
	if mind == null:
		out.append("[color=#e08f8f]no mind to read[/color]")
		return out

	out.append("")
	out.append("[b]known runes[/b]")
	var runes: Array[StringName] = _known()
	for i in runes.size():
		var rune_id: StringName = runes[i]
		var mark: String = "*" if _selected.has(rune_id) else " "
		out.append("  %d %s %-18s %-8s cost %d" % [
			i + 1, mark, rune_id, RuneLibrary.kind_of(rune_id),
			RuneLibrary.complexity_of(rune_id),
		])

	out.append("")
	out.append("[b]this spell[/b]")
	out.append("  runes: %s" % ("<none>" if _selected.is_empty() else " + ".join(_selected)))
	out.append(
		"  budget: %.1f (Rune_Stability %d)" % [
			SpellCompilerSystem.complexity_budget(mind), mind.insight_in(&"Rune_Stability")
		]
	)
	out.append_array(_preview(mind))
	if _last_result != "":
		out.append("")
		out.append("  " + _last_result)
	return out


## THE DRY RUN. Calls the pure compiler, so what is shown here is what a Bind would produce —
## including which geometric caps would fire, which is the "WARN: Radius > 15m" the grimoire spec
## asks for. Nothing is spent and nothing is written.
func _preview(mind: MindComponent) -> Array[String]:
	var out: Array[String] = []
	if _selected.is_empty():
		return out
	var compiler := SpellCompilerSystem.new()
	var result: Dictionary = compiler.compile(_selected, mind)
	if not result["ok"]:
		out.append("  [color=#e08f8f]will not compile — %s[/color]" % result["reason"])
		return out
	var spell: CompiledSpell = result["spell"]
	out.append("  [color=#8fe08f]%s[/color]" % spell.describe())
	if spell.was_capped():
		out.append(
			"  [color=#e0d08f]WARN: capped — %s[/color]" % ", ".join(spell.caps_applied)
		)
	return out
