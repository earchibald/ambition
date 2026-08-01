## The dumb viewer. Spawns and pools plain Node3D visuals for ECS entities.
##
## Owns NO authoritative state. It only LISTENS to ECSEvents and reads ECS positions. It never
## writes to the ECS. No CharacterBody3D, no RigidBody3D, no CollisionShape3D.
##
## This is a Node in Main.tscn, NOT an autoload: it holds scene-tree children, and an autoload
## that parents visuals outlives the scene they belong to.
class_name ViewManager
extends Node3D

## FIXED-TIMESTEP INTERPOLATION, not exponential smoothing.
##
## The old `lerp(ecs_position, 1 - exp(-15 * delta))` chased a MOVING target, and chasing a moving
## target never catches it: at speed v with rate k the visual settles a constant v/k behind the
## truth. At the 4 m/s walk speed that is a permanent 0.27 m lag which appears on acceleration and
## vanishes on stop. That is the "swimmy" feel — the avatar is rubber-banded to the player's own
## input.
##
## Interpolating between the PREVIOUS and CURRENT physics positions instead is exact: it is the
## standard fix for 60 Hz simulation under an uncapped render rate, it has zero steady-state lag,
## and it has no tuning constant to get wrong.
## Child node name for the heading marker, so pooled visuals can find and strip it.
const NOSE_NAME: String = "HeadingNose"

## Path to the PlayerInputBridge, read for the player's aim direction. Viewer-to-viewer only.
@export var aim_source_path: NodePath

var spawned: int = 0
var despawned: int = 0
var pooled: int = 0

var _visuals: Dictionary = {}
var _previous: Dictionary = {}
var _current: Dictionary = {}
var _aim_source: PlayerInputBridge = null
var _pool: Array[Node3D] = []


func _ready() -> void:
	ECSEvents.entity_created.connect(_on_entity_created)
	ECSEvents.entity_destroyed.connect(_on_entity_destroyed)
	ECSEvents.item_taken.connect(_on_item_taken)
	ECSEvents.entity_died.connect(_on_entity_died)
	if not aim_source_path.is_empty():
		_aim_source = get_node_or_null(aim_source_path)


func _on_entity_created(entity: int, tags: Array, initial_pos: Vector3) -> void:
	var row: int = EH.index_of(entity)
	if _visuals.has(row):
		return
	var node: Node3D = _acquire()
	node.global_position = initial_pos
	_style(node, tags)
	_visuals[row] = node
	# Seed both endpoints, or the first frame interpolates from the world origin and every new
	# entity visibly flies in from (0, 0, 0).
	_previous[row] = initial_pos
	_current[row] = initial_pos
	spawned += 1


func _on_entity_destroyed(entity: int) -> void:
	var row: int = EH.index_of(entity)
	if not _visuals.has(row):
		return
	var node: Node3D = _visuals[row]
	_visuals.erase(row)
	_previous.erase(row)
	_current.erase(row)
	_release(node)
	despawned += 1


## Samples ECS truth once per SIMULATION tick. Runs after GameLoopManager because autoloads are
## processed before scene nodes, so `_current` always holds the position this tick produced.
func _physics_process(_delta: float) -> void:
	for row in _visuals.keys():
		var position: Vector3 = ECSManager.position_of(row)
		_previous[row] = _current.get(row, position)
		_current[row] = position


## Draws each visual between the last two simulation positions. Iterates a KEY SNAPSHOT: a signal
## handler firing mid-iteration would otherwise mutate the dictionary being walked.
func _process(_delta: float) -> void:
	var fraction: float = Engine.get_physics_interpolation_fraction()
	for row in _visuals.keys():
		# An entity destroyed between its signal and this frame must not be dereferenced.
		if not ECSManager.is_alive(ECSManager.handle_of(row)):
			_on_entity_destroyed(ECSManager.handle_of(row))
			continue
		var from: Vector3 = _previous.get(row, _current.get(row, Vector3.ZERO))
		var to: Vector3 = _current.get(row, from)
		_visuals[row].global_position = from.lerp(to, fraction)
	_face_player()


## Turns the player's body to face the aim direction, and shows a nose so the turn is VISIBLE.
##
## A cube has no front. Until this existed the only way to know which way you were pointing was to
## infer it from what you could hit — the heading was real, enforced by the melee arc, and shown
## nowhere on the character.
##
## Facing is not yet an ECS component (no sprint owns it), so for Sprint 1 the viewer reads the
## input bridge directly. Both are viewer nodes, so no simulation state crosses the boundary. When
## NPCs need facing this becomes a real component and this function reads that instead.
func _face_player() -> void:
	if _aim_source == null:
		return
	var row: int = EH.index_of(ECSManager.player_handle())
	if not _visuals.has(row):
		return
	var aim: Vector3 = _aim_source.last_aim
	if aim.length() < 0.01:
		return
	_visuals[row].global_rotation = Vector3(0.0, atan2(aim.x, aim.z), 0.0)


## Death must be VISIBLE. The corpse conversion was already correct in the ECS and changed
## nothing on screen, so from the player's seat killing something and missing it looked the same.
func _on_entity_died(entity: int, _cause: StringName) -> void:
	var row: int = EH.index_of(entity)
	if not _visuals.has(row):
		return
	_style(_visuals[row], [&"Corpse"] as Array[StringName])
	# A corpse lies on the ground rather than hovering at standing height.
	_visuals[row].global_rotation = Vector3.ZERO


## A carried item has no world presence, so it must stop being drawn. The ENTITY is still alive —
## the inventory holds its handle — but `InventorySystem` has stripped its POSITION, so leaving
## the visual behind would paint it on the floor forever at the spot it was collected from.
func _on_item_taken(_taker: int, item: int, _reason: StringName) -> void:
	_on_entity_destroyed(item)


## The position a visual is DRAWN at this frame. The camera reads this rather than raw ECS truth,
## so the player's avatar cannot drift relative to the frame it sits in.
func visual_position_of(row: int) -> Vector3:
	if not _current.has(row):
		return ECSManager.position_of(row)
	var from: Vector3 = _previous.get(row, _current[row])
	return from.lerp(_current[row], Engine.get_physics_interpolation_fraction())


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
	var wears_a_nose: bool = false
	if tags.has(&"Corpse"):
		# Flat, grey and unmistakable. A body that keeps standing looks alive, and "no apparent
		# change when they die" was the exact play-test complaint.
		box.size = Vector3(0.7, 0.25, 0.7)
		colour = Color(0.30, 0.28, 0.30)
	elif tags.has(&"Item"):
		box.size = Vector3(0.2, 0.2, 0.2)
		colour = Color(0.95, 0.72, 0.25)
	elif tags.has(&"Citizen"):
		# TALL AND GREEN. Villagers used the same red box as the corpse rat, so the only way to
		# tell a neighbour from a monster was to hit it and find out.
		box.size = Vector3(0.45, 1.6, 0.45)
		colour = Color(0.45, 0.78, 0.42)
	elif tags.has(&"Creature"):
		box.size = Vector3(0.5, 0.5, 0.5)
		colour = Color(0.80, 0.30, 0.28)
	else:
		box.size = Vector3(0.6, 1.8, 0.6)
		colour = Color(0.35, 0.85, 0.95)
		wears_a_nose = true
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	box.material = material
	mesh_node.mesh = box
	_fit_nose(mesh_node, wears_a_nose)


## A cube looks identical from all four sides, so rotating one communicates nothing. The nose is
## the asymmetry that makes the rotation readable at a glance.
func _fit_nose(node: MeshInstance3D, wanted: bool) -> void:
	var existing: Node = node.get_node_or_null(NOSE_NAME)
	if not wanted:
		# Pooled nodes are reused across entity kinds; a leftover nose would mark the wrong thing.
		# Detached FIRST: `queue_free` is deferred, so the child is still attached and still drawn
		# for the remainder of this frame if it is only queued.
		if existing != null:
			node.remove_child(existing)
			existing.queue_free()
		return
	if existing != null:
		return
	# Sized to be legible at the camera's 11 m standoff, where the whole body is only ~40 px tall.
	var wedge := BoxMesh.new()
	wedge.size = Vector3(0.26, 0.26, 0.6)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.95, 0.35)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wedge.material = material

	var nose := MeshInstance3D.new()
	nose.name = NOSE_NAME
	nose.mesh = wedge
	# Forward is +Z, matching the aim convention used by the melee arc.
	nose.position = Vector3(0.0, 0.55, 0.5)
	node.add_child(nose)


func counters() -> Dictionary:
	return {
		"visuals_live": _visuals.size(),
		"visuals_spawned": spawned,
		"visuals_despawned": despawned,
		"visuals_pool": _pool.size(),
	}
