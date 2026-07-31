## Translates hardware input into ActionIntents. This is the ONLY place input touches the sim.
##
## Pressing W does not move the player. It pushes a MOVE intent onto Entity 0's action queue,
## and the ECS decides what that means.
class_name PlayerInputBridge
extends Node

@export var camera_path: NodePath
@export var overlay_path: NodePath

var intents_pushed: int = 0

## The direction the player is currently aiming, recomputed every frame from the cursor. Exposed
## so DebugGizmos can DRAW it: without this the player is a featureless box with no on-screen
## indication of facing, and the swing arc is invisible.
var last_aim: Vector3 = Vector3(0.0, 0.0, 1.0)

var _camera: Camera3D = null
var _overlay: DebugOverlay = null


func _ready() -> void:
	if not camera_path.is_empty():
		_camera = get_node_or_null(camera_path)
	if not overlay_path.is_empty():
		_overlay = get_node_or_null(overlay_path)


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

	# Recomputed every frame, not only on click, so the gizmo shows where a swing WOULD go.
	last_aim = _aim_direction(row, direction)

	if Input.is_action_just_pressed(&"attack"):
		_push_attack(row, last_aim)
	if Input.is_action_just_pressed(&"interact"):
		_push_interact(row)
	if Input.is_action_just_pressed(&"inspect"):
		_select_under_cursor()
	if Input.is_action_just_pressed(&"slow_time"):
		# Bullet-time scales delta, never the 60 Hz tick rate (ADR-9).
		GameLoopManager.time_scale = 0.2 if GameLoopManager.time_scale == 1.0 else 1.0


## You swing where you POINT, not where you last walked.
##
## The swing arc is +/-60 degrees around this vector. Taking it from the movement keys meant a
## standing player swung along a hard-coded +Z, so a rat standing due east sat 90 degrees outside
## the arc and clicking on it did nothing — with no message explaining why.
## Aim comes from `PickSystem.aim_direction`, which is continuous everywhere. It replaced a
## terrain march that fell back to a hard-coded `+Z` whenever the march found nothing — which is
## most of the upper half of the screen, since those rays reach the horizon or outrun the march
## budget. Sweeping the cursor past the player therefore made the aim SNAP to a fixed direction
## instead of continuing to rotate.
func _aim_direction(row: int, movement: Vector3) -> Vector3:
	if _camera != null:
		var mouse: Vector2 = _camera.get_viewport().get_mouse_position()
		var feet: Vector3 = ECSManager.position_of(row)
		var bounds: BoundsComponent = ECSManager.bounds.get(row)
		if bounds != null:
			feet.y -= bounds.half_extents.y
		var aim: Vector3 = PickSystem.aim_direction(
			feet, _camera.project_ray_origin(mouse), _camera.project_ray_normal(mouse)
		)
		if aim.length() > 0.01:
			return aim
	if movement.length() > 0.01:
		return movement.normalized()
	# Genuinely undefined only when the cursor sits on the actor and nobody is moving. Holding the
	# previous aim beats snapping to a constant.
	return last_aim


## Targeting goes through the ECS PickSystem, never a Godot raycast.
func _push_attack(row: int, swing: Vector3) -> void:
	var target: int = GameLoopManager.picking.melee_target(row, swing, GameLoopManager.spatial_hash)
	if not EH.is_valid(target):
		# Silence is the worst possible feedback. Say why nothing happened.
		ECSEvents.action_rejected.emit(ECSManager.handle_of(row), &"attack", &"nothing in reach")
		return
	ECSManager.push_intent(row, ActionIntent.create(ActionIntent.MELEE, target, swing))
	intents_pushed += 1


## Mouse-cursor entity inspection. `DebugOverlay.select_row` existed but NOTHING called it, so
## the inspector — the single highest-value debug surface — was unreachable from the game.
##
## The ray is built from the camera (viewer maths) and then handed to PickSystem, which resolves
## it against the SpatialHash and the tile grid. No Godot raycast is involved.
func _select_under_cursor() -> void:
	if _overlay == null or _camera == null or World.active_chunk == null:
		return
	var mouse: Vector2 = _camera.get_viewport().get_mouse_position()
	var result: Dictionary = GameLoopManager.picking.pick(
		_camera.project_ray_origin(mouse),
		_camera.project_ray_normal(mouse),
		GameLoopManager.spatial_hash,
		World.active_chunk
	)
	var handle: int = result["entity_handle"]
	# Nothing under the cursor falls back to the player, so Tab always shows something useful.
	_overlay.select_row(
		EH.index_of(handle) if EH.is_valid(handle) else EH.index_of(ECSManager.player_handle())
	)


## `E` takes what is under the cursor, or failing that the nearest thing within arm's reach.
##
## The ray now runs through the MOUSE rather than straight out of the camera's nose, and reach is
## measured from the player. The old version cast from the camera and compared the ray's own
## travel against a 2.5 m reach — the camera sits ~14 m away, so it never once succeeded.
func _push_interact(row: int) -> void:
	if _camera == null or World.active_chunk == null:
		return
	var mouse: Vector2 = _camera.get_viewport().get_mouse_position()
	var target: int = GameLoopManager.picking.interact_target(
		row,
		_camera.project_ray_origin(mouse),
		_camera.project_ray_normal(mouse),
		GameLoopManager.spatial_hash,
		World.active_chunk
	)
	if not EH.is_valid(target):
		ECSEvents.action_rejected.emit(ECSManager.handle_of(row), &"take", &"nothing in reach")
		return
	ECSManager.push_intent(row, ActionIntent.create(ActionIntent.TAKE, target))
	intents_pushed += 1
