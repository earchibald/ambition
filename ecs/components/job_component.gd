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


func is_open() -> bool:
	return status == ECSEnums.JobStatus.OPEN


## True while the job holds its claimant, which is what suppresses re-pathing every tick.
func is_latched() -> bool:
	return (
		status == ECSEnums.JobStatus.CLAIMED
		or status == ECSEnums.JobStatus.IN_PROGRESS
	)


func claim(claimant: int, score: float) -> bool:
	if not is_open():
		return false
	claimed_by = claimant
	score_at_claim = score
	status = ECSEnums.JobStatus.CLAIMED
	return true


## Returns the job to the pool rather than leaving it stranded on a dead claimant.
func release() -> void:
	claimed_by = EH.INVALID
	score_at_claim = 0.0
	status = ECSEnums.JobStatus.OPEN
