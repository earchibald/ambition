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


## THE AIM SNAP. Sweeping the cursor past the player made the aim jump to a fixed direction,
## because the old terrain march fell back to a hard-coded +Z whenever it found nothing — which
## is most of the upper half of the screen, where rays reach the horizon or outrun the march.
##
## Swept through a full circle, the aim must rotate CONTINUOUSLY. A snap shows up as one large
## angular step between neighbouring samples.
func test_aim_never_snaps_while_the_cursor_sweeps_around_the_player() -> void:
	var feet := Vector3(20.0, 0.0, 20.0)
	# A fixed camera above and behind, matching CameraRig.FOLLOW_OFFSET.
	var eye: Vector3 = feet + CameraRig.FOLLOW_OFFSET
	var previous: Vector3 = Vector3.ZERO
	var worst_step_deg: float = 0.0

	var samples: int = 720
	for i in samples:
		var angle: float = TAU * float(i) / float(samples)
		# A point on a wide circle around the player, converted into a ray from the camera.
		var aim_at: Vector3 = feet + Vector3(cos(angle), 0.0, sin(angle)) * 12.0
		var aim: Vector3 = PickSystem.aim_direction(feet, eye, (aim_at - eye).normalized())
		assert_gt(aim.length(), 0.9, "the aim is always defined at sample %d" % i)
		if previous != Vector3.ZERO:
			worst_step_deg = maxf(worst_step_deg, rad_to_deg(previous.angle_to(aim)))
		previous = aim
	# 720 samples around a circle is 0.5 degrees each. Anything near 90 or 180 is a snap.
	assert_lt(worst_step_deg, 5.0, "no discontinuity anywhere in the sweep")


## Crossing the player's own X axis is the case that was reported. Sampled either side of it, the
## aim must differ by a hair rather than flipping.
func test_aim_is_continuous_across_the_players_x_axis() -> void:
	var feet := Vector3(20.0, 0.0, 20.0)
	var eye: Vector3 = feet + CameraRig.FOLLOW_OFFSET
	var just_before: Vector3 = PickSystem.aim_direction(
		feet, eye, ((feet + Vector3(12.0, 0.0, 0.05)) - eye).normalized()
	)
	var just_after: Vector3 = PickSystem.aim_direction(
		feet, eye, ((feet + Vector3(12.0, 0.0, -0.05)) - eye).normalized()
	)
	assert_lt(
		rad_to_deg(just_before.angle_to(just_after)),
		2.0,
		"the aim does not snap as the cursor crosses the player's X axis"
	)


## A ray at or above the horizon has NO ground intersection. Rather than snapping to a constant,
## it must keep the direction the cursor implies — which is also the exact limit the intersection
## approaches as the ray flattens, so the two cases meet without a seam.
func test_a_level_ray_keeps_the_direction_the_cursor_implies() -> void:
	var feet := Vector3.ZERO
	var eye := Vector3(0.0, 11.0, 9.0)
	var level: Vector3 = PickSystem.aim_direction(feet, eye, Vector3(-1.0, 0.0, 0.0).normalized())
	assert_almost_eq(level.x, -1.0, 0.001, "a level ray aimed west still aims west")

	# Approach the horizon from below; the answer must converge on the level-ray answer.
	var nearly_level: Vector3 = PickSystem.aim_direction(
		feet, eye, Vector3(-1.0, -0.0005, 0.0).normalized()
	)
	assert_lt(
		rad_to_deg(level.angle_to(nearly_level)),
		1.0,
		"the descending and level cases agree in the limit — no seam at the horizon"
	)


## Straight down onto the actor is the one genuinely undefined case, and it must SAY so rather
## than inventing a direction. The caller holds its previous aim.
func test_a_vertical_ray_reports_that_it_is_undefined() -> void:
	assert_eq(
		PickSystem.aim_direction(Vector3.ZERO, Vector3(0.0, 10.0, 0.0), Vector3.DOWN),
		Vector3.ZERO,
		"a ray straight down has no horizontal answer to give"
	)


## A cube looks identical from all four sides, so rotating one communicates nothing. Heading was
## real and enforced by the melee arc, and shown nowhere on the character — the only way to learn
## which way you faced was to infer it from what you could hit.
func test_the_player_visual_carries_a_heading_marker() -> void:
	var view: ViewManager = ViewManager.new()
	add_child_autofree(view)
	view._on_entity_created(EH.make(0, 1), [&"Player"] as Array[StringName], Vector3.ZERO)
	var body: Node3D = view._visuals[0]
	assert_not_null(
		body.get_node_or_null(ViewManager.NOSE_NAME), "the player body has a visible front"
	)


## Items and creatures must not keep a nose handed down from a pooled player visual.
func test_a_pooled_visual_does_not_inherit_a_heading_marker() -> void:
	var view: ViewManager = ViewManager.new()
	add_child_autofree(view)
	view._on_entity_created(EH.make(0, 1), [&"Player"] as Array[StringName], Vector3.ZERO)
	var body: Node3D = view._visuals[0]
	view._style(body, [&"Item"] as Array[StringName])
	assert_null(
		body.get_node_or_null(ViewManager.NOSE_NAME), "the nose is stripped when reused as an item"
	)


## An entity must not fly in from the world origin on its first frame.
func test_a_new_visual_does_not_interpolate_from_the_origin() -> void:
	var view: ViewManager = ViewManager.new()
	add_child_autofree(view)
	var spawn := Vector3(30.0, 0.9, 30.0)
	view._on_entity_created(EH.make(9, 1), [&"Item"] as Array[StringName], spawn)
	assert_eq(view.visual_position_of(9), spawn, "the first frame draws it where it spawned")


## WASD IS BODY-RELATIVE. `W` walks along whatever direction the character faces; `A`/`D` strafe
## across it. Camera-relative WASD was effectively world-axis-locked, because the rig never
## rotates, so "forward" meant a fixed compass bearing no matter where you pointed.
func test_w_walks_along_the_direction_the_body_faces() -> void:
	# raw.y is NEGATIVE for W, because get_vector treats move_forward as the negative axis.
	var pressing_w := Vector2(0.0, -1.0)
	for facing in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
		var moved: Vector3 = PlayerInputBridge.movement_from(pressing_w, facing)
		assert_almost_eq(
			moved.normalized().dot(facing.normalized()),
			1.0,
			0.001,
			"facing %v, W walks that way" % facing
		)


func test_s_walks_backwards() -> void:
	var moved: Vector3 = PlayerInputBridge.movement_from(Vector2(0.0, 1.0), Vector3.FORWARD)
	assert_almost_eq(
		moved.normalized().dot(Vector3.FORWARD), -1.0, 0.001, "S is the opposite of W"
	)


## Getting the cross product backwards swaps A and D — trivially wrong, and easy to ship.
func test_d_strafes_to_the_bodys_right() -> void:
	# Facing -Z (Godot's forward), the body's right hand points toward +X.
	var moved: Vector3 = PlayerInputBridge.movement_from(Vector2(1.0, 0.0), Vector3.FORWARD)
	assert_almost_eq(moved.x, 1.0, 0.001, "D strafes to +X when facing -Z")
	assert_almost_eq(moved.z, 0.0, 0.001, "and does not drift forwards or back")


func test_a_and_d_are_opposites_at_every_facing() -> void:
	for degrees in [0, 37, 90, 143, 180, 271]:
		var angle: float = deg_to_rad(float(degrees))
		var facing := Vector3(sin(angle), 0.0, -cos(angle))
		var left: Vector3 = PlayerInputBridge.movement_from(Vector2(-1.0, 0.0), facing)
		var right: Vector3 = PlayerInputBridge.movement_from(Vector2(1.0, 0.0), facing)
		assert_almost_eq(
			left.dot(right), -1.0, 0.001, "A and D oppose each other at %d degrees" % degrees
		)


## Strafing must be perpendicular to facing, or A/D creep forwards and the body drifts.
func test_strafing_never_moves_you_forwards() -> void:
	for degrees in [0, 45, 90, 200, 330]:
		var angle: float = deg_to_rad(float(degrees))
		var facing := Vector3(sin(angle), 0.0, -cos(angle))
		var strafe: Vector3 = PlayerInputBridge.movement_from(Vector2(1.0, 0.0), facing)
		assert_almost_eq(
			strafe.dot(facing), 0.0, 0.001, "strafe is perpendicular at %d degrees" % degrees
		)


## Movement stays in the XZ plane. A facing with vertical component must not launch the player.
func test_movement_is_always_flat() -> void:
	var moved: Vector3 = PlayerInputBridge.movement_from(
		Vector2(1.0, -1.0), Vector3(0.3, 0.9, -0.3)
	)
	assert_almost_eq(moved.y, 0.0, 0.001, "WASD never moves you vertically")


## A degenerate facing must produce no movement rather than a NaN direction.
func test_a_degenerate_facing_produces_no_movement() -> void:
	assert_eq(
		PlayerInputBridge.movement_from(Vector2(1.0, -1.0), Vector3.UP),
		Vector3.ZERO,
		"straight up has no horizontal heading, so there is nowhere to walk"
	)
