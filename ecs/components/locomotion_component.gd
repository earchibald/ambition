## A route an entity is walking, and where it has got to.
##
## Kept as a component rather than inside the movement system so it survives a LoD demotion:
## review G4 requires that a Simulated mover keep its progress, not restart from its anchor when
## the player looks away and back.
class_name LocomotionComponent
extends RefCounted

## How close, in metres, counts as having reached a waypoint. Smaller than half a tile, or a
## mover overshoots and oscillates around the point it is trying to stand on.
const ARRIVE_RADIUS_M: float = 0.35

## World-space waypoints still to visit. Index 0 is the immediate target.
var waypoints: Array[Vector3] = []
var destination: Vector3 = Vector3.ZERO
var speed_mps: float = 2.2
var has_destination: bool = false

## Ticks to wait before re-planning after a failed path. Without it a boxed-in NPC asks for a
## route every single tick forever, which is the path-request flood the job latch exists to stop.
var replan_cooldown: int = 0


func clear() -> void:
	waypoints.clear()
	has_destination = false
	destination = Vector3.ZERO


func set_route(target: Vector3, route: Array[Vector3]) -> void:
	destination = target
	waypoints = route
	has_destination = true


## Consumes the current waypoint if we are standing on it. Returns the direction to steer, or
## Vector3.ZERO when the route is finished.
func steer_from(position: Vector3) -> Vector3:
	while not waypoints.is_empty():
		var flat_target := Vector3(waypoints[0].x, position.y, waypoints[0].z)
		if position.distance_to(flat_target) <= ARRIVE_RADIUS_M:
			waypoints.remove_at(0)
			continue
		return (flat_target - position).normalized()
	has_destination = false
	return Vector3.ZERO
