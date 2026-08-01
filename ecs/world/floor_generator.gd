## Builds one chunk's tile grid. Pure data in, pure ChunkData out.
##
## DETERMINISM IS PER CHUNK, NOT PER RUN. Every chunk derives its own RNG from
## `hash(master_seed, chunk_id)` rather than drawing from a shared stream. Sharing a stream would
## make a chunk's contents depend on the ORDER chunks were visited, so the same cave would look
## different depending on which corridor you walked down first — and ADR-1's promise that
## unvisited content regenerates from seed would be false.
##
## CONNECTIVITY IS GUARANTEED BY CONSTRUCTION, not checked afterwards. Rooms are linked in a
## chain, and every chunk opens its four edge midpoints. Cellular-automata caves were the obvious
## alternative and were rejected here: they routinely produce isolated pockets, and "generate,
## detect islands, then repair" is a far larger algorithm than laying corridors that cannot be
## disconnected in the first place.
class_name FloorGenerator
extends RefCounted

const CHUNK_TILES: int = WorldConstants.CHUNK_TILES

## Where a corridor crosses into the neighbouring chunk. Both sides use the same constant, so
## the openings line up without either chunk knowing anything about the other.
const EDGE_GATE: int = CHUNK_TILES / 2
const GATE_HALF_WIDTH: int = 1

const ROOMS_MIN: int = 4
const ROOMS_MAX: int = 7
const ROOM_MIN: int = 6
const ROOM_MAX: int = 14

const VILLAGE_FLOOR: int = 0

## Stairwells live on the LANDING CHUNK of each floor — chunk (0, 0, z) — at fixed tiles, so
## descending and ascending always arrive somewhere known. ADR-3's Active set already treats the
## landing chunk directly above and below as loaded, which is exactly what a stairwell needs.
const LANDING_CHUNK_XY := Vector2i(0, 0)
const STAIR_DOWN_TILE := Vector2i(34, 32)
const STAIR_UP_TILE := Vector2i(30, 32)

## How deep the stairwell goes. Matches DAGGenerator.DEEPEST_FLOOR: generating stairs to a floor
## no faction lives on would produce an empty shaft to nowhere.
const DEEPEST_FLOOR: int = -5

## The Adventurer's Residence (Sprint 3 roadmap Step 6, declared gap G-3): where each new
## adventurer wakes. A FIXED tile in the origin village chunk, carved AFTER the random
## buildings so no roll can wall it in. The successor spawning "at the same spot the last body
## started from" was the placeholder; a residence is what makes the respawn read as a person
## arriving somewhere rather than the world resetting.
const RESIDENCE_TILE := Vector2i(20, 44)
const RESIDENCE_HALF: int = 3


static func generate(chunk_id: Vector3i, master_seed: int) -> ChunkData:
	var chunk := ChunkData.new(chunk_id)
	var rng: RandomNumberGenerator = chunk_rng(chunk_id, master_seed)
	if chunk_id.z == VILLAGE_FLOOR:
		_generate_village(chunk, rng)
	else:
		_generate_ruins(chunk, rng)
	_open_edge_gates(chunk)
	_place_stairwell(chunk)
	# A freshly generated chunk is ABSTRACTED until something promotes it. ChunkData defaults to
	# ACTIVE, which is right for the hand-authored Sprint 1 arena and wrong for everything the
	# grid produces: it made every lazily-generated dungeon chunk claim to be Active, so the LoD
	# system would have paid full collision and fluid cost for the entire world at once.
	chunk.state = ECSEnums.LoD.ABSTRACTED
	chunk.tile_map_dirty = true
	chunk.topology_dirty = true
	chunk.nav_region_dirty = true
	return chunk


## A chunk's seed is a pure function of the world seed and its coordinates, so generating chunk
## (3, -2, -1) first or last produces the same chunk either way.
static func chunk_rng(chunk_id: Vector3i, master_seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	# Odd multipliers keep the three axes from aliasing onto each other; without distinct
	# factors, (1, 2, 0) and (2, 1, 0) would hash identically and generate the same chunk.
	rng.seed = (
		master_seed
		+ chunk_id.x * 73856093
		+ chunk_id.y * 19349663
		+ chunk_id.z * 83492791
	)
	return rng


## The surface village: open ground with solid blocks for buildings, each with a doorway.
static func _generate_village(chunk: ChunkData, rng: RandomNumberGenerator) -> void:
	var stone: int = chunk.intern_material(MaterialLibrary.MAT_STONE)
	_fill(chunk, ChunkData.TILE_OPEN, stone)

	var buildings: int = rng.randi_range(3, 6)
	for _b in buildings:
		var width: int = rng.randi_range(5, 9)
		var depth: int = rng.randi_range(5, 9)
		var origin_x: int = rng.randi_range(3, CHUNK_TILES - width - 4)
		var origin_y: int = rng.randi_range(3, CHUNK_TILES - depth - 4)
		_carve_building(chunk, origin_x, origin_y, width, depth, rng)

	# The Residence goes in LAST and only in the origin chunk, where the player spawns. Carved
	# last so a random building drawn over the same ground cannot leave a wall segment standing
	# inside it — determinism of the spawn point beats the aesthetics of one overlap.
	if chunk.chunk_id.x == 0 and chunk.chunk_id.y == 0:
		_carve_residence(chunk)


## A one-room house with the interior fully re-opened and a south door, centred on
## RESIDENCE_TILE. The interior clear pass is what makes this safe to carve over anything the
## random pass already placed.
static func _carve_residence(chunk: ChunkData) -> void:
	var lo: int = -RESIDENCE_HALF
	var hi: int = RESIDENCE_HALF
	for dy in range(lo, hi + 1):
		for dx in range(lo, hi + 1):
			var x: int = RESIDENCE_TILE.x + dx
			var y: int = RESIDENCE_TILE.y + dy
			var on_wall: bool = dx == lo or dx == hi or dy == lo or dy == hi
			chunk.set_tile(x, y, ChunkData.TILE_SOLID if on_wall else ChunkData.TILE_OPEN, 0.0)
	chunk.set_tile(RESIDENCE_TILE.x, RESIDENCE_TILE.y + lo, ChunkData.TILE_OPEN, 0.0)


## Walls only, so the inside stays enterable, plus exactly one doorway per building.
static func _carve_building(
	chunk: ChunkData, origin_x: int, origin_y: int, width: int, depth: int,
	rng: RandomNumberGenerator
) -> void:
	for y in range(origin_y, origin_y + depth):
		for x in range(origin_x, origin_x + width):
			var on_wall: bool = (
				x == origin_x
				or y == origin_y
				or x == origin_x + width - 1
				or y == origin_y + depth - 1
			)
			if on_wall:
				chunk.set_tile(x, y, ChunkData.TILE_SOLID, 0.0)
	var door_x: int = rng.randi_range(origin_x + 1, origin_x + width - 2)
	chunk.set_tile(door_x, origin_y, ChunkData.TILE_OPEN, 0.0)


## Dungeon floors: rigid rooms and corridors, in keeping with dwarven ruins.
static func _generate_ruins(chunk: ChunkData, rng: RandomNumberGenerator) -> void:
	var stone: int = chunk.intern_material(MaterialLibrary.MAT_STONE)
	_fill(chunk, ChunkData.TILE_SOLID, stone)

	var centres: Array[Vector2i] = []
	var room_count: int = rng.randi_range(ROOMS_MIN, ROOMS_MAX)
	for _r in room_count:
		var width: int = rng.randi_range(ROOM_MIN, ROOM_MAX)
		var depth: int = rng.randi_range(ROOM_MIN, ROOM_MAX)
		var origin_x: int = rng.randi_range(2, CHUNK_TILES - width - 3)
		var origin_y: int = rng.randi_range(2, CHUNK_TILES - depth - 3)
		for y in range(origin_y, origin_y + depth):
			for x in range(origin_x, origin_x + width):
				chunk.set_tile(x, y, ChunkData.TILE_OPEN, 0.0)
		centres.append(Vector2i(origin_x + width / 2, origin_y + depth / 2))

	# Ruins are inhabited. The swarm counter was declared, capped by the Interregnum tax, and
	# NEVER SEEDED — nothing in the build ever set it above zero, so the "swarm tax" clamped a
	# counter that was always already zero. Vermin scale loosely with depth: the deep floors are
	# older, wetter and less picked-over.
	chunk.swarm_population = rng.randi_range(0, 3) + mini(3, absi(chunk.chunk_id.z))

	# Chain every room to the previous one. A chain is a spanning tree, so no room can be
	# stranded — which is the failure mode that makes generated floors unplayable.
	for i in range(1, centres.size()):
		_carve_corridor(chunk, centres[i - 1], centres[i])

	# And chain the first room to the middle of the chunk, where the edge gates meet.
	if not centres.is_empty():
		_carve_corridor(chunk, centres[0], Vector2i(EDGE_GATE, EDGE_GATE))


## L-shaped: horizontal then vertical. Two straight runs are trivially connected, where a
## diagonal line of tiles is not — an AABB cannot pass through a shared vertex (Sprint 1).
static func _carve_corridor(chunk: ChunkData, from: Vector2i, to: Vector2i) -> void:
	var x: int = from.x
	while x != to.x:
		_carve_wide(chunk, x, from.y)
		x += 1 if to.x > x else -1
	var y: int = from.y
	while y != to.y:
		_carve_wide(chunk, to.x, y)
		y += 1 if to.y > y else -1
	_carve_wide(chunk, to.x, to.y)


## Two tiles wide. A one-tile corridor is exactly as wide as a 0.6 m humanoid AABB, so any
## floating-point drift wedges the player against a wall.
static func _carve_wide(chunk: ChunkData, x: int, y: int) -> void:
	for dy in range(0, 2):
		for dx in range(0, 2):
			var tx: int = clampi(x + dx, 1, CHUNK_TILES - 2)
			var ty: int = clampi(y + dy, 1, CHUNK_TILES - 2)
			chunk.set_tile(tx, ty, ChunkData.TILE_OPEN, 0.0)


## Opens a gap at the middle of each edge and runs it to the chunk centre, so neighbouring
## chunks always join. Both sides compute the same gate position independently.
static func _open_edge_gates(chunk: ChunkData) -> void:
	var last: int = CHUNK_TILES - 1
	for offset in range(-GATE_HALF_WIDTH, GATE_HALF_WIDTH + 1):
		var across: int = EDGE_GATE + offset
		for edge in [0, last]:
			chunk.set_tile(edge, across, ChunkData.TILE_OPEN, 0.0)
			chunk.set_tile(across, edge, ChunkData.TILE_OPEN, 0.0)
	_carve_corridor(chunk, Vector2i(0, EDGE_GATE), Vector2i(EDGE_GATE, EDGE_GATE))
	_carve_corridor(chunk, Vector2i(last, EDGE_GATE), Vector2i(EDGE_GATE, EDGE_GATE))
	_carve_corridor(chunk, Vector2i(EDGE_GATE, 0), Vector2i(EDGE_GATE, EDGE_GATE))
	_carve_corridor(chunk, Vector2i(EDGE_GATE, last), Vector2i(EDGE_GATE, EDGE_GATE))


## Marks the chunk's stairwell, the only way between floors (ADR-3 landings).
static func place_stairs(chunk: ChunkData, tile: Vector2i) -> void:
	chunk.set_tile(tile.x, tile.y, ChunkData.TILE_STAIRS, 0.0)
	# Carve a walkable pocket around it FIRST, then re-mark the stair itself: a stairwell
	# generated inside a solid room is one nobody can stand on, and that failure reads as the
	# stairs simply not working.
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			chunk.set_tile(tile.x + dx, tile.y + dy, ChunkData.TILE_OPEN, 0.0)
	chunk.set_tile(tile.x, tile.y, ChunkData.TILE_STAIRS, 0.0)


## Every landing chunk gets the stairs its depth allows: the surface has only a way down, the
## deepest floor only a way up, everything between has both.
static func _place_stairwell(chunk: ChunkData) -> void:
	if chunk.chunk_id.x != LANDING_CHUNK_XY.x or chunk.chunk_id.y != LANDING_CHUNK_XY.y:
		return
	# CORRIDORS FIRST. `_carve_corridor` writes TILE_OPEN over everything it touches, so carving
	# after placing would erase the stairs it was carving TO — and the failure is invisible,
	# because the transition is keyed on tile POSITION and kept working while the tile itself
	# silently reverted to plain floor.
	_carve_corridor(chunk, STAIR_UP_TILE, STAIR_DOWN_TILE)
	_carve_corridor(chunk, STAIR_DOWN_TILE, Vector2i(EDGE_GATE, EDGE_GATE))

	var floor_index: int = chunk.chunk_id.z
	if floor_index > DEEPEST_FLOOR:
		place_stairs(chunk, STAIR_DOWN_TILE)
	if floor_index < VILLAGE_FLOOR:
		place_stairs(chunk, STAIR_UP_TILE)


static func _fill(chunk: ChunkData, kind: int, material: int) -> void:
	for y in CHUNK_TILES:
		for x in CHUNK_TILES:
			chunk.set_tile(x, y, kind, 0.0)
			chunk.tile_material[WorldConstants.cell_index(x, y)] = material
