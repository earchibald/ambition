## The dumb viewer. Spawns and pools plain Node3D visuals for ECS entities.
##
## Owns NO authoritative state. It only LISTENS to ECSEvents and reads ECS positions. It never
## writes to the ECS. No CharacterBody3D, no RigidBody3D, no CollisionShape3D.
##
## This is a Node in Main.tscn, NOT an autoload: it holds scene-tree children, and an autoload
## that parents visuals outlives the scene they belong to.
class_name ViewManager
extends Node3D

## Exponential smoothing toward the ECS position. `lerp(target, delta * 15.0)` overshoots badly
## at large delta — at delta = 0.5 the weight is 7.5, i.e. 7.5x the distance. This form is
## frame-rate independent and cannot overshoot.
const SMOOTHING_RATE: float = 15.0

var spawned: int = 0
var despawned: int = 0
var pooled: int = 0

var _visuals: Dictionary = {}
var _pool: Array[Node3D] = []


func _ready() -> void:
	ECSEvents.entity_created.connect(_on_entity_created)
	ECSEvents.entity_destroyed.connect(_on_entity_destroyed)


func _on_entity_created(entity: int, tags: Array, initial_pos: Vector3) -> void:
	var row: int = EH.index_of(entity)
	if _visuals.has(row):
		return
	var node: Node3D = _acquire()
	node.global_position = initial_pos
	_style(node, tags)
	_visuals[row] = node
	spawned += 1


func _on_entity_destroyed(entity: int) -> void:
	var row: int = EH.index_of(entity)
	if not _visuals.has(row):
		return
	var node: Node3D = _visuals[row]
	_visuals.erase(row)
	_release(node)
	despawned += 1


## Interpolates visuals toward ECS truth. Iterates a KEY SNAPSHOT: a signal handler firing
## mid-iteration would otherwise mutate the dictionary being walked.
func _process(delta: float) -> void:
	var weight: float = 1.0 - exp(-SMOOTHING_RATE * delta)
	for row in _visuals.keys():
		# An entity destroyed between its signal and this frame must not be dereferenced.
		if not ECSManager.is_alive(ECSManager.handle_of(row)):
			_on_entity_destroyed(ECSManager.handle_of(row))
			continue
		var node: Node3D = _visuals[row]
		node.global_position = node.global_position.lerp(ECSManager.position_of(row), weight)


func _acquire() -> Node3D:
	if not _pool.is_empty():
		var reused: Node3D = _pool.pop_back()
		reused.visible = true
		pooled += 1
		return reused
	# No mesh here: `_style` assigns a fresh one per entity, so a pooled node never inherits the
	# previous occupant's appearance.
	var node := MeshInstance3D.new()
	add_child(node)
	return node


func _release(node: Node3D) -> void:
	node.visible = false
	_pool.append(node)


## Purely cosmetic. Tag-driven colour is always paired with a distinct SIZE here, because hue
## alone is not an accessible encoding — and because grey-on-grey made every entity in the test
## arena invisible against the stone floor, which is how a "working" build looked broken.
func _style(node: Node3D, tags: Array) -> void:
	if not node is MeshInstance3D:
		return
	var mesh_node: MeshInstance3D = node
	# Each visual needs its OWN mesh and material. A pooled node handed back with the previous
	# occupant's mesh would repaint every entity that ever shared it.
	var box := BoxMesh.new()
	var colour: Color
	if tags.has(&"Item"):
		box.size = Vector3(0.2, 0.2, 0.2)
		colour = Color(0.95, 0.72, 0.25)
	elif tags.has(&"Creature"):
		box.size = Vector3(0.5, 0.5, 0.5)
		colour = Color(0.80, 0.30, 0.28)
	else:
		box.size = Vector3(0.6, 1.8, 0.6)
		colour = Color(0.35, 0.85, 0.95)
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	box.material = material
	mesh_node.mesh = box


func counters() -> Dictionary:
	return {
		"visuals_live": _visuals.size(),
		"visuals_spawned": spawned,
		"visuals_despawned": despawned,
		"visuals_pool": _pool.size(),
	}
