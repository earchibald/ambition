## Makes the generated world INSPECTABLE (Sprint 3 play-testing gap).
##
## Sprint 2 generated 500 years of history, placed a dozen factions by it, and showed the player
## none of it. The chronicle existed only in memory. Faction ledgers are entities with no
## POSITION — deliberately, they are not things in the world — which means `Tab` can never reach
## them, because picking resolves through the spatial hash. So the single most interesting output
## of two sprints was, from the player's seat, entirely invisible.
##
## Read-only, like everything in `ui/`. It queries ECS state and renders text; it never writes.
class_name WorldInspector
extends RefCounted

## The village is 3x3 chunks, so a 9x9 window shows it entirely plus the ring of dungeon and
## unexplored space around it. Wide enough to be useful, narrow enough to read.
const MAP_RADIUS_CHUNKS: int = 4

## Chronicle lines shown at once. Fifty epochs produce roughly thirty lines, so this is usually
## the whole history — the cap exists so a longer run cannot push the screen off the bottom.
const MAX_CHRONICLE_LINES: int = 28


## The 500-year history, most recent last, as the generator recorded it.
static func history_text() -> String:
	var generator: DAGGenerator = _generator()
	if generator == null:
		return (
			"No history: this is the test arena, which has none by design.\n"
			+ "Boot the `world` scenario to see one."
		)
	var lines: Array[String] = [
		PanelFormat.heading("the chronicle"),
		PanelFormat.muted("  %d events across %d years" % [
			generator.chronicle.size(), generator.year_of(DAGGenerator.MAX_EPOCHS)
		]),
		"",
	]
	var start: int = maxi(0, generator.chronicle.size() - MAX_CHRONICLE_LINES)
	if start > 0:
		lines.append(PanelFormat.muted("  ... %d earlier events ..." % start))
	for i in range(start, generator.chronicle.size()):
		lines.append("  " + _dress_event(generator.chronicle[i]))
	return "\n".join(lines)


## Splits "Year 150: X conquered Y." into a dim year and a bright sentence, and tints the verb.
##
## The chronicle used to be a wall of identical grey lines, so finding the conquests — the events
## that actually shaped the world you are standing in — meant reading all of them.
static func _dress_event(event: String) -> String:
	var colon: int = event.find(":")
	if colon < 0:
		return PanelFormat.plain(event)
	var when: String = event.substr(0, colon + 1)
	var what: String = event.substr(colon + 1).strip_edges()
	var body: String = PanelFormat.plain(what)
	if what.contains("conquered"):
		body = PanelFormat.bad(what)
	elif what.contains("forged"):
		body = PanelFormat.accent(what)
	return "%s %s" % [PanelFormat.muted(when.rpad(10)), body]


## Who is alive, what they own, and what they have decided.
##
## Reads the LEDGER entities directly, which is the only way to see them: they have no position,
## so nothing in the world can be clicked to reach them.
static func factions_text() -> String:
	var rows: PackedInt32Array = ECSManager.query(ComponentMask.FACTION_CORE)
	if rows.is_empty():
		return "No factions. The test arena has none; boot the `world` scenario."

	var generator: DAGGenerator = _generator()
	var lines: Array[String] = [
		PanelFormat.heading("factions"),
		PanelFormat.muted("  %d alive" % rows.size()),
	]
	for row in rows:
		var core: FactionCoreComponent = ECSManager.faction_cores[row]
		var node: DAGNode = null if generator == null else generator.node_by_id(core.dag_node_id)
		var title: String = (
			"faction %d" % core.faction_id if node == null else String(node.name)
		)
		var bodies: int = FactionPlanner.members_of(core.faction_id).size()
		lines.append("")
		lines.append("  %s %s" % [
			PanelFormat.accent(title), PanelFormat.muted("#%d" % core.faction_id)
		])
		lines.append(PanelFormat.row("  people", PanelFormat.tally([
			[core.abstract_population, "abstract"],
			[bodies, "embodied"],
		])))
		lines.append(PanelFormat.row(
			"  culture", PanelFormat.muted(", ".join(core.culture_tags))
		))
		lines.append(PanelFormat.row("  doing", "%s %s" % [
			PanelFormat.plain(ECSEnums.Objective.keys()[core.current_objective]),
			PanelFormat.muted("(%s)" % ECSEnums.Emotion.keys()[core.current_emotion]),
		]))
		lines.append(PanelFormat.row("  wealth", PanelFormat.plain(_describe_wealth(core))))
		lines.append(PanelFormat.row(
			"  home", PanelFormat.muted("chunk %s" % core.anchor_chunk_id)
		))
		if core.last_declaration != "":
			lines.append('    [i]%s"%s"[/i]' % [
				"[color=#%s]" % PanelFormat.VALUE, core.last_declaration
			])
	return "\n".join(lines)


## An ASCII chunk map. SUPERSEDED by `MinimapView`, which draws the same information properly;
## kept because it is the only form the map can take in a headless test or a terminal dump.
##
## Crude on purpose: the question it answers — "what is around me, and is it
## loaded" — is answered better by a grid of letters than by any amount of prose.
static func map_text() -> String:
	if World.grid == null:
		return "No chunk grid: the test arena is a single hand-authored chunk."

	var centre: Vector3i = World.player_chunk_id
	var anchors: Dictionary = _anchor_lookup()
	var lines: Array[String] = [
		"--- FLOOR %d, chunks %d..%d ---"
		% [centre.z, centre.x - MAP_RADIUS_CHUNKS, centre.x + MAP_RADIUS_CHUNKS]
	]
	for y in range(centre.y - MAP_RADIUS_CHUNKS, centre.y + MAP_RADIUS_CHUNKS + 1):
		var cells: Array[String] = []
		for x in range(centre.x - MAP_RADIUS_CHUNKS, centre.x + MAP_RADIUS_CHUNKS + 1):
			cells.append(_cell(Vector3i(x, y, centre.z), centre, anchors))
		# ONE label per ROW, outside the column loop. Indented one level too deep, this emitted a
		# coordinate after every single cell — "y= -4 - y= -4 - y= -4" straight across — which is
		# how a readable map became incomprehensible in a single edit.
		#
		# Width-padded, too: "y=-4" is a character wider than "y=0", and that lone minus sign
		# raggeds the right-hand edge on its own.
		cells.append("   y=%3d" % y)
		lines.append("  " + " ".join(cells))
	lines.append("")
	lines.append("  @ you    A active    s simulated    . generated    - not generated yet")
	lines.append("  F faction anchor (overrides state)")
	return "\n".join(lines)


## One map cell. The player marker wins over everything, then a faction anchor, then LoD state —
## ordered by what you most need to know at a glance.
static func _cell(chunk_id: Vector3i, centre: Vector3i, anchors: Dictionary) -> String:
	if chunk_id == centre:
		return "@"
	if anchors.has(chunk_id):
		return "F"
	# has_chunk, NOT chunk_at: asking the grid would GENERATE every chunk on screen purely to
	# draw a map of which chunks exist, which would make the map itself the thing that fills it.
	if not World.grid.has_chunk(chunk_id):
		return "-"
	match World.grid.chunk_at(chunk_id).state:
		ECSEnums.LoD.ACTIVE:
			return "A"
		ECSEnums.LoD.SIMULATED:
			return "s"
		_:
			return "."


static func _anchor_lookup() -> Dictionary:
	var out: Dictionary = {}
	for row in ECSManager.query(ComponentMask.FACTION_CORE):
		out[ECSManager.faction_cores[row].anchor_chunk_id] = true
	return out


## Wealth, wherever it currently lives.
##
## A faction whose chunk is Active has an EMPTY ledger, because promotion spends it into physical
## stacks — that is the conservation rule working exactly as designed. Printing a bare "empty"
## for the village you are standing in reads as a bug, so the total is reported from whichever
## side currently holds it, and the location is named.
static func _describe_wealth(core: FactionCoreComponent) -> String:
	var banked: int = core.ledger_total()
	var carried: int = ChunkStreamingSystem.total_faction_value(core.faction_id) - banked
	if banked > 0 and carried <= 0:
		return "%s (on the ledger)" % _short_ledger(core.abstract_wealth_ledger)
	if carried > 0 and banked <= 0:
		return "%d units, materialized as stacks" % carried
	if banked <= 0 and carried <= 0:
		return "destitute"
	return "%d banked + %d materialized" % [banked, carried]


## Totals rather than a full breakdown: a dozen materials per faction would fill the screen and
## the number that matters at a glance is how rich they are.
static func _short_ledger(ledger: Dictionary) -> String:
	if ledger.is_empty():
		return "empty"
	var total: int = 0
	var richest: StringName = &""
	var most: int = -1
	for material in ledger:
		var amount: int = int(ledger[material])
		total += amount
		if amount > most:
			most = amount
			richest = material
	return "%d units, mostly %s" % [total, richest]


static func _generator() -> DAGGenerator:
	return null if World.boot_report == null else World.boot_report.generator
