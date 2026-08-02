## A DRAWN chunk map. Rectangles and dots, not characters.
##
## The first version was ASCII art, which was the wrong tool twice over. It depended on a
## monospace font to line up at all, it broke the instant a row label was emitted in the wrong
## loop — producing "y= -4 - y= -4 - y= -4" across the screen — and even when perfectly aligned a
## grid of letters is a poor way to answer a spatial question. This is a game engine; drawing a
## map is one `_draw` call.
##
## Read-only, like everything in `ui/`. It queries ECS and grid state and paints; it writes
## nothing and it generates nothing.
class_name MinimapView
extends Control

const CELL_PX: float = 30.0
const GUTTER_PX: float = 3.0
## Room for the coordinate labels down the left, and for the floor caption PLUS the column
## labels along the top. One shared margin had the floor caption sitting on top of the first
## column label.
const LEFT_MARGIN_PX: float = 26.0
const TOP_MARGIN_PX: float = 40.0

## How many chunks either side of the player are shown.
const RADIUS_CHUNKS: int = 4

const COLOUR_ABSENT := Color(0.12, 0.12, 0.15)
const COLOUR_GENERATED := Color(0.26, 0.26, 0.30)
const COLOUR_SIMULATED := Color(0.24, 0.38, 0.52)
const COLOUR_ACTIVE := Color(0.30, 0.62, 0.42)
const COLOUR_PLAYER := Color(0.40, 0.90, 1.0)
const COLOUR_ANCHOR := Color(1.0, 0.76, 0.28)
const COLOUR_STAIRS := Color(0.55, 0.85, 1.0)
const COLOUR_LABEL := Color(0.62, 0.66, 0.76)
const COLOUR_GRID := Color(0.40, 0.42, 0.50, 0.55)

var _font: Font = null


func _ready() -> void:
	var span: float = float(RADIUS_CHUNKS * 2 + 1) * (CELL_PX + GUTTER_PX)
	custom_minimum_size = Vector2(span + LEFT_MARGIN_PX, span + TOP_MARGIN_PX + 44.0)
	_font = ThemeDB.fallback_font


## Redrawn on demand rather than every frame: chunk states change on the Simulation tick at most,
## and repainting a grid at 60 Hz to show a value that changes twice a second is waste.
func refresh() -> void:
	queue_redraw()


func _draw() -> void:
	if World.grid == null:
		draw_string(
			_font, Vector2(4, 16), "No chunk grid — the arena is a single hand-authored chunk.",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COLOUR_LABEL
		)
		return

	var centre: Vector3i = World.player_chunk_id
	var anchors: Dictionary = _anchors()
	var step: float = CELL_PX + GUTTER_PX

	draw_string(
		_font, Vector2(0, 14), "FLOOR %d   (chunk %d, %d)" % [centre.z, centre.x, centre.y],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COLOUR_LABEL
	)

	for row in range(RADIUS_CHUNKS * 2 + 1):
		var chunk_y: int = centre.y - RADIUS_CHUNKS + row
		var top: float = TOP_MARGIN_PX + float(row) * step
		draw_string(
			_font, Vector2(0, top + CELL_PX * 0.7), "%d" % chunk_y,
			HORIZONTAL_ALIGNMENT_LEFT, LEFT_MARGIN_PX - 4, 11, COLOUR_LABEL
		)

		for column in range(RADIUS_CHUNKS * 2 + 1):
			var chunk_x: int = centre.x - RADIUS_CHUNKS + column
			var left: float = LEFT_MARGIN_PX + float(column) * step
			if row == 0:
				draw_string(
					_font, Vector2(left, TOP_MARGIN_PX - 6.0), "%d" % chunk_x,
					HORIZONTAL_ALIGNMENT_CENTER, CELL_PX, 11, COLOUR_LABEL
				)
			_draw_cell(
				Vector3i(chunk_x, chunk_y, centre.z),
				Rect2(left, top, CELL_PX, CELL_PX),
				centre,
				anchors
			)

	_draw_legend(TOP_MARGIN_PX + float(RADIUS_CHUNKS * 2 + 1) * step + 8.0)


func _draw_cell(
	chunk_id: Vector3i, box: Rect2, centre: Vector3i, anchors: Dictionary
) -> void:
	draw_rect(box, _state_colour(chunk_id))
	draw_rect(box, COLOUR_GRID, false, 1.0)

	# A stairwell is the only way off this floor, so it is marked before anything except you.
	if _has_stairs(chunk_id):
		var mark: float = 4.0
		draw_rect(
			Rect2(box.position + Vector2(3, 3), Vector2(mark, mark)), COLOUR_STAIRS
		)
	if anchors.has(chunk_id):
		draw_circle(box.position + Vector2(CELL_PX - 7.0, 7.0), 3.5, COLOUR_ANCHOR)
	if chunk_id == centre:
		draw_circle(box.get_center(), 6.0, COLOUR_PLAYER)
		draw_circle(box.get_center(), 6.0, Color(0, 0, 0, 0.85), false, 1.5)


## `has_chunk`, never `chunk_at`. Asking the grid GENERATES the chunk, which would make drawing a
## map of what exists the very thing that brings it into existence.
func _state_colour(chunk_id: Vector3i) -> Color:
	if not World.grid.has_chunk(chunk_id):
		return COLOUR_ABSENT
	match World.grid.chunk_at(chunk_id).state:
		ECSEnums.LoD.ACTIVE:
			return COLOUR_ACTIVE
		ECSEnums.LoD.SIMULATED:
			return COLOUR_SIMULATED
		_:
			return COLOUR_GENERATED


## Stairwells are generated on the landing chunk of every floor, so membership is positional and
## needs no lookup — which also means marking one cannot generate the chunk it marks.
func _has_stairs(chunk_id: Vector3i) -> bool:
	return (
		chunk_id.x == FloorGenerator.LANDING_CHUNK_XY.x
		and chunk_id.y == FloorGenerator.LANDING_CHUNK_XY.y
	)


func _anchors() -> Dictionary:
	var out: Dictionary = {}
	for row in ECSManager.query(ComponentMask.FACTION_CORE):
		out[ECSManager.faction_cores[row].anchor_chunk_id] = true
	return out


## Swatches, not a sentence. The legend has to be readable at a glance or it is just more text.
func _draw_legend(top: float) -> void:
	var entries: Array = [
		[COLOUR_ACTIVE, "active"],
		[COLOUR_SIMULATED, "simulated"],
		[COLOUR_GENERATED, "generated"],
		[COLOUR_ABSENT, "unexplored"],
	]
	var x: float = 0.0
	for entry in entries:
		draw_rect(Rect2(x, top, 11, 11), entry[0])
		draw_rect(Rect2(x, top, 11, 11), COLOUR_GRID, false, 1.0)
		draw_string(
			_font, Vector2(x + 15, top + 10), entry[1],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLOUR_LABEL
		)
		x += 15.0 + _font.get_string_size(entry[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 12.0

	var second: float = top + 16.0
	draw_circle(Vector2(5, second + 6), 5.0, COLOUR_PLAYER)
	draw_string(
		_font, Vector2(15, second + 10), "you", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLOUR_LABEL
	)
	draw_circle(Vector2(60, second + 6), 3.5, COLOUR_ANCHOR)
	draw_string(
		_font, Vector2(70, second + 10), "faction anchor",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLOUR_LABEL
	)
	draw_rect(Rect2(168, second + 2, 4, 4), COLOUR_STAIRS)
	draw_string(
		_font, Vector2(178, second + 10), "stairwell",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLOUR_LABEL
	)
