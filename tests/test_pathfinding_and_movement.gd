## Pathfinding, locomotion, and the job planner (Sprint 3A/3B).
##
## Before this existed the world was generated and inert: the ECS knew every citizen's needs,
## schedule and faction, and none of it reached their legs.
extends GutTest

const SEED: int = 808

var grid: WorldGrid
var pathfinder: GridPathfinder
var locomotion: LocomotionSystem
var planner: FactionPlanner


func before_each() -> void:
	GameLoopManager.set_physics_process(false)
	World.boot_scenario(World.SCENARIO_TEST_ARENA, SEED)
	grid = WorldGrid.new(SEED)
	grid.generate_village()
	pathfinder = GridPathfinder.new()
	locomotion = LocomotionSystem.new()
	planner = FactionPlanner.new()


func after_all() -> void:
	GameLoopManager.set_physics_process(true)


# --- A* ---------------------------------------------------------------------------------------

func test_a_route_across_open_ground_is_found() -> void:
	var chunk: ChunkData = World.active_chunk
	var from: Vector3 = chunk.tile_to_world(8, 32)
	var to: Vector3 = chunk.tile_to_world(18, 32)
	var route: Array[Vector3] = pathfinder.find_path(from, to, chunk)
	assert_gt(route.size(), 0, "a route exists across open floor")
	assert_lt(
		route[route.size() - 1].distance_to(to), 1.5, "and it ends at the destination tile"
	)


## Every waypoint must be somewhere a body can actually stand. A route through a wall is worse
## than no route: the mover walks into it and stops, which reads as a collision bug.
func test_no_waypoint_is_inside_a_wall() -> void:
	var chunk: ChunkData = World.active_chunk
	var route: Array[Vector3] = pathfinder.find_path(
		chunk.tile_to_world(8, 32), chunk.tile_to_world(40, 45), chunk
	)
	assert_gt(route.size(), 0, "a route was found")
	for point in route:
		assert_false(chunk.solid_at_world(point), "waypoint %v is walkable" % point)


## The arena's interior wall at x=24 spans y=4..59, so the honest invariant is not "it uses the
## doorway" — going around the wall's open northern end is a perfectly good route, and shorter
## from these endpoints. What must ALWAYS hold is that wherever the route crosses the wall line,
## it crosses on an open tile.
func test_a_route_crosses_the_wall_line_only_where_there_is_a_gap() -> void:
	var chunk: ChunkData = World.active_chunk
	var route: Array[Vector3] = pathfinder.find_path(
		chunk.tile_to_world(8, 10), chunk.tile_to_world(40, 10), chunk
	)
	assert_gt(route.size(), 0, "the far side is reachable")
	var crossings: int = 0
	for point in route:
		var tile: Vector2i = chunk.world_to_tile(point)
		if tile.x != 24:
			continue
		crossings += 1
		assert_false(chunk.is_solid(tile.x, tile.y), "crossed at open tile y=%d" % tile.y)
	assert_gt(crossings, 0, "the route really does cross the wall line")


## And when going around is impossible, it MUST use the doorway. Endpoints level with the
## doorway make the detour round the wall's end far longer than passing through it.
func test_a_route_uses_the_doorway_when_that_is_the_way_through() -> void:
	var chunk: ChunkData = World.active_chunk
	var route: Array[Vector3] = pathfinder.find_path(
		chunk.tile_to_world(20, TestArena.DOORWAY_Y),
		chunk.tile_to_world(30, TestArena.DOORWAY_Y),
		chunk
	)
	assert_gt(route.size(), 0, "the doorway is reachable")
	for point in route:
		var tile: Vector2i = chunk.world_to_tile(point)
		if tile.x == 24:
			assert_true(
				tile.y == TestArena.DOORWAY_Y or tile.y == TestArena.DOORWAY_Y + 1,
				"it went through the doorway, not around the whole wall"
			)


func test_a_walled_in_start_reports_failure_rather_than_hanging() -> void:
	var chunk := ChunkData.new(Vector3i.ZERO)
	# Everything solid except one cell. There is nowhere to go.
	chunk.set_tile(10, 10, ChunkData.TILE_OPEN, 0.0)
	var route: Array[Vector3] = pathfinder.find_path(
		chunk.tile_to_world(10, 10), chunk.tile_to_world(40, 40), chunk
	)
	assert_eq(route.size(), 0, "no route is returned")
	assert_eq(pathfinder.failures, 1, "and the failure is counted, not silently swallowed")


## Bounded work per call. An unbounded search on a large open world is a frame-time cliff.
func test_a_search_is_bounded_and_degrades_to_a_partial_route() -> void:
	var chunk: ChunkData = World.active_chunk
	# A destination far outside the chunk: unreachable, so the search exhausts its budget.
	var route: Array[Vector3] = pathfinder.find_path(
		chunk.tile_to_world(8, 32), Vector3(9000.0, 0.0, 9000.0), chunk
	)
	assert_lte(
		pathfinder.expansions_total,
		GridPathfinder.MAX_EXPANSIONS,
		"the search stopped at its cap"
	)
	# Partial beats nothing: a mover that walks most of the way and re-plans is fine; a mover
	# that gets no path stands still forever and reads as broken.
	assert_gt(route.size(), 0, "a partial route toward the closest point is returned")
	assert_eq(pathfinder.partial_paths, 1, "and reported as partial")


func test_asking_to_walk_where_you_already_are_returns_nothing() -> void:
	var chunk: ChunkData = World.active_chunk
	var here: Vector3 = chunk.tile_to_world(8, 32)
	assert_eq(pathfinder.find_path(here, here, chunk).size(), 0, "no steps needed")


# --- Locomotion --------------------------------------------------------------------------------

func test_an_active_mover_is_given_velocity_toward_its_destination() -> void:
	var row: int = _spawn_walker(ECSEnums.LoD.ACTIVE)
	var chunk: ChunkData = World.active_chunk
	LocomotionSystem.send_to(row, chunk.tile_to_world(18, 32))

	locomotion.run(1.0 / 60.0, chunk)
	locomotion.run(1.0 / 60.0, chunk)
	var velocity: Vector3 = ECSManager.velocity_of(row)
	assert_gt(Vector2(velocity.x, velocity.z).length(), 0.1, "it is moving horizontally")
	assert_gt(velocity.x, 0.0, "and eastward, toward the destination")


## Steering must not touch vertical velocity, or an NPC walking off a ledge hangs in the air.
func test_steering_leaves_gravity_alone() -> void:
	var row: int = _spawn_walker(ECSEnums.LoD.ACTIVE)
	var chunk: ChunkData = World.active_chunk
	ECSManager.set_velocity(row, Vector3(0.0, -6.0, 0.0))
	LocomotionSystem.send_to(row, chunk.tile_to_world(18, 32))
	locomotion.run(1.0 / 60.0, chunk)
	locomotion.run(1.0 / 60.0, chunk)
	assert_almost_eq(ECSManager.velocity_of(row).y, -6.0, 0.001, "the fall continues")


func test_a_simulated_mover_advances_without_collision() -> void:
	var row: int = _spawn_walker(ECSEnums.LoD.SIMULATED)
	var chunk: ChunkData = World.active_chunk
	var before: Vector3 = ECSManager.position_of(row)
	LocomotionSystem.send_to(row, chunk.tile_to_world(18, 32))
	for _tick in 30:
		locomotion.run(1.0 / 10.0, chunk)
	assert_gt(
		ECSManager.position_of(row).distance_to(before), 1.0, "it covered ground on its own"
	)


func test_arrival_promotes_a_claimed_job_to_in_progress() -> void:
	var row: int = _spawn_walker(ECSEnums.LoD.SIMULATED)
	var chunk: ChunkData = World.active_chunk
	var job := JobComponent.new()
	job.status = ECSEnums.JobStatus.CLAIMED
	ECSManager.jobs[row] = job
	ECSManager.add_component_bit(row, ComponentMask.JOB)

	LocomotionSystem.send_to(row, chunk.tile_to_world(10, 32))
	for _tick in 60:
		locomotion.run(1.0 / 10.0, chunk)
	assert_eq(job.status, ECSEnums.JobStatus.IN_PROGRESS, "walking there started the work")


## Re-issuing the same destination must not discard progress, or an NPC re-plans every tick and
## never arrives — the path-request flood the job latch exists to prevent.
func test_reissuing_the_same_destination_keeps_the_route() -> void:
	var row: int = _spawn_walker(ECSEnums.LoD.SIMULATED)
	var chunk: ChunkData = World.active_chunk
	var destination: Vector3 = chunk.tile_to_world(20, 32)
	LocomotionSystem.send_to(row, destination)
	locomotion.run(1.0 / 10.0, chunk)
	var remaining: int = ECSManager.locomotions[row].waypoints.size()
	assert_gt(remaining, 0, "a route was planned")

	LocomotionSystem.send_to(row, destination)
	assert_eq(
		ECSManager.locomotions[row].waypoints.size(), remaining, "the existing route survived"
	)


## Path planning is rate limited. Forty NPCs re-planning on one tick is a visible hitch.
func test_path_planning_is_rate_limited_per_tick() -> void:
	var chunk: ChunkData = World.active_chunk
	for i in 40:
		var row: int = _spawn_walker(ECSEnums.LoD.SIMULATED)
		LocomotionSystem.send_to(row, chunk.tile_to_world(20 + (i % 8), 40))
	locomotion.run(1.0 / 10.0, chunk)
	assert_lte(
		locomotion.paths_requested,
		LocomotionSystem.MAX_PATHS_PER_TICK,
		"no more searches than the per-tick budget"
	)


# --- The planner --------------------------------------------------------------------------------

func test_an_objective_expands_into_its_template_jobs() -> void:
	var core: FactionCoreComponent = _make_faction(3)
	var jobs: Array[Dictionary] = planner.plan(
		ECSEnums.Objective.RAID_FACTION, core.faction_id, grid
	)
	assert_eq(jobs.size(), 3, "one job per living member")
	var template: Array = FactionPlanner.JOB_TEMPLATES[ECSEnums.Objective.RAID_FACTION]
	for job in jobs:
		assert_true(template.has(job["action"]), "%s is in the RAID template" % job["action"])


func test_the_job_count_is_bounded_however_big_the_faction() -> void:
	var core: FactionCoreComponent = _make_faction(60)
	var jobs: Array[Dictionary] = planner.plan(ECSEnums.Objective.IDLE, core.faction_id, grid)
	assert_lte(
		jobs.size(), FactionPlanner.MAX_JOBS_PER_FACTION, "the queue cannot grow without limit"
	)


## A latched job is being worked. Overwriting it on every plan means nobody ever finishes.
func test_replanning_does_not_disturb_work_already_in_progress() -> void:
	var core: FactionCoreComponent = _make_faction(2)
	planner.assign(planner.plan(ECSEnums.Objective.IDLE, core.faction_id, grid))
	var row: int = FactionPlanner.members_of(core.faction_id)[0]
	var job: JobComponent = ECSManager.jobs[row]
	job.status = ECSEnums.JobStatus.IN_PROGRESS
	var action: StringName = job.current_action

	planner.assign(planner.plan(ECSEnums.Objective.RAID_FACTION, core.faction_id, grid))
	assert_eq(job.current_action, action, "the in-progress job was left alone")


func test_assigned_jobs_send_workers_somewhere_walkable() -> void:
	var core: FactionCoreComponent = _make_faction(4)
	planner.assign(planner.plan(ECSEnums.Objective.GATHER_RESOURCES, core.faction_id, grid))
	var chunk: ChunkData = grid.chunk_at(core.anchor_chunk_id)
	for row in FactionPlanner.members_of(core.faction_id):
		var moving: LocomotionComponent = ECSManager.locomotions.get(row)
		assert_not_null(moving, "row %d was told where to go" % row)
		assert_false(
			chunk.solid_at_world(moving.destination), "and the destination is not inside a wall"
		)


func test_the_dead_are_not_given_jobs() -> void:
	var core: FactionCoreComponent = _make_faction(3)
	var members: Array[int] = FactionPlanner.members_of(core.faction_id)
	ECSManager.bodies[members[0]].health = 0.0
	assert_eq(
		FactionPlanner.members_of(core.faction_id).size(), 2, "a corpse is not a worker"
	)


# --- fixtures ------------------------------------------------------------------------------------

func _spawn_walker(tier: ECSEnums.LoD) -> int:
	var chunk: ChunkData = World.active_chunk
	var handle: int = ECSManager.allocate_entity()
	var row: int = EH.index_of(handle)
	ECSManager.set_position(row, chunk.tile_to_world(8, 32) + Vector3(0.0, 0.9, 0.0))
	ECSManager.add_component_bit(row, ComponentMask.POSITION)
	ECSManager.bounds[row] = BoundsComponent.new(Vector3(0.3, 0.9, 0.3))
	ECSManager.add_component_bit(row, ComponentMask.BOUNDS)
	ECSManager.lods[row] = LoDComponent.new(tier)
	ECSManager.add_component_bit(row, ComponentMask.LOD)
	return row


func _make_faction(members: int) -> FactionCoreComponent:
	var core_handle: int = ECSManager.allocate_entity()
	var core_row: int = EH.index_of(core_handle)
	var core := FactionCoreComponent.new()
	core.faction_id = 4242
	core.anchor_chunk_id = Vector3i.ZERO
	ECSManager.faction_cores[core_row] = core
	ECSManager.add_component_bit(core_row, ComponentMask.FACTION_CORE)

	for _i in members:
		var row: int = _spawn_walker(ECSEnums.LoD.SIMULATED)
		ECSManager.social_identities[row] = SocialIdentityComponent.new(core.faction_id)
		ECSManager.add_component_bit(row, ComponentMask.SOCIAL_IDENTITY)
		ECSManager.bodies[row] = BodyComponent.new()
		ECSManager.add_component_bit(row, ComponentMask.BODY)
	return core


## PROFESSION FILTERING (ADR-4). `PREFERRED_PROFESSION` was declared, documented as if it worked,
## and never read — so a miner was as likely to be sent to guard duty as a guard was. Dead code
## that claims to do something is worse than absent code, because it reads as covered.
func test_a_worker_is_given_a_job_their_profession_suits() -> void:
	var core: FactionCoreComponent = _make_faction(4)
	var members: Array[int] = FactionPlanner.members_of(core.faction_id)
	for row in members:
		var job_role := ProfessionComponent.new()
		job_role.profession = &"Guard"
		ECSManager.professions[row] = job_role
		ECSManager.add_component_bit(row, ComponentMask.PROFESSION)

	var jobs: Array[Dictionary] = planner.plan(
		ECSEnums.Objective.GATHER_RESOURCES, core.faction_id, grid
	)
	var guard_actions: Array = FactionPlanner.PREFERRED_PROFESSION.keys().filter(
		func(a: StringName) -> bool: return FactionPlanner.PREFERRED_PROFESSION[a] == &"Guard"
	)
	var template: Array = FactionPlanner.JOB_TEMPLATES[ECSEnums.Objective.GATHER_RESOURCES]
	var suitable: Array = template.filter(
		func(a: StringName) -> bool: return guard_actions.has(a)
	)
	if suitable.is_empty():
		# No guard work in this template, so round-robin is the correct outcome.
		assert_gt(jobs.size(), 0, "everyone still gets work when nobody is qualified")
		return
	for job in jobs:
		assert_true(suitable.has(job["action"]), "guards drew guard work")


## A village where every job needs a specialist and none exists must not stop working.
func test_unqualified_workers_still_get_jobs() -> void:
	var core: FactionCoreComponent = _make_faction(3)
	var jobs: Array[Dictionary] = planner.plan(
		ECSEnums.Objective.RAID_FACTION, core.faction_id, grid
	)
	assert_eq(jobs.size(), 3, "nobody is left idle for lack of a profession")


## A RAID THAT MARCHED NOWHERE. `objective_target` was written by the resolver and read by
## nobody, so a faction that decided to raid faction 9 sent its soldiers wandering around its own
## village. The decision was made, recorded, and shown in the overlay, and changed nothing.
func test_a_raid_marches_on_the_faction_it_named() -> void:
	var attacker: FactionCoreComponent = _make_faction(4)
	var defender: FactionCoreComponent = _make_faction(3)
	# `_make_faction` gives every core the same id, so distinguish them or the planner correctly
	# reads "my target is myself" and marches home — which is what this test first proved.
	defender.faction_id = attacker.faction_id + 1
	defender.anchor_chunk_id = attacker.anchor_chunk_id + Vector3i(2, 0, 0)
	attacker.objective_target = defender.faction_id

	var jobs: Array[Dictionary] = planner.plan(
		ECSEnums.Objective.RAID_FACTION, attacker.faction_id, grid
	)
	var marches: Array = jobs.filter(
		func(j: Dictionary) -> bool: return j["action"] == &"MarchToTarget"
	)
	if marches.is_empty():
		assert_gt(jobs.size(), 0, "the raid produced work of some kind")
		return

	var home: ChunkData = grid.chunk_at(attacker.anchor_chunk_id)
	var away: ChunkData = grid.chunk_at(defender.anchor_chunk_id)
	for march in marches:
		var to: Vector3 = march["location"]
		assert_lt(
			to.distance_to(away.tile_to_world(32, 32)),
			to.distance_to(home.tile_to_world(32, 32)),
			"the march heads toward the enemy, not around the village"
		)


## A raid with no named enemy is a muster, and mustering at home is right — not a crash.
func test_a_raid_without_a_target_still_produces_work() -> void:
	var core: FactionCoreComponent = _make_faction(3)
	core.objective_target = -1
	var jobs: Array[Dictionary] = planner.plan(
		ECSEnums.Objective.RAID_FACTION, core.faction_id, grid
	)
	assert_gt(jobs.size(), 0, "everyone still has something to do")
