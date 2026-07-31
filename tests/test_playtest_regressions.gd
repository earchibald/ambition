## Every test here is a defect a human found by playing, that 146 green tests did not.
##
## The common shape: the simulation was correct and the PLAYER'S ROUTE INTO IT was not. Targeting
## measured from the wrong origin, gravity was never applied to creatures, and outcomes were
## computed and then reported nowhere. None of that is visible from inside a unit test that calls
## the system directly with hand-made arguments.
extends GutTest

var _player_row: int


func before_each() -> void:
	# GameLoopManager is an AUTOLOAD, so its `_physics_process` keeps ticking underneath the test
	# and runs its own collision pass between our calls — draining `landings` before we can read
	# them. Any test that drives a system by hand must own the clock.
	GameLoopManager.set_physics_process(false)
	World.boot_scenario(World.SCENARIO_TEST_ARENA, 1)
	_player_row = ECSManager.resolve(ECSManager.player_handle())


func after_all() -> void:
	GameLoopManager.set_physics_process(true)


func _rebuild_hash() -> SpatialHash:
	var hash: SpatialHash = GameLoopManager.spatial_hash
	hash.rebuild(ECSManager.query(ComponentMask.POSITION))
	return hash


## THE `E` BUG. Reach was compared against the RAY'S travel distance, but the ray starts at the
## camera ~14 m away, so the check could never pass and `E` did nothing to anything, ever.
func test_interact_reach_is_measured_from_the_actor_not_the_ray_origin() -> void:
	var player_position: Vector3 = ECSManager.position_of(_player_row)
	var item: int = World.spawn_item(
		player_position + Vector3(1.0, 0.0, 0.0), MaterialLibrary.MAT_COPPER, 112.0, 1
	)
	var hash: SpatialHash = _rebuild_hash()

	# A ray originating far away, exactly as the camera does.
	var far_origin: Vector3 = player_position + Vector3(0.0, 11.0, 9.0)
	var direction: Vector3 = (player_position - far_origin).normalized()
	var target: int = GameLoopManager.picking.interact_target(
		_player_row, far_origin, direction, hash, World.active_chunk
	)
	assert_true(
		EH.is_valid(target),
		"an item 1 m from the player is reachable even though the ray travelled 14 m"
	)
	assert_eq(target, item, "and it is the item, not something else")


## Out of arm's reach must still fail, or the fix has simply removed the rule.
func test_interact_still_refuses_things_that_are_far_away() -> void:
	var player_position: Vector3 = ECSManager.position_of(_player_row)
	World.spawn_item(
		player_position + Vector3(9.0, 0.0, 0.0), MaterialLibrary.MAT_COPPER, 112.0, 1
	)
	var hash: SpatialHash = _rebuild_hash()
	var target: int = GameLoopManager.picking.interact_target(
		_player_row, player_position + Vector3(0.0, 11.0, 9.0), Vector3.DOWN, hash,
		World.active_chunk
	)
	assert_false(EH.is_valid(target), "an item 9 m away is out of reach")


## THE `LMB` BUG. The swing arc is +/-60 degrees around the aim vector, and the aim vector came
## from the movement keys — so a standing player swung along a hard-coded +Z and a rat due EAST
## sat 90 degrees outside the arc. Clicking on it did nothing, with no message saying why.
func test_a_stationary_attacker_can_hit_a_target_it_is_aiming_at() -> void:
	var player_position: Vector3 = ECSManager.position_of(_player_row)
	World.spawn_creature(player_position + Vector3(1.2, 0.0, 0.0), &"SPC_CORPSE_RAT")
	var hash: SpatialHash = _rebuild_hash()

	assert_false(
		EH.is_valid(GameLoopManager.picking.melee_target(_player_row, Vector3.FORWARD, hash)),
		"aiming away from the rat correctly misses — the arc rule still applies"
	)
	assert_true(
		EH.is_valid(GameLoopManager.picking.melee_target(_player_row, Vector3.RIGHT, hash)),
		"aiming AT the rat hits it, with no movement required"
	)


## THE PIT BUG. Only loose items had gravity, so walking off a 2.5 m ledge left the mover at its
## old height and the step/drop rule held it there. A drop was indistinguishable from a step, and
## `resolve_fall` had no caller anywhere in the codebase.
func test_a_creature_over_a_drop_actually_falls() -> void:
	var chunk: ChunkData = World.active_chunk
	# Stand at the pit's lip height, over the pit floor at -2.5 m.
	var over_pit: Vector3 = chunk.tile_to_world(42, 14)
	ECSManager.set_position(_player_row, Vector3(over_pit.x, 0.9, over_pit.z))
	ECSManager.set_velocity(_player_row, Vector3.ZERO)

	GameLoopManager.collision.run(1.0 / 60.0, chunk, _rebuild_hash())

	assert_lt(
		ECSManager.velocity_of(_player_row).y, 0.0, "gravity pulls a creature into the pit"
	)
	assert_gt(GameLoopManager.collision.airborne_movers, 0, "the mover is reported as airborne")


## A creature standing on flat ground must NOT accumulate downward speed. Without zeroing it on
## landing, a stationary player builds up fatal velocity and the next 0.1 m step kills them.
func test_a_grounded_creature_does_not_accumulate_fall_speed() -> void:
	var chunk: ChunkData = World.active_chunk
	for _frame in 30:
		GameLoopManager.collision.run(1.0 / 60.0, chunk, GameLoopManager.spatial_hash)
	assert_almost_eq(
		ECSManager.velocity_of(_player_row).y, 0.0, 0.001, "standing still stays at zero"
	)


## And the landing must be recorded exactly once, not re-detected every frame from a stale column.
func test_a_landing_is_reported_once_not_every_frame() -> void:
	var chunk: ChunkData = World.active_chunk
	var over_pit: Vector3 = chunk.tile_to_world(42, 14)
	ECSManager.set_position(_player_row, Vector3(over_pit.x, 0.9, over_pit.z))
	ECSManager.set_velocity(_player_row, Vector3.ZERO)

	var landings: int = 0
	for _frame in 120:
		GameLoopManager.collision.run(1.0 / 60.0, chunk, GameLoopManager.spatial_hash)
		landings += GameLoopManager.collision.landings.size()
	assert_eq(landings, 1, "one drop produces exactly one landing, not one per frame")


## Falling far enough must cost health, and the overlay must be able to say so.
func test_a_long_fall_deals_damage_and_announces_it() -> void:
	var body: BodyComponent = ECSManager.bodies.get(_player_row)
	var before: float = body.health
	var announced: Array[float] = []
	var probe := func(_e: int, amount: float, _left: float, cause: StringName) -> void:
		if cause == &"fall":
			announced.append(amount)
	ECSEvents.entity_damaged.connect(probe)
	# 9 m/s is comfortably past SAFE_FALL_MPS.
	var dealt: float = GameLoopManager.combat.resolve_fall(_player_row, 9.0)
	ECSEvents.entity_damaged.disconnect(probe)

	assert_gt(dealt, 0.0, "a 9 m/s impact hurts")
	assert_lt(body.health, before, "and health actually drops")
	assert_eq(announced.size(), 1, "the fall is announced exactly once on the event bus")


## A gentle step must remain free, or every staircase becomes a hazard.
func test_a_short_drop_is_free() -> void:
	var body: BodyComponent = ECSManager.bodies.get(_player_row)
	var before: float = body.health
	assert_eq(
		GameLoopManager.combat.resolve_fall(_player_row, WorldConstants.SAFE_FALL_MPS - 0.1),
		0.0,
		"landing under the safe speed costs nothing"
	)
	assert_eq(body.health, before, "and leaves health untouched")


## Outcomes must reach the bus. Sprint 1 resolved melee correctly and reported it nowhere, so a
## hit and a miss looked identical from the player's seat.
func test_melee_damage_is_announced() -> void:
	var player_position: Vector3 = ECSManager.position_of(_player_row)
	var rat: int = World.spawn_creature(player_position + Vector3(1.0, 0.0, 0.0))
	var rat_row: int = ECSManager.resolve(rat)

	var announced: Array[StringName] = []
	var probe := func(_e: int, _amount: float, _left: float, cause: StringName) -> void:
		announced.append(cause)
	ECSEvents.entity_damaged.connect(probe)
	GameLoopManager.combat.resolve_melee(_player_row, rat_row, Vector3.RIGHT, 1.5)
	ECSEvents.entity_damaged.disconnect(probe)

	assert_gt(announced.size(), 0, "a landed hit is announced on the event bus")


## A refused action must say so. Silence is the worst possible feedback, and it is exactly what
## made "I cannot interact with the rat" impossible to diagnose from inside the game.
func test_a_refused_action_is_announced() -> void:
	var rejections: Array[StringName] = []
	var probe := func(_actor: int, action: StringName, _reason: StringName) -> void:
		rejections.append(action)
	ECSEvents.action_rejected.connect(probe)
	ECSEvents.action_rejected.emit(ECSManager.player_handle(), &"attack", &"nothing in reach")
	ECSEvents.action_rejected.disconnect(probe)
	assert_eq(rejections, [&"attack"] as Array[StringName], "the bus carries refusals too")


## The ground march must agree with what TerrainView draws, or the cursor lies about walls.
func test_ground_march_agrees_with_the_drawn_wall_height() -> void:
	assert_eq(
		PickSystem.WALL_TOP_M,
		TerrainView.WALL_HEIGHT_M,
		"the pick march and the drawn wall are the same height"
	)


## Enum readouts must be names. `awareness 0` was read during play-testing as the entity being
## asleep; it is UNAWARE, and Sprint 1 has no sleep state at all.
func test_enums_are_reported_by_name() -> void:
	var overlay: DebugOverlay = DebugOverlay.new()
	add_child_autofree(overlay)
	assert_string_contains(
		overlay._enum_name(ECSEnums.AwarenessState, ECSEnums.AwarenessState.UNAWARE),
		"UNAWARE",
		"awareness reads as a name, not a bare integer"
	)
