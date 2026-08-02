## The pack: what you are carrying, in your own words. Summoned with `I`, dismissed with `I`
## or `Esc`.
##
## THE INVENTORY WAS REAL AND INVISIBLE. `E` has moved items into `InventoryComponent` since
## Sprint 1 — volume-limited, mass-tracked, speed-sapping — and no surface anywhere showed what
## you held. The only evidence you owned anything was walking slower.
##
## AN AUTO-SORTED LIST, NEVER A GRID. The ui_ux spec §5 is explicit: the computer handles the
## spatial math, the player never plays Tetris. Heaviest first, because mass is the number that
## is costing you something.
##
## READ-ONLY, AND IT SAYS SO. There is no DROP intent in the ECS yet, so the panel states the
## limit on its face rather than growing a button that cannot work. When DROP exists, rows
## become actionable.
##
## IT NEVER WRITES ECS STATE, and it never eats a click it does not own (`wants_mouse`).
class_name PackPanel
extends CanvasLayer

## Content refresh cadence while open. Item counts change on pickup (signal-driven) and almost
## never otherwise; this is a safety net, not the update path.
const REFRESH_INTERVAL_S: float = 0.5

var _panel: PanelContainer = null
var _label: RichTextLabel = null
var _open: bool = false
var _accumulator: float = 0.0


func _ready() -> void:
	_build()
	ECSEvents.item_taken.connect(_on_taken)


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", UITheme.panel_style(true))
	UITheme.decorate(_panel)
	_panel.visible = false
	add_child(_panel)

	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# TWO voices in one panel, on purpose: the stack rows and capacity bars are columnar data
	# and render through [code] in monospace; the title and the prose lines stay proportional —
	# the game talking, not the machine (the theme's two-voice rule).
	_label.add_theme_font_override("mono_font", UITheme.mono_font())
	_panel.add_child(_label)


## True while the panel is up, so the input bridge and the hover card can yield to it.
func is_open() -> bool:
	return _open


## Closed from outside — the input bridge dismisses on a click-away.
func close() -> void:
	_open = false
	_panel.visible = false


## True when a click belongs to this panel rather than to the world behind it.
func wants_mouse() -> bool:
	if not _open or _panel == null:
		return false
	return _panel.get_global_rect().has_point(_panel.get_global_mouse_position())


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if event.is_action(&"inventory"):
		_open = not _open
		_panel.visible = _open
		_refresh()
		get_viewport().set_input_as_handled()
		return
	if _open and event.is_action(&"cancel"):
		close()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not _open:
		return
	_accumulator += delta
	if _accumulator < REFRESH_INTERVAL_S:
		return
	_accumulator = 0.0
	_refresh()


func _on_taken(taker: int, _item: int, _reason: StringName) -> void:
	if _open and taker == ECSManager.player_handle():
		_refresh()


func _refresh() -> void:
	if not _open or _label == null:
		return
	var row: int = ECSManager.resolve(ECSManager.player_handle())
	if row < 0:
		return
	_label.add_theme_font_size_override("normal_font_size", DebugFlags.overlay_font_size)
	_label.add_theme_font_size_override("bold_font_size", DebugFlags.overlay_font_size)
	_label.text = "\n".join(compose(row))
	_panel.reset_size()
	_place()


func _place() -> void:
	var view: Vector2 = Vector2(get_viewport().get_visible_rect().size)
	var size: Vector2 = _panel.get_combined_minimum_size()
	_panel.position = ((view - size) / 2.0).max(Vector2(12.0, 12.0))


## The whole panel, as BBCode lines. Static and row-only so a headless test can assert it.
static func compose(row: int) -> Array[String]:
	var inventory: InventoryComponent = ECSManager.inventories.get(row)
	var container: ContainerComponent = ECSManager.containers.get(row)
	var body: BodyComponent = ECSManager.bodies.get(row)
	var out: Array[String] = [
		"%s   %s" % [UITheme.title("Pack"), UITheme.muted("[I] or [Esc] closes")]
	]
	if inventory == null or container == null or body == null:
		out.append(UITheme.muted("you have no way to carry anything"))
		return out

	out.append("")
	for line in _stack_lines(inventory):
		out.append(line)
	out.append("")
	out.append("[code]%s %s[/code]" % [
		UITheme.body("space".rpad(6)),
		UITheme.bar(
			inventory.total_volume_used / 1000.0, container.capacity_cm3 / 1000.0, UITheme.MAGIC
		) + UITheme.muted(" L"),
	])
	var multiplier: float = InventorySystem.speed_multiplier(row)
	var load_line: String = "[code]%s %s[/code]" % [
		UITheme.body("load".rpad(6)),
		UITheme.bar(inventory.total_mass_kg, body.carry_capacity_kg(), UITheme.STRAIN)
		+ UITheme.muted(" kg"),
	]
	if multiplier < 0.99:
		load_line += "  [color=#%s]pace %d%%[/color]" % [
			UITheme.WARNING, int(round(multiplier * 100.0))
		]
	out.append(load_line)
	out.append("")
	out.append(UITheme.muted("E takes things from the world. Dropping is not built yet."))
	return out


## One row per held stack, heaviest first: name, mass, litres.
static func _stack_lines(inventory: InventoryComponent) -> Array[String]:
	var stacks: Array[Dictionary] = []
	for handle in inventory.held_items:
		var item_row: int = ECSManager.resolve(handle)
		if item_row < 0:
			continue
		var physical: PhysicalPropertyComponent = ECSManager.physicals.get(item_row)
		stacks.append({
			"name": EntityCard.title(item_row),
			"mass": 0.0 if physical == null else physical.stack_mass_kg(),
			"litres": 0.0 if physical == null else physical.stack_volume_cm3() / 1000.0,
		})
	if stacks.is_empty():
		return [UITheme.muted("  nothing — E takes what is under the cursor")] as Array[String]
	stacks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["mass"]) > float(b["mass"])
	)
	var out: Array[String] = []
	for stack in stacks:
		out.append("[code]  %s %s %s[/code]" % [
			UITheme.primary(String(stack["name"]).rpad(22)),
			UITheme.body("%6.1f kg" % float(stack["mass"])),
			UITheme.muted("%6.1f L" % float(stack["litres"])),
		])
	return out
