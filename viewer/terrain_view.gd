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

var _floors: MultiMeshInstance3D = null
var _walls: MultiMeshInstance3D = null
var _water: MultiMeshInstance3D = null
var _accumulator: float = 0.0


func _ready() -> void:
	_floors = _make_layer(Vector3(1.0, 0.1, 1.0), Color(0.42, 0.40, 0.38))
	_walls = _make_layer(Vector3(1.0, 2.4, 1.0), Color(0.24, 0.23, 0.26))
	_water = _make_layer(Vector3(1.0, 0.12, 1.0), Color(0.20, 0.45, 0.75, 0.65), true)
	World.world_ready.connect(_on_world_ready)
	if World.booted:
		_on_world_ready(World.player_chunk_id)


func _process(delta: float) -> void:
	if not World.booted:
		return
	_accumulator += delta
	if _accumulator < WATER_REFRESH_S:
		return
	_accumulator = 0.0
	_rebuild_water(World.active_chunk)


func _on_world_ready(_chunk_id: Vector3i) -> void:
	var chunk: ChunkData = World.active_chunk
	if chunk == null:
		return
	_rebuild_tiles(chunk)
	_rebuild_water(chunk)


## Floors sit at each tile's own elevation, so the ledge reads as raised and the pit as sunken
## without any extra authoring. That elevation IS the value the step/drop rule tests.
func _rebuild_tiles(chunk: ChunkData) -> void:
	var floor_transforms: Array[Transform3D] = []
	var wall_transforms: Array[Transform3D] = []
	for y in WorldConstants.CHUNK_TILES:
		for x in WorldConstants.CHUNK_TILES:
			var centre: Vector3 = chunk.tile_to_world(x, y)
			if chunk.is_solid(x, y):
				wall_transforms.append(Transform3D(Basis.IDENTITY, centre + Vector3(0, 1.2, 0)))
			else:
				floor_transforms.append(Transform3D(Basis.IDENTITY, centre))
	_fill(_floors, floor_transforms)
	_fill(_walls, wall_transforms)


func _rebuild_water(chunk: ChunkData) -> void:
	if chunk == null:
		return
	var transforms: Array[Transform3D] = []
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
	_fill(_water, transforms)


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
