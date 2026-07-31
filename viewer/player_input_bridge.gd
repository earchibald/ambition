## Translates hardware input into ActionIntents. This is the ONLY place input touches the sim.
##
## Pressing W does not move the player. It pushes a MOVE intent onto Entity 0's action queue,
## and the ECS decides what that means.
class_name PlayerInputBridge
extends Node

@export var camera_path: NodePath

var intents_pushed: int = 0

var _camera: Camera3D = null


func _ready() -> void:
	if not camera_path.is_empty():
		_camera = get_node_or_null(camera_path)


func _physics_process(_delta: float) -> void:
	if not World.booted:
		return
	var handle: int = ECSManager.player_handle()
	var row: int = ECSManager.resolve(handle)
	if row < 0:
		return

	var raw: Vector2 = Input.get_vector(
		&"move_left", &"move_right", &"move_forward", &"move_back"
	)
	# Camera-relative on the XZ plane so "forward" means what the player sees.
	var basis_forward := Vector3(0.0, 0.0, 1.0)
	var basis_right := Vector3(1.0, 0.0, 0.0)
	if _camera != null:
		var camera_basis: Basis = _camera.global_transform.basis
		basis_forward = Vector3(camera_basis.z.x, 0.0, camera_basis.z.z).normalized()
		basis_right = Vector3(camera_basis.x.x, 0.0, camera_basis.x.z).normalized()

	var direction: Vector3 = basis_right * raw.x + basis_forward * raw.y
	ECSManager.push_intent(row, ActionIntent.create(ActionIntent.MOVE, EH.INVALID, direction))
	intents_pushed += 1

	if Input.is_action_just_pressed(&"attack"):
		_push_attack(row, direction)
	if Input.is_action_just_pressed(&"interact"):
		_push_interact(row)
	if Input.is_action_just_pressed(&"inspect"):
		# Bullet-time scales delta, never the 60 Hz tick rate (ADR-9).
		GameLoopManager.time_scale = 0.2 if GameLoopManager.time_scale == 1.0 else 1.0


## Targeting goes through the ECS PickSystem, never a Godot raycast.
func _push_attack(row: int, direction: Vector3) -> void:
	var swing: Vector3 = direction if direction.length() > 0.01 else Vector3(0.0, 0.0, 1.0)
	var target: int = GameLoopManager.picking.melee_target(row, swing, GameLoopManager.spatial_hash)
	if EH.is_valid(target):
		ECSManager.push_intent(row, ActionIntent.create(ActionIntent.MELEE, target, swing))
		intents_pushed += 1


func _push_interact(row: int) -> void:
	if _camera == null or World.active_chunk == null:
		return
	var origin: Vector3 = _camera.global_position
	var forward: Vector3 = -_camera.global_transform.basis.z
	var target: int = GameLoopManager.picking.interact_target(
		origin, forward, GameLoopManager.spatial_hash, World.active_chunk
	)
	if EH.is_valid(target):
		ECSManager.push_intent(row, ActionIntent.create(ActionIntent.TAKE, target))
		intents_pushed += 1
