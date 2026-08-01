## Hand-authored Sprint 1 chunk.
##
## Sprint 1 needs a tile_map in FIVE places — collision sweeps, pick DDA, line of sight, grid A*
## fallback, and the fluid grid's host chunk — but world generation is Sprint 2. Without this,
## Sprint 1 either stalls or invents a chunk representation Sprint 2 then throws away.
##
## This is the PRECURSOR to the Sprint 2 WorldGrid, not a parallel system. Sprint 2 replaces the
## producer; the consumer contract does not change.
##
## Layout (64x64, 1 m tiles):
##   * solid border wall
##   * an interior wall with a doorway, to exercise sliding and line-of-sight occlusion
##   * a raised ledge at STEP_UP_MAX height, to exercise the step rule
##   * a pit, to exercise drops and fall damage
##   * a diagonal pinch, to exercise the vertex-squeeze case
##   * a water source cell, to exercise the fluid CA
class_name TestArena
extends RefCounted

const DOORWAY_Y: int = 32
const LEDGE_HEIGHT_M: float = 0.4
const PIT_DEPTH_M: float = -2.5
## Ramp out of the pit. 0.4 m per tile keeps every tread inside `STEP_UP_MAX_M` (0.5 m) with
## margin, so it is walkable up and down without a jump.
const RAMP_RISE_PER_TILE_M: float = 0.4
const RAMP_Y_MIN: int = 14
const RAMP_Y_MAX: int = 15

const WATER_SOURCE: Vector2i = Vector2i(10, 10)
const SPAWN_TILE: Vector2i = Vector2i(8, 32)


static func build(chunk_id: Vector3i = Vector3i.ZERO) -> ChunkData:
	var chunk := ChunkData.new(chunk_id)
	chunk.biome_tag = &"BIOME_TEST_ARENA"
	chunk.ambient_temperature_c = 20.0
	var stone: int = chunk.intern_material(MaterialLibrary.MAT_STONE)

	var size: int = WorldConstants.CHUNK_TILES
	for y in size:
		for x in size:
			var idx: int = WorldConstants.cell_index(x, y)
			var border: bool = x == 0 or y == 0 or x == size - 1 or y == size - 1
			chunk.tile_map[idx] = ChunkData.TILE_SOLID if border else ChunkData.TILE_OPEN
			chunk.height_map[idx] = 0.0
			chunk.tile_material[idx] = stone

	_carve_interior_wall(chunk)
	_carve_ledge(chunk)
	_carve_pit(chunk)
	_carve_diagonal_pinch(chunk)

	# A puddle to prove the CA runs, freezes, and makes the floor slippery.
	chunk.add_fluid(WATER_SOURCE.x, WATER_SOURCE.y, 400, MaterialLibrary.MAT_WATER)
	return chunk


## A wall across the arena with a single doorway, so sliding and occlusion are both testable.
static func _carve_interior_wall(chunk: ChunkData) -> void:
	for y in range(4, WorldConstants.CHUNK_TILES - 4):
		if y == DOORWAY_Y or y == DOORWAY_Y + 1:
			continue
		chunk.set_tile(24, y, ChunkData.TILE_SOLID, 0.0)


## A step exactly inside STEP_UP_MAX_M, so a mover should climb it without jumping.
static func _carve_ledge(chunk: ChunkData) -> void:
	for y in range(40, 50):
		for x in range(40, 50):
			chunk.set_tile(x, y, ChunkData.TILE_OPEN, LEDGE_HEIGHT_M)


## A pit deep enough that entering it is a fall, not a step-down.
static func _carve_pit(chunk: ChunkData) -> void:
	for y in range(12, 18):
		for x in range(40, 46):
			chunk.set_tile(x, y, ChunkData.TILE_OPEN, PIT_DEPTH_M)
	_carve_pit_ramp(chunk)


## A way BACK OUT of the pit.
##
## The pit floor is 2.5 m below the surrounding stone and the step-up limit is 0.5 m, so a player
## who fell in was simply trapped: every wall of the pit is five times too tall to climb and there
## is no jump. Correct physics, unusable test arena.
##
## Each tread rises 0.4 m, comfortably inside STEP_UP_MAX_M, so the ramp is walkable in both
## directions and also exercises the step rule repeatedly on the way up.
static func _carve_pit_ramp(chunk: ChunkData) -> void:
	var tread: float = PIT_DEPTH_M
	for x in range(46, 52):
		tread += RAMP_RISE_PER_TILE_M
		for y in range(RAMP_Y_MIN, RAMP_Y_MAX + 1):
			chunk.set_tile(x, y, ChunkData.TILE_OPEN, tread)


## Two diagonal solids with open cells between them. An axis-separated collision resolve would
## squeeze an AABB through the shared vertex here.
static func _carve_diagonal_pinch(chunk: ChunkData) -> void:
	chunk.set_tile(50, 20, ChunkData.TILE_SOLID, 0.0)
	chunk.set_tile(51, 21, ChunkData.TILE_SOLID, 0.0)


static func spawn_position(chunk: ChunkData) -> Vector3:
	var world: Vector3 = chunk.tile_to_world(SPAWN_TILE.x, SPAWN_TILE.y)
	# Feet on the floor: centre sits one half-height above ground.
	return Vector3(world.x, world.y + 0.9, world.z)
