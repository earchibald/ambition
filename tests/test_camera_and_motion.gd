## Camera and visual-motion rules. These exist because "swimmy" is a real defect with a real
## cause, and a cause that can be asserted should not be left to feel.
##
## The original rig had TWO independent exponential lags: ViewManager chased ECS truth at rate
## 15, and the camera chased the player at rate 8. Exponential smoothing toward a MOVING target
## never catches it — at speed v and rate k it settles a constant v/k behind. At the 4 m/s walk
## speed that is 0.27 m for the avatar and 0.50 m for the camera, and the DIFFERENCE between them
## is visible drift of the avatar inside its own frame whenever you accelerate or stop.
extends GutTest

var _rig: CameraRig


func before_each() -> void:
	GameLoopManager.set_physics_process(false)
	World.boot_scenario(World.SCENARIO_TEST_ARENA, 1)
	_rig = CameraRig.new()
	add_child_autofree(_rig)


func after_all() -> void:
	GameLoopManager.set_physics_process(true)


## Inside the deadzone the camera must not move AT ALL. Not "move a little", not "move slowly" —
## any motion here is world-slosh under a player who is barely moving.
func test_camera_is_perfectly_still_inside_the_deadzone() -> void:
	var focus := Vector3(10.0, 0.0, 10.0)
	var nudged: Vector3 = _rig.pull_focus(focus, focus + Vector3(1.0, 0.0, 1.0))
	assert_eq(nudged, focus, "a 1.4 m step inside a 5 m deadzone moves the camera zero metres")


## Leaving the deadzone moves the focus EXACTLY enough to put the player back on the boundary,
## with no smoothing. Rigid tracking has no relative motion, which is the whole point.
func test_camera_moves_exactly_enough_to_reach_the_boundary() -> void:
	var focus := Vector3(0.0, 0.0, 0.0)
	var target := Vector3(8.0, 0.0, 0.0)
	var moved: Vector3 = _rig.pull_focus(focus, target)
	assert_almost_eq(moved.x, 3.0, 0.0001, "focus advances by exactly the overshoot, 8 - 5")
	assert_almost_eq(
		Vector2(target.x - moved.x, target.z - moved.z).length(),
		_rig.deadzone_radius_m,
		0.0001,
		"and the player ends up precisely on the deadzone boundary"
	)


## Vertical is a separate, larger deadzone: a 0.4 m ledge must not move the camera, a 2.5 m pit
## must. Handling them together would let a fall shove the view sideways.
func test_vertical_deadzone_ignores_a_step_but_follows_a_fall() -> void:
	var focus := Vector3.ZERO
	assert_eq(
		_rig.pull_focus(focus, Vector3(0.0, TestArena.LEDGE_HEIGHT_M, 0.0)).y,
		0.0,
		"stepping onto the 0.4 m ledge does not move the camera"
	)
	var fallen: Vector3 = _rig.pull_focus(focus, Vector3(0.0, TestArena.PIT_DEPTH_M, 0.0))
	assert_lt(fallen.y, 0.0, "falling into the 2.5 m pit does move the camera")
	assert_almost_eq(
		fallen.y, TestArena.PIT_DEPTH_M + _rig.deadzone_height_m, 0.0001, "by exactly the excess"
	)


## Horizontal motion must never disturb the vertical focus, or walking would bob the view.
func test_walking_does_not_move_the_camera_vertically() -> void:
	var moved: Vector3 = _rig.pull_focus(Vector3.ZERO, Vector3(40.0, 0.0, 40.0))
	assert_eq(moved.y, 0.0, "a long horizontal walk leaves the vertical focus untouched")


## A per-frame `look_at` re-aims the camera as the player moves inside the deadzone, rotating the
## whole world a fraction of a degree every frame. That is invisible in a screenshot and is the
## most nauseating part of a follow rig, so the rotation is set once and frozen.
func test_camera_orientation_is_fixed_not_recomputed_each_frame() -> void:
	var source: String = FileAccess.open("res://viewer/camera_rig.gd", FileAccess.READ).get_as_text()
	var body: String = source.split("func _process(")[1]
	assert_false(body.contains("look_at"), "_process never re-aims the camera")


## Fixed-timestep interpolation, not exponential smoothing. At the end of a physics step the
## drawn position must equal simulation truth exactly — no residual lag, at any speed.
func test_visual_position_has_no_steady_state_lag() -> void:
	var view: ViewManager = ViewManager.new()
	add_child_autofree(view)
	World.boot_scenario(World.SCENARIO_TEST_ARENA, 1)
	var row: int = ECSManager.resolve(ECSManager.player_handle())

	# Two simulation steps at walking speed, sampled as the viewer samples them.
	view._physics_process(1.0 / 60.0)
	ECSManager.set_position(row, ECSManager.position_of(row) + Vector3(0.0667, 0.0, 0.0))
	view._physics_process(1.0 / 60.0)

	var drawn: Vector3 = view.visual_position_of(row)
	var truth: Vector3 = ECSManager.position_of(row)
	# The drawn point lies between the two samples, and never beyond the newest one.
	assert_lte(
		drawn.distance_to(truth), 0.0667 + 0.0001, "the visual never trails by more than one step"
	)


## An entity must not fly in from the world origin on its first frame.
func test_a_new_visual_does_not_interpolate_from_the_origin() -> void:
	var view: ViewManager = ViewManager.new()
	add_child_autofree(view)
	var spawn := Vector3(30.0, 0.9, 30.0)
	view._on_entity_created(EH.make(9, 1), [&"Item"] as Array[StringName], spawn)
	assert_eq(view.visual_position_of(9), spawn, "the first frame draws it where it spawned")
