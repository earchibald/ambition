## Translates hardware input into ActionIntents. This is the ONLY place input touches the sim.
##
## Pressing W does not move the player. It pushes a MOVE intent onto Entity 0's action queue,
## and the ECS decides what that means.
class_name PlayerInputBridge
extends Node

## Damage per press of the debug injure key. A quarter of a full health bar, so reaching death
## takes four deliberate presses rather than one twitch.
const DEBUG_HURT_AMOUNT: float = 25.0

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

	# AIM FIRST, then movement — the order is load-bearing now that movement is BODY-relative.
	# `_aim_direction` reads the cursor and only falls back to a movement vector when the cursor
	# cannot answer, so passing zero here breaks what would otherwise be a circular dependency:
	# facing would depend on movement which depends on facing.
	last_aim = _aim_direction(row, Vector3.ZERO)

	var direction: Vector3 = movement_from(raw, last_aim)
	# Precision mode is expressed as a SHORTER intent vector, not as a second speed constant.
	# `_apply_intent` normalises only vectors longer than 1, so a 0.35-length direction is
	# 35% speed — the ECS keeps one movement law and the viewer just asks for less of it.
	if Input.is_action_pressed(&"precision_move"):
		direction *= WorldConstants.PRECISION_SPEED_SCALE
	# While the free camera flies, WASD belongs to the CAMERA and the body stands still. A zero
	# intent is still pushed so the player halts rather than gliding on their last velocity.
	if _rig() != null and _rig().free_flight:
		direction = Vector3.ZERO
	ECSManager.push_intent(row, ActionIntent.create(ActionIntent.MOVE, EH.INVALID, direction))
	intents_pushed += 1

	# A click on the debug panel belongs to the panel. The bridge POLLS rather than consuming
	# events, so it has to ask rather than relying on the event being marked handled.
	var ui_has_mouse: bool = _overlay != null and _overlay.wants_mouse()

	if not ui_has_mouse and Input.is_action_just_pressed(&"attack"):
		_push_attack(row, last_aim)
	if not ui_has_mouse and Input.is_action_just_pressed(&"interact"):
		_push_interact(row)
	if not ui_has_mouse and Input.is_action_just_pressed(&"inspect"):
		_select_under_cursor()
	if Input.is_action_just_pressed(&"cast"):
		_push_cast(row, last_aim)
	if Input.is_action_just_pressed(&"debug_hurt"):
		_debug_hurt(row)
	if Input.is_action_just_pressed(&"debug_respawn"):
		_debug_respawn()
	if Input.is_action_just_pressed(&"debug_hazard"):
		_debug_toggle_hazard()
	if Input.is_action_just_pressed(&"slow_time"):
		# Bullet-time scales delta, never the 60 Hz tick rate (ADR-9).
		GameLoopManager.time_scale = 0.2 if GameLoopManager.time_scale == 1.0 else 1.0
	if Input.is_action_just_pressed(&"free_camera"):
		_toggle_free_camera(row)
	if Input.is_action_just_pressed(&"debug_spawn_rat"):
		_spawn_at_cursor(row, &"rat")
	if Input.is_action_just_pressed(&"debug_spawn_item"):
		_spawn_at_cursor(row, &"item")


## WASD in the BODY's frame, not the camera's.
##
## `W` is forward along whatever direction the character faces, and `A`/`D` strafe along the
## perpendicular. Camera-relative WASD was effectively world-axis-locked, because this rig never
## rotates — so "forward" meant a fixed compass bearing no matter which way you were pointing.
##
## `raw.x` is positive for `D`; `raw.y` is positive for `S`, because `Input.get_vector` treats
## `move_forward` as the NEGATIVE axis. Hence the subtraction — miss it and `W` walks backwards.
##
## Extracted as a static so the handedness can be asserted without simulating input. Getting the
## cross product backwards swaps `A` and `D`, which is trivially wrong and easy to ship.
static func movement_from(raw: Vector2, facing: Vector3) -> Vector3:
	var forward := Vector3(facing.x, 0.0, facing.z)
	if forward.length() < 0.001:
		return Vector3.ZERO
	forward = forward.normalized()
	# right = forward x UP. With Godot's handedness that is +X for a body facing -Z, matching the
	# convention the camera and the heading nose already use.
	var right: Vector3 = forward.cross(Vector3.UP).normalized()
	return right * raw.x - forward * raw.y


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


## Casts whatever the Grimoire last bound, aimed where the cursor points.
##
## The bound Action_ID lives on `MindComponent.active_spell`, not in this node. That keeps the
## viewer stateless about magic: a cast is "fire what my mind currently holds", so a bind that
## happened this frame is castable the next without the two nodes having to agree about anything.
func _push_cast(row: int, aim: Vector3) -> void:
	var mind: MindComponent = ECSManager.minds.get(row)
	if mind == null or mind.active_spell == &"":
		# Silence is the worst possible feedback. Say what is missing and where to fix it.
		ECSEvents.action_rejected.emit(
			ECSManager.handle_of(row), &"cast", &"no spell bound — press B"
		)
		return
	ECSManager.push_intent(row, ActionIntent.cast(mind.active_spell, aim))
	intents_pushed += 1


func _rig() -> CameraRig:
	return null if _camera == null else _camera.get_parent() as CameraRig


## DEBUG ONLY (`F8`): detach the camera and survey the world. Half of the scope doc's "free
## camera + spawn console" Sprint 1 deliverable, which never shipped — "without a spawn console
## you cannot reproduce a single success state on demand" was the roadmap's own warning.
func _toggle_free_camera(row: int) -> void:
	var rig: CameraRig = _rig()
	if rig == null:
		return
	var flying: bool = rig.toggle_free_flight()
	ECSEvents.action_rejected.emit(
		ECSManager.handle_of(row), &"camera",
		&"free camera ON — WASD flies, F8 returns" if flying else &"camera follows you again"
	)


## DEBUG ONLY (`F9`/`F10`): the spawn console's other half. Spawns a rat or a copper stack at
## the cursor's ground point, so any combat or pickup scenario is reproducible on demand
## without editing a scene.
func _spawn_at_cursor(row: int, kind: StringName) -> void:
	if _camera == null or World.active_chunk == null:
		return
	var mouse: Vector2 = _camera.get_viewport().get_mouse_position()
	var ground: Dictionary = GameLoopManager.picking.cursor_ground(
		_camera.project_ray_origin(mouse),
		_camera.project_ray_normal(mouse),
		World.sampler()
	)
	if not bool(ground.get("hit", false)):
		ECSEvents.action_rejected.emit(
			ECSManager.handle_of(row), &"spawn", &"point at the ground first"
		)
		return
	var at: Vector3 = ground["point"] + Vector3(0.0, 0.5, 0.0)
	if kind == &"rat":
		World.spawn_creature(at, &"SPC_CORPSE_RAT")
	else:
		World.spawn_item(at, MaterialLibrary.MAT_COPPER, 112.0, 5)


## DEBUG ONLY: injure the player, so the death loop can be reached at all.
##
## Sprint 3's headline feature is that death is a loop rather than a screen, and in the generated
## world there was NO WAY TO TRIGGER IT. That world has no pit, no hazard, and nothing hostile —
## so the one thing the sprint was built to demonstrate could not be demonstrated. A play-tester
## should never have to edit code to reach a feature.
func _debug_hurt(row: int) -> void:
	var body: BodyComponent = ECSManager.bodies.get(row)
	if body == null or not body.is_alive():
		return
	var before: float = body.health
	body.health = maxf(0.0, body.health - DEBUG_HURT_AMOUNT)
	ECSEvents.entity_damaged.emit(
		ECSManager.handle_of(row), before - body.health, body.health, &"debug"
	)


## DEBUG ONLY: make the chunk you are standing in a spore field, and back again.
##
## Same reason `K` exists. Mutation is Sprint 4's headline consequence system, and there is no
## naturally-occurring hazard zone anywhere in either scenario — the world generator does not
## place them yet — so without this the entire ecology loop is unreachable from the keyboard and
## can only be seen by reading a test. Exposure accrues at 2.0/s and the threshold is 100, so a
## mutation lands after about fifty seconds of standing in it.
func _debug_toggle_hazard() -> void:
	var chunk: ChunkData = World.active_chunk
	if chunk == null:
		return
	var row: int = EH.index_of(ECSManager.player_handle())
	if chunk.hazard_tags.has(&"Spores"):
		chunk.hazard_tags.erase(&"Spores")
		ECSEvents.action_rejected.emit(
			ECSManager.handle_of(row), &"hazard", &"the air clears"
		)
		return
	chunk.hazard_tags.append(&"Spores")
	ECSEvents.action_rejected.emit(
		ECSManager.handle_of(row), &"hazard", &"the chunk fills with spores"
	)


## DEBUG ONLY: run the Interregnum and bring in the successor.
##
## The year-skip and the successor spawn were implemented and TESTED in Sprint 3, and nothing
## triggered them from the keyboard — so on death the game simply paused forever. The loop only
## reads as a loop if you can complete it.
func _debug_respawn() -> void:
	if ECSManager.is_alive(ECSManager.player_handle()):
		return
	GameLoopManager.death_loop.run_interregnum(World.boot_report, World.grid)
	GameLoopManager.death_loop.spawn_successor(
		World.active_chunk, LineageJournal.load_journal()
	)
	GameLoopManager.paused = false


## Mouse-cursor entity inspection. `DebugOverlay.select_row` existed but NOTHING called it, so
## the inspector — the single highest-value debug surface — was unreachable from the game.
##
## The ray is built from the camera (viewer maths) and then handed to PickSystem, which resolves
## it against the SpatialHash and the tile grid. No Godot raycast is involved.
func _select_under_cursor() -> void:
	if _overlay == null or _camera == null or World.active_chunk == null:
		return
	var mouse: Vector2 = _camera.get_viewport().get_mouse_position()
	var player_row: int = EH.index_of(ECSManager.player_handle())
	# Forgiving selection: nearest entity to the ground point, not an exact ray-AABB thread.
	# A villager is a 0.6 m box seen from 14 m up, and demanding a precise hit made Tab feel
	# broken rather than precise.
	var handle: int = GameLoopManager.picking.cursor_target(
		_camera.project_ray_origin(mouse),
		_camera.project_ray_normal(mouse),
		GameLoopManager.spatial_hash,
		World.sampler(),
		player_row
	)
	var picked: int = EH.index_of(handle) if EH.is_valid(handle) else -1
	_overlay.select_row(next_selection(picked, _overlay.selected_row()))


## What Tab should select next, given what it hit and what is already selected.
##
## THREE BEHAVIOURS, and they have to stay distinguishable (Sprint 4 roadmap Step 5):
##   * a NEW target   -> inspect it, with no clearing press in between;
##   * the SAME target -> clear, restoring the unobstructed LIVE view;
##   * empty ground    -> clear.
##
## That last case REVERSES a Sprint 3 decision. Tab used to fall back to the player row on a miss
## so it "always shows something useful", which was the right fix while the complaint was a hitbox
## that felt broken, and the wrong one once the panel grew big enough to obstruct the view: there
## was then no press anywhere on screen that dismissed it.
##
## Extracted as a static because the behaviour is the whole feature and the rest of
## `_select_under_cursor` is a camera, a viewport and a spatial hash. Testing it through those
## would test the pick path instead — which already has its own tests — and would make the one
## rule that matters here the hardest part to assert.
static func next_selection(picked_row: int, selected_row: int) -> int:
	if picked_row < 0:
		return -1
	return -1 if picked_row == selected_row else picked_row


## `E` takes what is under the cursor, or failing that the nearest thing within arm's reach.
##
## The ray now runs through the MOUSE rather than straight out of the camera's nose, and reach is
## measured from the player. The old version cast from the camera and compared the ray's own
## travel against a 2.5 m reach — the camera sits ~14 m away, so it never once succeeded.
func _push_interact(row: int) -> void:
	if _camera == null or World.active_chunk == null:
		return
	# CONTEXT-SENSITIVE, as the spec calls for: standing on a stairwell, `E` uses the stairs.
	# A separate key would be one more thing to document and one more thing to forget.
	var stairs: int = World.stairs_under(row)
	if stairs != 0:
		World.change_floor(stairs)
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
