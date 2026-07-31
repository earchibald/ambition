## Third-person follow camera. A pure viewer node: it reads ECS position and owns no state.
##
## Perspective is a real design decision that combat depends on, because the swing direction is
## camera-relative. Third person is chosen so the 2.5D elevation steps and drops are legible.
class_name CameraRig
extends Node3D

## Tuned by looking at it, not by guessing. The first values (y=6, z=8) put the horizon halfway
## up the screen and gave half the frame to empty floor, so the 0.4 m ledge and the 2.5 m pit
## read as identical flat shapes. A steeper pitch is what makes 2.5D elevation legible, which is
## the whole reason this camera is third-person.
const FOLLOW_OFFSET := Vector3(0.0, 11.0, 9.0)
const FOLLOW_RATE: float = 8.0

@export var camera: Camera3D


func _ready() -> void:
	if camera == null:
		camera = get_node_or_null("Camera3D")


func _process(delta: float) -> void:
	if not World.booted:
		return
	var row: int = ECSManager.resolve(ECSManager.player_handle())
	if row < 0:
		return
	var target: Vector3 = ECSManager.position_of(row)
	var desired: Vector3 = target + FOLLOW_OFFSET
	# Frame-rate independent smoothing; cannot overshoot at large delta.
	var weight: float = 1.0 - exp(-FOLLOW_RATE * delta)
	global_position = global_position.lerp(desired, weight)
	if camera != null:
		camera.look_at(target, Vector3.UP)
