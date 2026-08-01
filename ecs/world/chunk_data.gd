## One chunk of world (registry section 6).
##
## Chunks are NOT entities. The cellular-automata fluid buffers and the dirty-cell set live
## here, because nothing else owned them.
##
## ALL GRIDS CARRY A 1-CELL GHOST APRON (stride 66, not 64). On a bare 64x64 array a neighbour
## probe at x=63 wraps to the next row and at index 4095 runs off the end entirely. Index every
## cell through WorldConstants.cell_index(x, y).
class_name ChunkData
extends TileSampler

const TILE_OPEN: int = 0
const TILE_SOLID: int = 1
const TILE_STAIRS: int = 2

var chunk_id: Vector3i = Vector3i.ZERO
var state: ECSEnums.LoD = ECSEnums.LoD.ACTIVE
var biome_tag: StringName = &"BIOME_TEST"
var ambient_temperature_c: float = 20.0

## ZONE-LEVEL HAZARDS (Sprint 4 §4). A whole region that is sporing, filthy, or irradiated, as
## distinct from a tag on one entity. `MutationSystem` accrues exposure from these for anything
## standing in the chunk, which is what makes "spend too long in a High_Filth zone" a real rule
## rather than a description of one. Chunks are not entities, so this is chunk data and NOT a
## ChemistryComponent (registry §6).
var hazard_tags: Array[StringName] = []

## One-shot flag for prop spawning at first promotion (a ruined library's lectern). The same
## transaction-flag pattern as `wealth_materialized`: promotion is re-entrant, prop spawning
## must not be, or every visit to a chunk grows another lectern.
var props_spawned: bool = false

## Tile solidity and per-tile elevation in metres (2.5D, ADR-3).
var tile_map: PackedInt32Array = PackedInt32Array()
var height_map: PackedFloat32Array = PackedFloat32Array()
## Material of each tile, for LoS attenuation and mining yields.
var tile_material: PackedInt32Array = PackedInt32Array()

## --- Cellular automata. SINGLE buffer plus a delta accumulator. ---
## There is deliberately NO next_volume_map: double buffering plus a sparse dirty set
## annihilates every settled cell on the first tick it stops being dirty, because non-dirty
## cells never get written to the back buffer.
var volume_map: PackedInt32Array = PackedInt32Array()
var delta_map: PackedInt32Array = PackedInt32Array()
var material_map: PackedInt32Array = PackedInt32Array()
## Sparse set of cell indices to process. This IS the ADR-10 "active cell" set.
var dirty_cells: Dictionary = {}
## Volume pending from a neighbouring chunk, pumped in at a safe rate.
var flood_buffer: Dictionary = {}

## Abstracted fluid held while this chunk is not Active, by material id.
var volume_pools: Dictionary = {}
## Guards against re-materializing a pool that was already spawned (the fluid analogue of
## `wealth_materialized`). Without it, N boundary crossings create N copies.
var fluid_materialized: bool = false

var swarm_population: int = 0
var wealth_materialized: bool = false
var tile_map_dirty: bool = false
var topology_dirty: bool = false
var nav_region_dirty: bool = false

## Material ids interned to ints for the grids. 0 means "none".
var _material_ids: Array[StringName] = [&""]


func _init(id: Vector3i = Vector3i.ZERO) -> void:
	chunk_id = id
	var cells: int = WorldConstants.GRID_CELLS
	tile_map.resize(cells)
	# The ghost apron is SOLID by default, so a neighbour probe that steps outside the real
	# 64x64 area is treated as wall by BOTH the fluid CA and collision. Builders explicitly
	# open the real cells they want traversable.
	tile_map.fill(TILE_SOLID)
	height_map.resize(cells)
	tile_material.resize(cells)
	volume_map.resize(cells)
	delta_map.resize(cells)
	material_map.resize(cells)


func intern_material(material_id: StringName) -> int:
	var existing: int = _material_ids.find(material_id)
	if existing >= 0:
		return existing
	_material_ids.append(material_id)
	return _material_ids.size() - 1


## How many distinct materials this chunk has interned, including the empty id 0. Lets a system
## build a per-material lookup table once per tick instead of asking per cell.
func material_count() -> int:
	return _material_ids.size()


func material_name(interned: int) -> StringName:
	if interned < 0 or interned >= _material_ids.size():
		return &""
	return _material_ids[interned]


func is_solid(x: int, y: int) -> bool:
	if not in_bounds(x, y):
		# Outside a loaded chunk reads as SOLID so a sweep or a DDA march cannot escape into
		# unloaded space.
		return true
	return tile_map[WorldConstants.cell_index(x, y)] == TILE_SOLID


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < WorldConstants.CHUNK_TILES and y < WorldConstants.CHUNK_TILES


# --- Tile sampler contract -----------------------------------------------------------------
#
# `WorldGrid` implements these three identically but resolves the owning chunk first. Collision
# and picking call only these, so the same code drives a single hand-authored room and a
# streamed multi-chunk world without knowing which it has.


## Outside this chunk reads as SOLID, deliberately. A lone chunk is a sealed room: better a mover
## stops at the edge than walks into unallocated space. `WorldGrid` overrides this by generating
## the neighbour instead.
func solid_at_world(world: Vector3) -> bool:
	var tile: Vector2i = world_to_tile(world)
	if not in_bounds(tile.x, tile.y):
		return true
	return is_solid(tile.x, tile.y)


func height_at_world(world: Vector3) -> float:
	var tile: Vector2i = world_to_tile(world)
	return height_at(tile.x, tile.y)


func contains_world(world: Vector3) -> bool:
	var tile: Vector2i = world_to_tile(world)
	return in_bounds(tile.x, tile.y)


func height_at(x: int, y: int) -> float:
	if not in_bounds(x, y):
		return 0.0
	return height_map[WorldConstants.cell_index(x, y)]


func set_tile(x: int, y: int, kind: int, elevation: float = 0.0) -> void:
	var idx: int = WorldConstants.cell_index(x, y)
	tile_map[idx] = kind
	height_map[idx] = elevation


## Any change to solidity, elevation, or hazard MUST dirty these flags. Collision uses the
## current tile_map immediately; the abstract graph and any nav bake catch up behind it.
func mutate_tile(x: int, y: int, kind: int, elevation: float = 0.0) -> void:
	set_tile(x, y, kind, elevation)
	tile_map_dirty = true
	topology_dirty = true
	if state == ECSEnums.LoD.ACTIVE:
		nav_region_dirty = true


func mark_dirty_cell(x: int, y: int) -> void:
	if in_bounds(x, y):
		dirty_cells[WorldConstants.cell_index(x, y)] = true


func fluid_at(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return 0
	return volume_map[WorldConstants.cell_index(x, y)]


func add_fluid(x: int, y: int, units: int, material_id: StringName) -> void:
	if not in_bounds(x, y) or units == 0:
		return
	var idx: int = WorldConstants.cell_index(x, y)
	volume_map[idx] += units
	if material_map[idx] == 0:
		material_map[idx] = intern_material(material_id)
	dirty_cells[idx] = true


## Total fluid in the grid. The conservation invariant is asserted against this.
func total_fluid_volume() -> int:
	var total: int = 0
	for y in WorldConstants.CHUNK_TILES:
		for x in WorldConstants.CHUNK_TILES:
			total += volume_map[WorldConstants.cell_index(x, y)]
	return total


## World-space centre of a tile, in metres.
func tile_to_world(x: int, y: int) -> Vector3:
	var origin_x: float = float(chunk_id.x) * WorldConstants.CHUNK_SIZE_M
	var origin_z: float = float(chunk_id.y) * WorldConstants.CHUNK_SIZE_M
	return Vector3(
		origin_x + (float(x) + 0.5) * WorldConstants.TILE_SIZE_M,
		height_at(x, y),
		origin_z + (float(y) + 0.5) * WorldConstants.TILE_SIZE_M
	)


## Chunk-local tile containing a world position.
func world_to_tile(world: Vector3) -> Vector2i:
	var origin_x: float = float(chunk_id.x) * WorldConstants.CHUNK_SIZE_M
	var origin_z: float = float(chunk_id.y) * WorldConstants.CHUNK_SIZE_M
	return Vector2i(
		int(floor((world.x - origin_x) / WorldConstants.TILE_SIZE_M)),
		int(floor((world.z - origin_z) / WorldConstants.TILE_SIZE_M))
	)
