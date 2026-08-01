## A* over the tile grid (ADR-2's grid-A* tier).
##
## Pure maths against the TileSampler. No NavigationServer3D, no navigation mesh, no scene nodes.
## ADR-2 sanctions NavigationServer3D as a local-steering accelerator inside Active chunks, but
## it is deliberately not used here: it needs a baked region, a bake is asynchronous, and a
## Simulated NPC that cannot path until a bake completes simply stands still. Grid A* answers
## immediately from data that already exists.
##
## EVERY SEARCH IS BOUNDED. `MAX_EXPANSIONS` caps the work a single call can do, and a path
## request that hits the cap returns a partial route toward the closest node reached rather than
## nothing. An NPC that walks most of the way and re-plans is indistinguishable from one that
## planned perfectly; an NPC that gets no path stands still forever and reads as broken.
class_name GridPathfinder
extends RefCounted

## Roughly the area of two chunks. Enough to cross a village, cheap enough to run several per
## Simulation tick without noticing.
const MAX_EXPANSIONS: int = 4000

## Four-way only. Diagonals would need the same vertex-squeeze exclusion the collision resolve
## implements, and a diagonal step whose shared corner is solid is exactly the move an AABB
## cannot physically make — so the path would be one the body cannot walk.
const STEPS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]

var searches: int = 0
var expansions_total: int = 0
var partial_paths: int = 0
var failures: int = 0


## World-space waypoints from `from` to `to`, or an empty array if there is no route at all.
## The first element is the next step, NOT the current position.
func find_path(from: Vector3, to: Vector3, sampler: TileSampler) -> Array[Vector3]:
	searches += 1
	var start: Vector2i = _tile_of(from)
	var goal: Vector2i = _tile_of(to)
	if start == goal:
		return [] as Array[Vector3]

	# g-score and parent, keyed by tile. Dictionaries rather than a flat array because the search
	# is unbounded in world space: tiles are global, not chunk-local.
	var came_from: Dictionary = {}
	var cost: Dictionary = {start: 0}
	var frontier: Array[Vector2i] = [start]
	var priority: Dictionary = {start: _heuristic(start, goal)}
	var expansions: int = 0
	var closest: Vector2i = start
	var closest_distance: int = _heuristic(start, goal)

	while not frontier.is_empty() and expansions < MAX_EXPANSIONS:
		var current: Vector2i = _pop_cheapest(frontier, priority)
		expansions += 1
		if current == goal:
			expansions_total += expansions
			return _reconstruct(came_from, current)

		var remaining: int = _heuristic(current, goal)
		if remaining < closest_distance:
			closest_distance = remaining
			closest = current

		for step in STEPS:
			var next: Vector2i = current + step
			if sampler.solid_at_world(_world_of(next)):
				continue
			var next_cost: int = int(cost[current]) + 1
			if cost.has(next) and next_cost >= int(cost[next]):
				continue
			cost[next] = next_cost
			came_from[next] = current
			priority[next] = next_cost + _heuristic(next, goal)
			frontier.append(next)

	expansions_total += expansions
	if closest == start:
		# Genuinely walled in. Distinct from "ran out of budget", and worth its own counter:
		# one means the world is wrong, the other means the cap is too low.
		failures += 1
		return [] as Array[Vector3]
	partial_paths += 1
	return _reconstruct(came_from, closest)


## Manhattan, which is admissible for four-way movement on a uniform grid and therefore keeps A*
## optimal. Euclidean would also be admissible but never tighter here, so it only costs a sqrt.
func _heuristic(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## Linear scan for the lowest f-score. A binary heap is the textbook answer and is deliberately
## not used yet: at these frontier sizes the scan measures faster than the heap's bookkeeping,
## and ADR-10's budget is a measurement, not a preference. Revisit if the frontier grows.
func _pop_cheapest(frontier: Array[Vector2i], priority: Dictionary) -> Vector2i:
	var best: int = 0
	var best_score: int = int(priority[frontier[0]])
	for i in range(1, frontier.size()):
		var score: int = int(priority[frontier[i]])
		if score < best_score:
			best_score = score
			best = i
	var chosen: Vector2i = frontier[best]
	frontier.remove_at(best)
	return chosen


func _reconstruct(came_from: Dictionary, goal: Vector2i) -> Array[Vector3]:
	var reversed_tiles: Array[Vector2i] = [goal]
	var cursor: Vector2i = goal
	while came_from.has(cursor):
		cursor = came_from[cursor]
		reversed_tiles.append(cursor)
	var out: Array[Vector3] = []
	# Drop the start tile: the mover is already standing on it, and steering toward your own
	# feet produces a jitter that looks exactly like a stuck pathfinder.
	for i in range(reversed_tiles.size() - 2, -1, -1):
		out.append(_world_of(reversed_tiles[i]))
	return out


## GLOBAL tile coordinates, not chunk-local. Chunk-local indices cannot express a route that
## crosses a seam, which is most routes in a streamed world.
static func _tile_of(world: Vector3) -> Vector2i:
	return Vector2i(
		int(floor(world.x / WorldConstants.TILE_SIZE_M)),
		int(floor(world.z / WorldConstants.TILE_SIZE_M))
	)


static func _world_of(tile: Vector2i) -> Vector3:
	return Vector3(
		(float(tile.x) + 0.5) * WorldConstants.TILE_SIZE_M,
		0.0,
		(float(tile.y) + 0.5) * WorldConstants.TILE_SIZE_M
	)


func counters() -> Dictionary:
	return {
		"path_searches": searches,
		"path_expansions": expansions_total,
		"path_partial": partial_paths,
		"path_failures": failures,
	}
