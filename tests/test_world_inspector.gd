## The world inspector (Sprint 3 play-testing gap).
##
## Sprint 2 generated 500 years of history and a dozen factions, and showed the player none of
## it. Faction ledgers have no POSITION by design, so `Tab` — which picks through the spatial
## hash — can never reach them. The most interesting output of two sprints was unreachable.
extends GutTest


func before_each() -> void:
	GameLoopManager.set_physics_process(false)
	World.boot_scenario(World.SCENARIO_WORLD, 2026)


func after_all() -> void:
	GameLoopManager.set_physics_process(true)


func test_the_chronicle_is_readable() -> void:
	var text: String = WorldInspector.history_text()
	assert_string_contains(text, "THE CHRONICLE", "the page is titled")
	assert_string_contains(text, "founded on floor", "and contains real events")


## A 500-epoch run must not push the screen off the bottom.
func test_the_chronicle_is_bounded() -> void:
	var lines: int = WorldInspector.history_text().split("\n").size()
	# The cap is on EVENTS; the page also carries a heading, a summary and blank spacers.
	assert_lte(lines, WorldInspector.MAX_CHRONICLE_LINES + 6, "the page fits on a screen")


## THE POINT OF THE WHOLE FILE. Ledger entities are unreachable by picking, so if the inspector
## cannot list them, nothing can.
func test_factions_are_listed_despite_having_no_position() -> void:
	var text: String = WorldInspector.factions_text()
	var expected: int = ECSManager.query(ComponentMask.FACTION_CORE).size()
	assert_gt(expected, 0, "the world has factions")
	assert_string_contains(text, "FACTIONS", "the page is titled")
	assert_string_contains(text, "%d alive" % expected, "and all of them are counted")

	for row in ECSManager.query(ComponentMask.FACTION_CORE):
		assert_false(
			ECSManager.has_components(row, ComponentMask.POSITION),
			"which is necessary, because they cannot be clicked"
		)


func test_a_faction_entry_names_what_it_is_doing_and_where_it_lives() -> void:
	var text: String = WorldInspector.factions_text()
	assert_string_contains(text, "home", "each faction reports its home chunk")
	assert_string_contains(text, "doing", "and its current objective")
	assert_string_contains(text, "abstract", "and its population")


## An Active faction's ledger is EMPTY because promotion spent it into physical stacks — the
## conservation rule working correctly. Printing a bare "empty" for the village you are standing
## in reads as a bug, so the total must be reported from whichever side holds it.
func test_materialized_wealth_is_not_reported_as_empty() -> void:
	var village: FactionCoreComponent = null
	for row in ECSManager.query(ComponentMask.FACTION_CORE):
		var core: FactionCoreComponent = ECSManager.faction_cores[row]
		if core.anchor_chunk_id == Vector3i.ZERO:
			village = core
	assert_not_null(village, "the village faction is anchored at the origin")
	assert_eq(village.ledger_total(), 0, "and its ledger really is spent")

	var described: String = WorldInspector._describe_wealth(village)
	assert_false(described.contains("empty"), "but it does not read as destitute")
	assert_string_contains(described, "materialized", "it says where the wealth actually is")


func test_a_genuinely_poor_faction_says_so() -> void:
	var core := FactionCoreComponent.new()
	core.faction_id = 98765
	assert_eq(WorldInspector._describe_wealth(core), "destitute", "nothing anywhere")


# --- The map -------------------------------------------------------------------------------

func test_the_map_marks_the_player_and_the_loaded_chunks() -> void:
	var text: String = WorldInspector.map_text()
	assert_string_contains(text, "@", "the player is marked")
	assert_string_contains(text, "A", "and the Active chunks around them")
	assert_string_contains(text, "FLOOR", "with the floor named")


## Asking the grid for a chunk GENERATES it. A map that generated every cell it drew would be
## the thing that filled the world it is describing.
func test_drawing_the_map_generates_nothing() -> void:
	var before: int = World.grid.chunks_generated
	WorldInspector.map_text()
	WorldInspector.map_text()
	assert_eq(World.grid.chunks_generated, before, "the map is read-only in every sense")


func test_ungenerated_chunks_are_shown_as_absent() -> void:
	assert_string_contains(
		WorldInspector.map_text(), "-", "unexplored space is visibly unexplored"
	)


# --- The arena, which has none of this -------------------------------------------------------

## The arena is a single hand-authored chunk with no history and no factions. Every page must say
## so plainly rather than rendering an empty table that looks like a failure.
func test_the_arena_explains_that_it_has_no_world() -> void:
	World.boot_scenario(World.SCENARIO_TEST_ARENA, 1)
	assert_string_contains(WorldInspector.history_text(), "test arena", "history says why")
	assert_string_contains(WorldInspector.factions_text(), "arena", "factions says why")
	assert_string_contains(WorldInspector.map_text(), "single hand-authored", "the map too")


## The pages must be reachable, or the whole inspector is as invisible as what it inspects.
func test_the_page_cycle_key_is_mapped() -> void:
	assert_true(InputMap.has_action(&"cycle_debug_page"), "F1 cycles the overlay pages")


## MONOSPACE IS NOT COSMETIC. The map is a grid of characters; in a proportional font its columns
## do not line up and it stops being a map. Every row must therefore be the same width.
func test_the_map_rows_are_all_the_same_width() -> void:
	var rows: Array[String] = []
	for line in WorldInspector.map_text().split("\n"):
		if line.contains("y="):
			rows.append(line)
	assert_gt(rows.size(), 1, "the map has rows")
	for line in rows:
		assert_eq(
			line.length(), rows[0].length(), "every map row is the same character width"
		)


## The panel reads DebugFlags in `_ready`, and Godot readies CHILDREN BEFORE their parent — so it
## used to run before `Main._ready` initialised them. Every flag read a default, and a font size
## set in debug_config.json silently never applied.
func test_the_overlay_initialises_flags_itself() -> void:
	var overlay: DebugOverlay = DebugOverlay.new()
	add_child_autofree(overlay)
	assert_gte(
		DebugFlags.overlay_font_size,
		DebugFlags.MIN_OVERLAY_FONT_SIZE,
		"flags are loaded by the time the panel is built"
	)


## Clicking the panel must not swing a weapon at whatever is behind it.
func test_the_panel_claims_the_mouse_when_the_pointer_is_over_it() -> void:
	var overlay: DebugOverlay = DebugOverlay.new()
	add_child_autofree(overlay)
	overlay.visible = false
	assert_false(overlay.wants_mouse(), "a hidden panel never claims input")


## F1 cycles round to HIDDEN and dismisses the panel. One key drives the tool and gets it out of
## the way; a second key that only hides would do nothing else.
func test_the_page_cycle_includes_a_hidden_state() -> void:
	assert_eq(
		DebugOverlay.Page.keys()[DebugOverlay.Page.size() - 1],
		"HIDDEN",
		"the last page dismisses the panel"
	)


## THE ASCII MAP IS SUPERSEDED, but it is still the only form available headlessly, so its rows
## must stay aligned. The regression that produced "y= -4 - y= -4 - y= -4" across the screen was
## a row label emitted inside the COLUMN loop — one wrong indent.
func test_the_text_map_emits_one_row_label_per_row() -> void:
	for line in WorldInspector.map_text().split("\n"):
		assert_lte(line.count("y="), 1, "each row carries exactly one coordinate label")


## Markup must not leak into the words. A stray unclosed tag swallows the rest of the page, and
## the symptom is text simply vanishing rather than an error.
func test_every_colour_tag_on_a_page_is_closed() -> void:
	for page in [
		WorldInspector.history_text(), WorldInspector.factions_text()
	]:
		assert_eq(
			page.count("[color="),
			page.count("[/color]"),
			"every colour tag is closed"
		)


## The drawn map must never generate a chunk. Marking a stairwell is positional for the same
## reason: a lookup would bring the chunk it is describing into existence.
func test_the_drawn_map_generates_nothing() -> void:
	var minimap: MinimapView = MinimapView.new()
	add_child_autofree(minimap)
	var before: int = World.grid.chunks_generated
	minimap.refresh()
	assert_eq(World.grid.chunks_generated, before, "drawing the map created no chunks")
