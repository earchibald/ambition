## Third-person follow camera with a DEADZONE. A pure viewer node: it reads ECS data through
## ViewManager and owns no state the simulation can see.
##
## Perspective is a real design decision that combat depends on, because the swing direction is
## camera-relative. Third person is chosen so the 2.5D elevation steps and drops are legible.
##
## WHY A DEADZONE, AND WHY NO SMOOTHING
##
## The first version lerped the camera toward the player every frame at rate 8.0, while
## ViewManager separately lerped the player's own avatar toward ECS truth at rate 15.0. Two
## independent exponential lags chasing the same moving target at different speeds means the
## avatar drifts RELATIVE TO THE FRAME IT SITS IN whenever you accelerate or stop, so the whole
## world appears to slosh around the player. It reads as motion sickness, not as smoothness.
##
## Both halves are now exact. ViewManager interpolates between fixed simulation steps, and this
## rig does not smooth at all: inside the deadzone the camera is perfectly still, and outside it
## the camera moves EXACTLY as far as needed to put the player back on the boundary. Rigid
## tracking has zero relative motion, which is the thing that was causing the queasiness.
class_name CameraRig
extends Node3D

## Camera position relative to its focus point. A steep pitch is what makes the 0.4 m ledge and
## the 2.5 m pit read as different heights rather than as the same flat shape.
const FOLLOW_OFFSET := Vector3(0.0, 11.0, 9.0)

## How far the player may move from the focus point before the camera moves at all, in metres.
## Ordinary walking and small course corrections should cost no camera motion whatsoever.
@export var deadzone_radius_m: float = 5.0

## Vertical deadzone, separate and larger: stepping onto a 0.4 m ledge must not move the camera,
## and falling 2.5 m into the pit must.
@export var deadzone_height_m: float = 2.0

@export var camera: Camera3D

var _focus: Vector3 = Vector3.ZERO
var _initialised: bool = false


func _ready() -> void:
	if camera == null:
		camera = get_node_or_null("Camera3D")
	# Orientation is set ONCE and never touched again. A per-frame `look_at` re-aims the camera as
	# the player moves inside the deadzone, rotating the whole world a fraction of a degree every
	# frame. That was the most nauseating part of the original rig, and it is invisible in a
	# screenshot — only sustained motion reveals it.
	if camera != null:
		camera.position = Vector3.ZERO
		camera.look_at_from_position(FOLLOW_OFFSET, Vector3.ZERO, Vector3.UP)


func _process(_delta: float) -> void:
	if not World.booted:
		return
	var row: int = ECSManager.resolve(ECSManager.player_handle())
	if row < 0:
		return

	# Track the DRAWN position, not raw ECS truth. Following the simulation directly would put the
	# camera one interpolation fraction ahead of the avatar it is framing, reintroducing exactly
	# the relative drift this rig exists to remove.
	var target: Vector3 = view_position(row)
	if not _initialised:
		_focus = target
		_initialised = true
	_focus = pull_focus(_focus, target)
	global_position = _focus + FOLLOW_OFFSET


## Moves the focus the minimum distance that brings `target` back inside the deadzone. Horizontal
## and vertical are handled separately, so falling does not also shove the camera sideways.
func pull_focus(focus: Vector3, target: Vector3) -> Vector3:
	var flat := Vector2(target.x - focus.x, target.z - focus.z)
	var distance: float = flat.length()
	if distance > deadzone_radius_m:
		var push: Vector2 = flat.normalized() * (distance - deadzone_radius_m)
		focus.x += push.x
		focus.z += push.y

	var rise: float = target.y - focus.y
	if absf(rise) > deadzone_height_m:
		focus.y += rise - signf(rise) * deadzone_height_m
	return focus


## The position the player is DRAWN at this frame, which is what the camera must frame.
func view_position(row: int) -> Vector3:
	var view: ViewManager = get_parent().get_node_or_null("ViewManager")
	if view == null:
		return ECSManager.position_of(row)
	return view.visual_position_of(row)
