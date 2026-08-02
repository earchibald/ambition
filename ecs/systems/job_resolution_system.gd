## Utility evaluation and job claiming on the Simulation tick.
##
## THIS IS AN ARGMAX OVER COMPARABLE SCORES, NOT A PRIORITY LADDER. The old evaluator multiplied
## a need by a constant and compared to a constant, which is algebraically identical to a bare
## threshold, and never compared the two urgencies to each other. Consequence: an NPC at
## hunger 76 / energy 0 returned Consume forever and could never sleep, and with an empty
## stockpile it returned the same unsatisfiable intent every tick, permanently.
##
## THE JOB LATCH IS LOAD-BEARING. Without it the evaluator re-issues an intent — and a path
## request — every Simulation tick for the whole duration of a walk. At 1,500 NPCs x 2 Hz that
## is 3,000 path requests/second against NavBridge's bounded 300/second: the queue grows without
## limit and every entity sits waiting for a path forever.
class_name JobResolutionSystem
extends RefCounted

const HUNGER_ENTER: float = 80.0
const HUNGER_EXIT: float = 30.0
const ENERGY_ENTER: float = 20.0
const ENERGY_EXIT: float = 80.0

## Urgency an active need starts at, as a fraction of its weight, the moment it crosses its
## enter threshold. Without this a just-triggered need scores 0.0 and never interrupts work.
const INTERRUPT_BASE: float = 0.6

const W_EAT: float = 2.0
const W_SLEEP: float = 1.8
const W_WORK: float = 1.0

## A new option must beat the latched one by this margin to preempt it.
const PREEMPT_MARGIN: float = 1.35
## After a precondition failure, the action is unavailable for this many ticks so the entity
## cannot livelock on something it can never satisfy.
const FAIL_COOLDOWN_TICKS: int = 20

## IN_PROGRESS ticks before a planner job counts as finished. 40 Simulation ticks is 20 s of
## standing at the work site — long enough to read as working, short enough that a village
## visibly cycles through tasks within a play session.
const WORK_DURATION_TICKS: int = 40

var evaluations: int = 0
var preemptions: int = 0
var latched_retained: int = 0
var jobs_completed: int = 0
var jobs_aborted: int = 0

## row -> { action: StringName -> tick_when_available }
var _cooldowns: Dictionary = {}


func run(sim_tick: int) -> void:
	evaluations = 0
	preemptions = 0
	latched_retained = 0
	var rows: PackedInt32Array = ECSManager.query(ComponentMask.NEEDS)
	for i in rows.size():
		var row: int = rows[i]
		evaluations += 1
		_evaluate(row, sim_tick)


func _evaluate(row: int, sim_tick: int) -> void:
	var need: NeedsComponent = ECSManager.needs[row]
	var job: JobComponent = ECSManager.jobs.get(row)
	if job == null:
		job = JobComponent.new()
		ECSManager.jobs[row] = job
		ECSManager.add_component_bit(row, ComponentMask.JOB)

	# THE LIFECYCLE, before the argmax. Until 2026-08-01 DONE and ABORTED were enum values with
	# no producer: a job could start and could be evicted, and could never finish or fail.
	if job.status == ECSEnums.JobStatus.IN_PROGRESS:
		job.progress_ticks += 1
		if job.progress_ticks >= WORK_DURATION_TICKS:
			jobs_completed += 1
			job.complete()
	elif job.status == ECSEnums.JobStatus.CLAIMED and _walk_failed(row):
		# The path search gave up (bounded A*, unreachable target). Without this the job sat
		# CLAIMED forever on a worker who was never going to arrive — the stranded-job state the
		# claim lifecycle exists to prevent, reached through the front door.
		jobs_aborted += 1
		mark_precondition_failed(row, job.current_action, sim_tick)
		job.abort()

	var scores: Dictionary = score_actions(row, need)
	var best_action: StringName = &""
	var best_score: float = -1.0
	for action in scores:
		if _on_cooldown(row, action, sim_tick):
			continue
		var value: float = scores[action]
		if value > best_score:
			best_score = value
			best_action = action

	# The latch: keep an in-progress job unless the alternative is decisively better.
	if job.is_latched():
		if best_score <= job.score_at_claim * PREEMPT_MARGIN:
			latched_retained += 1
			return
		preemptions += 1
		job.release()

	if best_action == &"":
		return
	job.current_action = best_action
	job.claim(ECSManager.handle_of(row), best_score)


## Comparable 0..1 urgencies scaled by weight, so hunger and exhaustion actually compete.
## Dual thresholds give hysteresis: without it an entity sitting on a threshold flips action
## every single tick.
func score_actions(row: int, need: NeedsComponent) -> Dictionary:
	var job: JobComponent = ECSManager.jobs.get(row)
	var current: StringName = &"" if job == null else job.current_action

	var eat_enter: float = HUNGER_EXIT if current == ActionIntent.CONSUME else HUNGER_ENTER
	var sleep_enter: float = ENERGY_EXIT if current == ActionIntent.SLEEP else ENERGY_ENTER

	# CROSSING A THRESHOLD MUST ACTUALLY INTERRUPT. A purely normalized ramp starts at 0.0 right
	# at the threshold, so a need that has just become urgent would still lose to routine work
	# and "hunger > 80 interrupts the routine" would be false until ~90. So an active need starts
	# at INTERRUPT_BASE of its weight and ramps to full.
	var eat: float = 0.0
	if need.hunger > eat_enter:
		var eat_ramp: float = clampf(
			(need.hunger - eat_enter) / maxf(100.0 - eat_enter, 0.001), 0.0, 1.0
		)
		eat = INTERRUPT_BASE + (1.0 - INTERRUPT_BASE) * eat_ramp
	var sleep: float = 0.0
	if need.energy < sleep_enter:
		var sleep_ramp: float = clampf(
			(sleep_enter - need.energy) / maxf(sleep_enter, 0.001), 0.0, 1.0
		)
		sleep = INTERRUPT_BASE + (1.0 - INTERRUPT_BASE) * sleep_ramp

	var schedule: ScheduleComponent = ECSManager.schedules.get(row)
	var work: float = 0.5
	if schedule != null:
		match schedule.block_for_hour(GameClock.hour):
			ScheduleComponent.Block.WORK:
				work = 1.0
			ScheduleComponent.Block.SLEEP:
				work = 0.0
			_:
				work = 0.3

	return {
		ActionIntent.CONSUME: eat * W_EAT,
		ActionIntent.SLEEP: sleep * W_SLEEP,
		ActionIntent.WORK: work * W_WORK,
	}


## True when a walking job's route was refused. Only planner jobs walk — the three personal
## actions (CONSUME/SLEEP/WORK) never set a locomotion destination, so testing them here would
## abort every meal. The signature of failure is `_plan` clearing `has_destination` after a
## refused search, with no waypoints left to follow.
func _walk_failed(row: int) -> bool:
	var job: JobComponent = ECSManager.jobs.get(row)
	if job == null or _is_personal(job.current_action):
		return false
	var locomotion: LocomotionComponent = ECSManager.locomotions.get(row)
	if locomotion == null:
		return false
	return not locomotion.has_destination and locomotion.waypoints.is_empty()


static func _is_personal(action: StringName) -> bool:
	return (
		action == ActionIntent.CONSUME
		or action == ActionIntent.SLEEP
		or action == ActionIntent.WORK
	)


## Called when an action cannot be satisfied (e.g. no food in the stockpile).
func mark_precondition_failed(row: int, action: StringName, sim_tick: int) -> void:
	if not _cooldowns.has(row):
		_cooldowns[row] = {}
	_cooldowns[row][action] = sim_tick + FAIL_COOLDOWN_TICKS
	var job: JobComponent = ECSManager.jobs.get(row)
	if job != null and job.current_action == action:
		job.release()


func _on_cooldown(row: int, action: StringName, sim_tick: int) -> bool:
	if not _cooldowns.has(row):
		return false
	return sim_tick < int(_cooldowns[row].get(action, 0))


## A dead or destroyed claimant must not strand its job. Static, because the caller that
## matters is the corpse-conversion path in `ActionResolutionSystem`, which holds no reference
## to this system — and this function had NO production caller at all until 2026-08-01, so a
## dead hauler's job stayed CLAIMED by a corpse forever.
static func release_jobs_of(row: int) -> void:
	var job: JobComponent = ECSManager.jobs.get(row)
	if job != null:
		job.release()


func counters() -> Dictionary:
	return {
		"utility_evaluations": evaluations,
		"job_preemptions": preemptions,
		"jobs_latched": latched_retained,
		"jobs_completed": jobs_completed,
		"jobs_aborted": jobs_aborted,
	}
