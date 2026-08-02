## The boot sequence (Sprint 2 Step 6). Order is the deliverable.
##
## Every step below depends on the one before it, and the roadmap calls the failure modes
## "Simulation Paradoxes and Physics Explosions" because that is what they look like from the
## outside rather than as an obvious crash:
##
##   1. HISTORY   — the DAG. Nothing else can run first, because world generation places
##                  factions at anchors and there are no factions until history exists.
##   2. GRID      — world generation and anchor assignment. The Interregnum needs zones to
##                  exist before it can age them, so the grid CANNOT come after it.
##   3. POPULATE  — DAG nodes become entities, now that they have somewhere to stand.
##   4. INTERREGNUM (only after a death) — a coarse MONTHLY pass, explicitly NOT twelve hourly
##                  Macro ticks. Running 8,760 hourly ticks to skip a year is the paradox: it
##                  costs a hundred times more and produces a different world than the coarse
##                  pass the death loop is specified against.
##   5. PRE-WARM  — 100 Simulation ticks with gravity suppressed. Crafted items snap to their
##                  display surface; without that they spawn overlapping and the collision
##                  depenetration pass fires them across the room on frame one.
##   6. SPAWN     — Entity 0, last, into a world that is already running.
##
## Phases record their ORDER, not their duration. `ecs/` never reads wall-clock (ADR-20), and
## boot instrumentation is not a good enough reason to carve an exception into a rule whose whole
## value is being absolute — the caller times the call, from outside `ecs/`.
class_name Bootstrapper
extends RefCounted

## Scope doc §7 iteration budgets. Asserted by the boot test rather than aspirational.
const COLD_BOOT_BUDGET_S: float = 30.0

const PRE_WARM_TICKS: int = 100
const INTERREGNUM_MONTHS: int = 12

## What one coarse interregnum month is worth in gray-box production, relative to one hour.
## A month is ~720 hours, but a leaderless year is not a productive one — the world decays and
## regroups rather than compounding at full rate.
const HOURS_PER_INTERREGNUM_MONTH: int = 180

var generator: DAGGenerator = null
var grid: WorldGrid = null
var instantiator: DAGInstantiator = null
var economy: GrayBoxSystem = null

## The phases that actually ran, in the order they ran. This IS the contract: the boot test
## asserts the sequence, because every ordering bug here presents as something else entirely.
var phases_run: Array[StringName] = []
var pre_warm_ticks_run: int = 0
var interregnum_months_run: int = 0

## Notified with each phase name as it COMPLETES. The scope doc requires a per-phase breakdown
## so a 30-second regression is actionable, and ADR-20 forbids this file from reading the clock
## — so the caller (a singleton, outside `ecs/`) owns the stopwatch and this owns the callback.
var on_phase: Callable = Callable()


## Builds a world. `sim_tick` is injected rather than reached for, so the Pre-Warm can be driven
## by a test without standing up the whole game loop.
func execute_boot_sequence(
	master_seed: int, after_death: bool = false, sim_tick: Callable = Callable()
) -> void:
	phases_run.clear()
	pre_warm_ticks_run = 0
	interregnum_months_run = 0

	RNGService.reseed_all(master_seed)

	_phase(&"history", func() -> void:
		generator = DAGGenerator.new()
		generator.run_history_generation()
	)

	_phase(&"grid", func() -> void:
		grid = WorldGrid.new(master_seed)
		grid.generate_village()
		grid.assign_anchors(generator.active_factions())
	)

	_phase(&"populate", func() -> void:
		instantiator = DAGInstantiator.new()
		instantiator.instantiate(generator.get_active_world_state(), grid)
	)

	economy = GrayBoxSystem.new()
	if after_death:
		_phase(&"interregnum", _run_interregnum)

	_phase(&"pre_warm", func() -> void: _run_pre_warm(sim_tick))


## A YEAR of absence, as twelve coarse passes.
##
## NOT twelve hourly Macro ticks, and not 8,760 of them either. The death loop is specified
## against a coarse pass: it is two orders of magnitude cheaper, and running the fine-grained
## tick would additionally let hour-scale behaviour (meals, sleep, job claims) execute thousands
## of times with nobody present to interact with it.
func _run_interregnum() -> void:
	for _month in INTERREGNUM_MONTHS:
		for _hour in HOURS_PER_INTERREGNUM_MONTH:
			economy.run()
		interregnum_months_run += 1
	# THE CALENDAR MOVES TOO. The coarse pass aged the ledgers and left the clock alone, so the
	# successor woke on the same date their predecessor died and every "recently" comparison —
	# memory decay, crisis windows — treated the missing year as never having happened.
	GameClock.advance_interregnum_year()


## 100 Simulation ticks so the village is mid-routine when the player arrives.
##
## GRAVITY IS SUPPRESSED throughout. Items crafted during Pre-Warm are placed onto display
## surfaces; if they were dropped under gravity they would spawn interpenetrating, and the
## depenetration pass would fire the lot across the room on the first real frame. That is the
## roadmap's "Day 0 collision explosion", and it presents as a bug in collision rather than as a
## boot-order problem.
func _run_pre_warm(sim_tick: Callable) -> void:
	for _tick in PRE_WARM_TICKS:
		if sim_tick.is_valid():
			sim_tick.call(true)
		pre_warm_ticks_run += 1
	_snap_loose_items_to_ground()


## Every loose item ends Pre-Warm resting exactly on its tile, at zero velocity.
func _snap_loose_items_to_ground() -> void:
	for row in ECSManager.query(ComponentMask.LOOSE_ITEM):
		var bounds: BoundsComponent = ECSManager.bounds.get(row)
		if bounds == null:
			continue
		var position: Vector3 = ECSManager.position_of(row)
		var ground: float = grid.height_at_world(position)
		ECSManager.set_position(
			row, Vector3(position.x, ground + bounds.half_extents.y, position.z)
		)
		ECSManager.set_velocity(row, Vector3.ZERO)
		var loose: LooseItemComponent = ECSManager.loose_items[row]
		loose.resting = true


func _phase(phase: StringName, work: Callable) -> void:
	work.call()
	phases_run.append(phase)
	if on_phase.is_valid():
		on_phase.call(phase)


func counters() -> Dictionary:
	return {
		"boot_phases": phases_run.size(),
		"boot_pre_warm_ticks": pre_warm_ticks_run,
		"boot_interregnum_months": interregnum_months_run,
	}
