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
##
## KEYED ON THE REGISTRY'S `Prof_*` VOCABULARY, and it was not: the first version used bare
## `&"Guard"`-style names that matched neither the society doc nor `ProfessionComponent`'s own
## `&"Prof_Idler"` default, so even with professions assigned every lookup would have missed and
## the table would have stayed a constant round-robin wearing a filter. The same defect as the
## invented `CULTURE_FUNGAL` tags, and the invariant test now guards this table the same way.
const PREFERRED_PROFESSION: Dictionary = {
	&"ReassignToGuard": &"Prof_Guard",
	&"PatrolBorders": &"Prof_Guard",
	&"Equip": &"Prof_Guard",
	&"FormSquad": &"Prof_Guard",
	&"Siege": &"Prof_Guard",
	&"Haul": &"Prof_Hauler",
	&"Restock": &"Prof_Hauler",
	&"ClaimResourceZone": &"Prof_Miner",
	&"Barricade": &"Prof_Mason",
}

## What a materialized citizen can be. Weighted toward labour: a village that is mostly guards
## defends granaries nobody filled.
const SPAWN_PROFESSIONS: Array[StringName] = [
	&"Prof_Hauler", &"Prof_Hauler", &"Prof_Miner", &"Prof_Miner",
	&"Prof_Mason", &"Prof_Guard", &"Prof_Guard", &"Prof_Idler",
]

## Never hand a faction more concurrent jobs than it has plausible workers for. An unbounded
## queue is a memory leak that presents as an AI that never finishes anything.
const MAX_JOBS_PER_FACTION: int = 24

## The utility score a planner-issued job claims at. This was 0.0 — the default — which made
## every faction job preemptible by ANY nonzero personal utility, so `MarchToTarget` survived
## for at most one Simulation tick before the worker's own routine (WORK scores 1.0 in work
## hours) evicted it. The LLM decided, the planner assigned, and half a second later everyone
## went back to what they were doing. Set equal to full scheduled work: personal EMERGENCIES
## (starving 2.0, exhausted 1.8 — both above 1.0 x PREEMPT_MARGIN) still interrupt a patrol,
## and mere routine does not. A faction order outranks habit, not survival.
const PLANNER_CLAIM_SCORE: float = 1.0

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
		job.claim(ECSManager.handle_of(row), PLANNER_CLAIM_SCORE)
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
		&"MarchToTarget":
			# MARCHING SOMEWHERE ELSE. `objective_target` was written by the resolver and read by
			# nobody until 2026-08-01, so a faction that decided to raid faction 9 sent its
			# soldiers to wander its own village. The decision was made, recorded, surfaced in
			# the overlay, and had no effect on where anyone walked.
			return _open_tile(_chunk_of_target(core, grid, chunk), rng, 4, 59)
		&"PatrolBorders":
			return _open_tile(chunk, rng, 4, 59)
		&"Barricade", &"ReassignToGuard":
			return _open_tile(chunk, rng, 2, 20)
		&"Restock", &"Haul", &"Equip", &"FormSquad":
			return _open_tile(chunk, rng, 26, 38)
		_:
			return _open_tile(chunk, rng, 8, 55)


## The anchor chunk of whoever this faction decided to act against, or its own if there is no
## target — a raid with no named enemy is a muster, and mustering at home is correct.
func _chunk_of_target(
	core: FactionCoreComponent, grid: WorldGrid, fallback: ChunkData
) -> ChunkData:
	if core.objective_target < 0 or core.objective_target == core.faction_id:
		return fallback
	var target: FactionCoreComponent = DAGInstantiator.faction_core(core.objective_target)
	if target == null or target.anchor_chunk_id == DAGNode.NO_ANCHOR:
		return fallback
	var chunk: ChunkData = grid.chunk_at(target.anchor_chunk_id)
	return fallback if chunk == null else chunk


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
