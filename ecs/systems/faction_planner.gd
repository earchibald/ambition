## Objective -> jobs, via a data-driven template table (ADR-4, Sprint 3 scaffolding §6).
##
## Deliberately NOT a search planner. ADR-4 is explicit: each objective maps to a fixed, ordered
## JobTemplate, and real GOAP can be swapped in later behind this same `plan()` signature. A
## search planner here would be the third unbounded loop in the boot path and would make an
## NPC's behaviour impossible to explain, which the debugging spec requires it to be.
##
## The planner produces INTENDED WORK, not motion. `LocomotionSystem` moves bodies; this decides
## where bodies should be. Keeping those apart is what lets a Simulated faction re-plan without
## anybody walking anywhere.
class_name FactionPlanner
extends RefCounted

## Ordered job types per objective. Data, not code, so content work never edits the planner.
const JOB_TEMPLATES: Dictionary = {
	ECSEnums.Objective.FORTIFY: [&"ReassignToGuard", &"PatrolBorders", &"Barricade"],
	ECSEnums.Objective.RAID_FACTION: [&"Equip", &"FormSquad", &"MarchToTarget", &"Siege"],
	ECSEnums.Objective.GATHER_RESOURCES: [&"ClaimResourceZone", &"Haul", &"Restock"],
	ECSEnums.Objective.MIGRATE: [&"PackUp", &"MarchToTarget"],
	ECSEnums.Objective.IDLE: [&"Wander"],
}

## Which profession prefers which job. A miner sent to guard duty is a planner bug that reads as
## a content bug, so the filter is explicit rather than implied by ordering.
const PREFERRED_PROFESSION: Dictionary = {
	&"ReassignToGuard": &"Guard",
	&"PatrolBorders": &"Guard",
	&"Equip": &"Guard",
	&"FormSquad": &"Guard",
	&"Siege": &"Guard",
	&"Haul": &"Hauler",
	&"Restock": &"Hauler",
	&"ClaimResourceZone": &"Miner",
	&"Barricade": &"Mason",
}

## Never hand a faction more concurrent jobs than it has plausible workers for. An unbounded
## queue is a memory leak that presents as an AI that never finishes anything.
const MAX_JOBS_PER_FACTION: int = 24

var plans_made: int = 0
var jobs_issued: int = 0
var workers_assigned: int = 0


## The swappable interface. A real GOAP planner would implement exactly this and nothing else
## would change.
func plan(objective: ECSEnums.Objective, faction_id: int, grid: WorldGrid) -> Array[Dictionary]:
	plans_made += 1
	var core: FactionCoreComponent = DAGInstantiator.faction_core(faction_id)
	if core == null:
		return [] as Array[Dictionary]

	var template: Array = JOB_TEMPLATES.get(objective, JOB_TEMPLATES[ECSEnums.Objective.IDLE])
	var workers: Array[int] = members_of(faction_id)
	if workers.is_empty():
		return [] as Array[Dictionary]

	# Profession-filtered, as ADR-4 requires. This table was previously declared, documented, and
	# NEVER READ — a miner was as likely to be sent to guard duty as a guard was. Dead code that
	# claims to do something is worse than absent code, because it reads as covered.
	var out: Array[Dictionary] = []
	var index: int = 0
	for worker in workers:
		if out.size() >= MAX_JOBS_PER_FACTION:
			break
		var action: StringName = _best_action_for(worker, template, index)
		index += 1
		out.append({
			"row": worker,
			"action": action,
			"location": _target_for(action, core, worker, grid),
		})
	jobs_issued += out.size()
	return out


## Picks this worker's job from the template, preferring one their profession suits.
##
## Falls back to round-robin so the whole template is still covered when nobody is qualified —
## a village where every job needs a specialist and none exists would simply stop working.
func _best_action_for(worker: int, template: Array, index: int) -> StringName:
	var profession: ProfessionComponent = ECSManager.professions.get(worker)
	if profession != null and profession.profession != &"":
		for candidate in template:
			if PREFERRED_PROFESSION.get(candidate, &"") == profession.profession:
				return candidate
	return template[index % template.size()]


## Applies a plan: writes each worker's job and points it somewhere to walk.
func assign(jobs: Array[Dictionary]) -> void:
	for entry in jobs:
		var row: int = int(entry["row"])
		var job: JobComponent = ECSManager.jobs.get(row)
		if job == null:
			job = JobComponent.new()
			ECSManager.jobs[row] = job
			ECSManager.add_component_bit(row, ComponentMask.JOB)
		# A latched job is being worked. Overwriting it every plan is the re-path flood the job
		# latch exists to prevent, and it means nobody ever finishes anything.
		if job.is_latched():
			continue
		job.current_action = entry["action"]
		job.target_location = entry["location"]
		job.status = ECSEnums.JobStatus.CLAIMED
		job.claimed_by = ECSManager.handle_of(row)
		LocomotionSystem.send_to(row, entry["location"])
		workers_assigned += 1


## Every living Tier 2 member of a faction. Linear over social identities, which is bounded by
## the entity cap and by ADR-12's faction cap.
static func members_of(faction_id: int) -> Array[int]:
	var out: Array[int] = []
	for row in ECSManager.query(ComponentMask.SOCIAL_IDENTITY):
		if row == 0:
			continue
		var identity: SocialIdentityComponent = ECSManager.social_identities[row]
		if identity.faction_id != faction_id:
			continue
		var body: BodyComponent = ECSManager.bodies.get(row)
		if body != null and body.is_alive():
			out.append(row)
	return out


## Where a given job type happens. Derived from the faction's anchor chunk, so a plan is always
## somewhere the faction actually is rather than at the world origin.
func _target_for(
	action: StringName, core: FactionCoreComponent, worker: int, grid: WorldGrid
) -> Vector3:
	var chunk: ChunkData = grid.chunk_at(core.anchor_chunk_id)
	var rng: RandomNumberGenerator = FloorGenerator.chunk_rng(
		Vector3i(worker, core.faction_id, int(action.hash() % 1000)), grid.master_seed
	)
	match action:
		&"PatrolBorders", &"MarchToTarget":
			return _open_tile(chunk, rng, 4, 59)
		&"Barricade", &"ReassignToGuard":
			return _open_tile(chunk, rng, 2, 20)
		&"Restock", &"Haul", &"Equip", &"FormSquad":
			return _open_tile(chunk, rng, 26, 38)
		_:
			return _open_tile(chunk, rng, 8, 55)


## A walkable tile in a band of the chunk. Bounded search, then the chunk centre: an unbounded
## "roll until open" loop hangs the Simulation tick on a densely built chunk.
func _open_tile(
	chunk: ChunkData, rng: RandomNumberGenerator, low: int, high: int
) -> Vector3:
	for _attempt in 24:
		var tile := Vector2i(rng.randi_range(low, high), rng.randi_range(low, high))
		if not chunk.is_solid(tile.x, tile.y):
			var ground: Vector3 = chunk.tile_to_world(tile.x, tile.y)
			return Vector3(ground.x, ground.y + 0.9, ground.z)
	return World.spawn_position_in(chunk)


func counters() -> Dictionary:
	return {
		"plans_made": plans_made,
		"jobs_issued": jobs_issued,
		"workers_assigned": workers_assigned,
	}
