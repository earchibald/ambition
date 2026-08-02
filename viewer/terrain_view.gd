## Renders the chunk's tile grid so the arena is actually visible.
##
## Without this the game boots to a void: `tile_map` and `height_map` existed and were simulated
## correctly, but NOTHING in `viewer/` ever read them, so the player fell down an invisible pit
## next to an invisible wall. A simulation you cannot see cannot be play-tested, and Gates A-D
## all require looking at the thing.
##
## Dumb viewer, per the Prime Directive: this reads ChunkData and owns no state. Geometry here is
## PURELY cosmetic — collision is resolved against `tile_map` by CollisionResolveSystem, never
## against these meshes. There are no CollisionShape3D nodes and there is no StaticBody3D.
##
## MultiMesh, not one node per tile: 64x64 is 4,096 tiles, and 4,096 MeshInstance3D nodes costs
## more per frame than the entire ECS.
class_name TerrainView
extends Node3D

## Water is redrawn on a timer rather than every frame. The CA runs at 15 Hz, so a 60 Hz rebuild
## would be three redundant passes out of four.
const WATER_REFRESH_S: float = 0.25

## Below this many units a cell is a damp patch, not a puddle, and drawing it is noise.
const WATER_VISIBLE_MIN_UNITS: int = 8

## How tall a solid tile is drawn. Single source of truth: `DebugOverlay` marches the cursor ray
## against this same height, so a wall you can see is a wall the cursor readout agrees about.
const WALL_HEIGHT_M: float = 2.4

## How far out from the player's chunk terrain is drawn. Matches the Active set radius, so the
## visible world is exactly the simulated one.
const RENDER_RADIUS_CHUNKS: int = 1

## How far a stairwell sits above or below the floor around it. Enough to read as a step from
## the camera's height without being something you have to climb.
const STAIR_RISE_M: float = 0.22
const STAIR_SINK_M: float = -0.18

## Beacon column height. Taller than the 2.4 m walls by a clear margin, so it is never hidden by
## the building it stands next to.
const BEACON_HEIGHT_M: float = 9.0

var _floors: MultiMeshInstance3D = null
var _walls: MultiMeshInstance3D = null
var _water: MultiMeshInstance3D = null
var _stairs_down: MultiMeshInstance3D = null
var _stairs_up: MultiMeshInstance3D = null
var _beacons_down: MultiMeshInstance3D = null
var _beacons_up: MultiMeshInstance3D = null
var _accumulator: float = 0.0
var _drawn_chunks: int = 0


func _ready() -> void:
	_floors = _make_layer(Vector3(1.0, 0.1, 1.0), Color(0.42, 0.40, 0.38))
	_walls = _make_layer(Vector3(1.0, WALL_HEIGHT_M, 1.0), Color(0.24, 0.23, 0.26))
	_water = _make_layer(Vector3(1.0, 0.12, 1.0), Color(0.20, 0.45, 0.75, 0.65), true)
	# Down SINKS and is cold; up RISES and is warm. Colour alone is not an accessible encoding,
	# so the direction is carried by geometry as well as hue.
	_stairs_down = _make_layer(Vector3(0.9, 0.5, 0.9), Color(0.20, 0.70, 0.85))
	_stairs_up = _make_layer(Vector3(0.9, 0.5, 0.9), Color(0.95, 0.70, 0.20))
	# BEACONS. A stairwell is ONE TILE in a village 192 m across; a tile-sized marker is visible
	# only once you are already standing on it, which is no help at all in finding the way down.
	# A translucent column carries it above the rooftops so it can be walked toward.
	_beacons_down = _make_layer(
		Vector3(0.28, BEACON_HEIGHT_M, 0.28), Color(0.20, 0.80, 0.95, 0.30), true
	)
	_beacons_up = _make_layer(
		Vector3(0.28, BEACON_HEIGHT_M, 0.28), Color(1.0, 0.75, 0.25, 0.30), true
	)
	World.world_ready.connect(_on_world_ready)
	if World.booted:
		rebuild()


func _process(delta: float) -> void:
	if not World.booted:
		return
	_accumulator += delta
	if _accumulator < WATER_REFRESH_S:
		return
	_accumulator = 0.0
	# The player can walk into a chunk that did not exist when the terrain was last built, so
	# the visible set is re-checked rather than assumed fixed.
	var chunks: Array[ChunkData] = visible_chunks()
	if chunks.size() != _drawn_chunks:
		_rebuild_tiles(chunks)
	_rebuild_water_all(chunks)


func _on_world_ready(_chunk_id: Vector3i) -> void:
	rebuild()


## Every chunk worth drawing: the player's own, plus its neighbours out to the render radius.
##
## Rendering only `active_chunk` was correct while the world was one room and wrong the moment
## there were neighbours — the village is nine chunks, and eight of them were invisible, so the
## world ended in a cliff two steps from spawn.
func visible_chunks() -> Array[ChunkData]:
	var out: Array[ChunkData] = []
	if World.grid == null:
		if World.active_chunk != null:
			out.append(World.active_chunk)
		return out
	var centre: Vector3i = World.player_chunk_id
	for dy in range(-RENDER_RADIUS_CHUNKS, RENDER_RADIUS_CHUNKS + 1):
		for dx in range(-RENDER_RADIUS_CHUNKS, RENDER_RADIUS_CHUNKS + 1):
			var chunk_id := Vector3i(centre.x + dx, centre.y + dy, centre.z)
			# Only chunks that already EXIST. Asking the grid would generate the whole
			# neighbourhood just to draw it, which is the opposite of streaming.
			if World.grid.has_chunk(chunk_id):
				out.append(World.grid.chunk_at(chunk_id))
	return out


func rebuild() -> void:
	var chunks: Array[ChunkData] = visible_chunks()
	if chunks.is_empty():
		return
	_rebuild_tiles(chunks)
	_rebuild_water_all(chunks)


## Floors sit at each tile's own elevation, so the ledge reads as raised and the pit as sunken
## without any extra authoring. That elevation IS the value the step/drop rule tests.
func _rebuild_tiles(chunks: Array[ChunkData]) -> void:
	var floor_transforms: Array[Transform3D] = []
	var wall_transforms: Array[Transform3D] = []
	var down_transforms: Array[Transform3D] = []
	var up_transforms: Array[Transform3D] = []
	var down_beacons: Array[Transform3D] = []
	var up_beacons: Array[Transform3D] = []
	for chunk in chunks:
		for y in WorldConstants.CHUNK_TILES:
			for x in WorldConstants.CHUNK_TILES:
				var centre: Vector3 = chunk.tile_to_world(x, y)
				if chunk.is_solid(x, y):
					var lift := Vector3(0.0, WALL_HEIGHT_M * 0.5, 0.0)
					wall_transforms.append(Transform3D(Basis.IDENTITY, centre + lift))
					continue
				# STAIRS ARE DRAWN, not merely walkable. They were functional and INVISIBLE:
				# the tile kind existed, the transition worked, and nothing on screen said so —
				# which makes the only route off the surface something you have to be told about.
				if _tile_kind(chunk, x, y) == ChunkData.TILE_STAIRS:
					var beacon := Vector3(0.0, BEACON_HEIGHT_M * 0.5, 0.0)
					if Vector2i(x, y) == FloorGenerator.STAIR_UP_TILE:
						up_transforms.append(
							Transform3D(Basis.IDENTITY, centre + Vector3(0, STAIR_RISE_M, 0))
						)
						up_beacons.append(Transform3D(Basis.IDENTITY, centre + beacon))
					else:
						down_transforms.append(
							Transform3D(Basis.IDENTITY, centre + Vector3(0, STAIR_SINK_M, 0))
						)
						down_beacons.append(Transform3D(Basis.IDENTITY, centre + beacon))
					continue
				floor_transforms.append(Transform3D(Basis.IDENTITY, centre))
	_fill(_floors, floor_transforms)
	_fill(_walls, wall_transforms)
	_fill(_stairs_down, down_transforms)
	_fill(_stairs_up, up_transforms)
	_fill(_beacons_down, down_beacons)
	_fill(_beacons_up, up_beacons)
	_drawn_chunks = chunks.size()


func _tile_kind(chunk: ChunkData, x: int, y: int) -> int:
	return chunk.tile_map[WorldConstants.cell_index(x, y)]


func _rebuild_water_all(chunks: Array[ChunkData]) -> void:
	var transforms: Array[Transform3D] = []
	for chunk in chunks:
		_collect_water(chunk, transforms)
	_fill(_water, transforms)


func _collect_water(chunk: ChunkData, transforms: Array[Transform3D]) -> void:
	if chunk == null:
		return
	for y in WorldConstants.CHUNK_TILES:
		for x in WorldConstants.CHUNK_TILES:
			var units: int = chunk.fluid_at(x, y)
			if units < WATER_VISIBLE_MIN_UNITS:
				continue
			# Depth is visible: a full cell stands taller than a spreading film.
			var fill: float = clampf(float(units) / float(WorldConstants.MAX_CELL_VOLUME), 0.08, 1.0)
			var basis := Basis.IDENTITY.scaled(Vector3(1.0, fill * 4.0, 1.0))
			var centre: Vector3 = chunk.tile_to_world(x, y)
			transforms.append(Transform3D(basis, centre + Vector3(0, 0.06, 0)))


func _fill(layer: MultiMeshInstance3D, transforms: Array[Transform3D]) -> void:
	layer.multimesh.instance_count = transforms.size()
	for i in transforms.size():
		layer.multimesh.set_instance_transform(i, transforms[i])


func _make_layer(size: Vector3, colour: Color, transparent: bool = false) -> MultiMeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	box.material = material

	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = box

	var node := MultiMeshInstance3D.new()
	node.multimesh = multi
	add_child(node)
	return node
