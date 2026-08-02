## One unit of intended work.
##
## The claim lifecycle prevents orphaned jobs and double-claims within the single-threaded
## tick: claiming sets CLAIMED; if the claimant dies or aborts, the job returns to OPEN.
class_name JobComponent
extends RefCounted

var current_action: StringName = &""
var target_entity: int = EH.INVALID
var target_location: Vector3 = Vector3.ZERO
var claimed_by: int = EH.INVALID
var status: ECSEnums.JobStatus = ECSEnums.JobStatus.OPEN
## Utility score at claim time. The latch compares against this to decide preemption.
var score_at_claim: float = 0.0
## Simulation ticks spent IN_PROGRESS. What makes DONE reachable: until 2026-08-01 a job could
## only ever be OPEN, CLAIMED or IN_PROGRESS — completion and abortion were enum values with no
## producer, so no job in the history of the build had ever finished.
var progress_ticks: int = 0


func is_open() -> bool:
	return status == ECSEnums.JobStatus.OPEN


## True while the job holds its claimant, which is what suppresses re-pathing every tick.
func is_latched() -> bool:
	return (
		status == ECSEnums.JobStatus.CLAIMED
		or status == ECSEnums.JobStatus.IN_PROGRESS
	)


## Refused only while LATCHED. A DONE or ABORTED job is finished business and must be
## re-claimable, or every worker would be permanently retired by their first completed task.
func claim(claimant: int, score: float) -> bool:
	if is_latched():
		return false
	claimed_by = claimant
	score_at_claim = score
	status = ECSEnums.JobStatus.CLAIMED
	progress_ticks = 0
	return true


## Terminal success. Distinct from `release()` so the F1 page and the counters can tell "the
## hauler finished" from "the hauler gave up" — the two look identical from the outside and
## mean opposite things about the simulation.
func complete() -> void:
	status = ECSEnums.JobStatus.DONE
	claimed_by = EH.INVALID
	score_at_claim = 0.0
	progress_ticks = 0


## Terminal failure (unreachable target, failed precondition). The next evaluation may claim
## again; the cooldown in `JobResolutionSystem` is what stops that becoming a livelock.
func abort() -> void:
	status = ECSEnums.JobStatus.ABORTED
	claimed_by = EH.INVALID
	score_at_claim = 0.0
	progress_ticks = 0


## Returns the job to the pool rather than leaving it stranded on a dead claimant.
func release() -> void:
	claimed_by = EH.INVALID
	score_at_claim = 0.0
	status = ECSEnums.JobStatus.OPEN
	progress_ticks = 0
