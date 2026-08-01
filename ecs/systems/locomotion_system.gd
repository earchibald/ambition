## Turns destinations into velocity, and velocity into arrival (Sprint 3A).
##
## This is what makes the world move. Before it existed, citizens stood exactly where history
## placed them: the ECS knew their needs, their schedules and their jobs, and none of that
## reached their legs.
##
## TWO TIERS, because a village of forty and a world of fifteen factions cannot pay the same
## price per head:
##   * ACTIVE entities steer toward the next waypoint and are moved by CollisionResolveSystem,
##     so they collide with walls and each other exactly like the player does.
##   * SIMULATED entities advance along their route ANALYTICALLY — no collision, no substeps —
##     because the route was already proven walkable when it was planned, and re-proving it
##     every tick for someone nobody is looking at buys nothing.
##
## Path requests are RATE LIMITED per tick. A* is cheap but not free, and forty NPCs all
## re-planning on the same tick is a visible hitch; spreading them costs nobody anything, since
## an NPC that starts walking a tick later is indistinguishable from one that did not.
class_name LocomotionSystem
extends RefCounted

## Paths planned per Simulation tick, across all entities. At 2 Hz this is 24 routes a second,
## which comfortably covers a village re-tasking itself.
const MAX_PATHS_PER_TICK: int = 12

## Ticks an entity waits before asking again after a failed search.
const REPLAN_COOLDOWN_TICKS: int = 10

## How close to the destination counts as arrived, for job completion purposes.
const ARRIVAL_RADIUS_M: float = 0.6

var pathfinder: GridPathfinder = GridPathfinder.new()

var walkers: int = 0
var paths_requested: int = 0
var arrivals: int = 0
var simulated_steps: int = 0


func run(delta: float, sampler: TileSampler) -> void:
	walkers = 0
	paths_requested = 0
	arrivals = 0
	simulated_steps = 0

	var budget: int = MAX_PATHS_PER_TICK
	for row in ECSManager.query(ComponentMask.LOCOMOTION):
		var locomotion: LocomotionComponent = ECSManager.locomotions[row]
		if locomotion.replan_cooldown > 0:
			locomotion.replan_cooldown -= 1
		if not locomotion.has_destination:
			_halt(row)
			continue

		if locomotion.waypoints.is_empty():
			budget = _plan(row, locomotion, sampler, budget)
			if locomotion.waypoints.is_empty():
				continue

		walkers += 1
		if _tier_of(row) == ECSEnums.LoD.ACTIVE:
			_steer_active(row, locomotion)
		else:
			_advance_simulated(row, locomotion, delta)


## Active movers get VELOCITY. They are then integrated and collided by the same system that
## moves the player, so an NPC cannot walk through a wall the player cannot.
func _steer_active(row: int, locomotion: LocomotionComponent) -> void:
	var position: Vector3 = ECSManager.position_of(row)
	var direction: Vector3 = locomotion.steer_from(position)
	if direction == Vector3.ZERO:
		_arrive(row, locomotion)
		return
	var velocity: Vector3 = direction * locomotion.speed_mps
	# Vertical velocity belongs to gravity, not to steering. Overwriting it here would cancel a
	# fall mid-air and leave an NPC hovering over the pit.
	ECSManager.set_velocity(row, Vector3(velocity.x, ECSManager.velocity_of(row).y, velocity.z))


## Simulated movers advance along the route directly. The route was proven walkable when it was
## planned, so re-deriving that every tick for an entity nobody can see is pure cost.
func _advance_simulated(row: int, locomotion: LocomotionComponent, delta: float) -> void:
	simulated_steps += 1
	var position: Vector3 = ECSManager.position_of(row)
	var remaining: float = locomotion.speed_mps * delta
	while remaining > 0.0 and not locomotion.waypoints.is_empty():
		var target: Vector3 = locomotion.waypoints[0]
		var flat := Vector3(target.x, position.y, target.z)
		var distance: float = position.distance_to(flat)
		if distance <= remaining:
			position = flat
			remaining -= distance
			locomotion.waypoints.remove_at(0)
			continue
		position += (flat - position).normalized() * remaining
		remaining = 0.0
	ECSManager.set_position(row, position)
	if locomotion.waypoints.is_empty():
		_arrive(row, locomotion)


func _plan(
	row: int, locomotion: LocomotionComponent, sampler: TileSampler, budget: int
) -> int:
	if budget <= 0 or locomotion.replan_cooldown > 0:
		return budget
	var position: Vector3 = ECSManager.position_of(row)
	if position.distance_to(locomotion.destination) <= ARRIVAL_RADIUS_M:
		_arrive(row, locomotion)
		return budget

	paths_requested += 1
	var route: Array[Vector3] = pathfinder.find_path(position, locomotion.destination, sampler)
	if route.is_empty():
		# Nowhere to go. Back off rather than asking again next tick forever.
		locomotion.replan_cooldown = REPLAN_COOLDOWN_TICKS
		locomotion.has_destination = false
		_halt(row)
		return budget - 1
	locomotion.waypoints = route
	return budget - 1


func _arrive(row: int, locomotion: LocomotionComponent) -> void:
	arrivals += 1
	locomotion.clear()
	_halt(row)
	var job: JobComponent = ECSManager.jobs.get(row)
	if job != null and job.status == ECSEnums.JobStatus.CLAIMED:
		job.status = ECSEnums.JobStatus.IN_PROGRESS


## Stops horizontal motion without touching the vertical component, so halting mid-fall does not
## leave the entity suspended.
func _halt(row: int) -> void:
	if not ECSManager.has_components(row, ComponentMask.POSITION):
		return
	var velocity: Vector3 = ECSManager.velocity_of(row)
	if velocity.x == 0.0 and velocity.z == 0.0:
		return
	ECSManager.set_velocity(row, Vector3(0.0, velocity.y, 0.0))


func _tier_of(row: int) -> ECSEnums.LoD:
	var lod: LoDComponent = ECSManager.lods.get(row)
	return ECSEnums.LoD.SIMULATED if lod == null else lod.current_state


## Points an entity at somewhere to go. The route is planned lazily on the next tick, so a caller
## re-issuing the same destination costs nothing.
static func send_to(row: int, destination: Vector3) -> void:
	var locomotion: LocomotionComponent = ECSManager.locomotions.get(row)
	if locomotion == null:
		locomotion = LocomotionComponent.new()
		ECSManager.locomotions[row] = locomotion
		ECSManager.add_component_bit(row, ComponentMask.LOCOMOTION)
	if locomotion.has_destination and locomotion.destination.distance_to(destination) < 0.5:
		# Already heading there. Re-planning would discard progress and re-pay for A*.
		return
	locomotion.set_route(destination, [] as Array[Vector3])


func counters() -> Dictionary:
	var out: Dictionary = {
		"walkers": walkers,
		"paths_requested": paths_requested,
		"arrivals": arrivals,
		"simulated_steps": simulated_steps,
	}
	out.merge(pathfinder.counters())
	return out
