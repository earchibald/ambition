## The master clock. Drives every ECS tick class from Godot's fixed physics step.
##
## MUST `extends Node` to be autoloadable. Loaded LAST, so its `_physics_process` runs after
## ECSEvents and ECSManager exist.
##
## TICKS ARE COUNTED IN PHYSICS FRAMES, NOT ACCUMULATED FLOATS (ADR-9).
## `_physics_process` delta is exactly 1/60 in Godot, so a frame counter is exact, testable,
## and cannot drift or double-fire. The float-accumulator version in the original scaffolding
## could do both.
##
## Dropped ticks are DELIBERATE. If the process is stalled we do not run catch-up ticks,
## because a catch-up burst is how a hitch becomes a death spiral.
##
## ADR-20 forbids simulation code in `ecs/` from reading wall-clock time, so that the soak
## harness is reproducible from RNG seeds alone. The `Time.get_ticks_usec()` calls below are
## PROFILING ONLY: they are written to observability counters and never feed simulation state,
## never gate a branch that changes the world, and never leave this file. Simulation cadence
## comes from the physics-frame counter, not from elapsed time.
extends Node

## Bullet-time scales the per-tick delta used for integration. It NEVER changes the tick
## rate, which ADR-9 fixes at 60 Hz.
var time_scale: float = 1.0

var micro_frames: int = 0
var sim_ticks: int = 0
var macro_ticks: int = 0
var fluid_ticks: int = 0

var paused: bool = false

# --- Observability: last measured duration per tick class, in milliseconds. ---
var last_micro_ms: float = 0.0
var last_sim_ms: float = 0.0
var last_macro_ms: float = 0.0


func _physics_process(delta: float) -> void:
	if paused:
		return
	var scaled_delta := delta * time_scale

	var micro_start := Time.get_ticks_usec()
	_run_micro_tick(scaled_delta)
	last_micro_ms = (Time.get_ticks_usec() - micro_start) / 1000.0

	micro_frames += 1

	# Fluids run at 15 Hz, not 60 Hz. ADR-10's 20,000-cell Micro-tick budget was measured at
	# ~13 ms on the M1 reference — 164% of the entire 8 ms frame budget on its own.
	if micro_frames % WorldConstants.FLUID_TICK_EVERY_N_MICRO == 0:
		_run_fluid_tick(scaled_delta)
		fluid_ticks += 1

	if micro_frames % WorldConstants.SIM_TICK_EVERY_N_MICRO == 0:
		var sim_start := Time.get_ticks_usec()
		_run_sim_tick()
		last_sim_ms = (Time.get_ticks_usec() - sim_start) / 1000.0
		sim_ticks += 1

	if micro_frames % WorldConstants.MACRO_TICK_EVERY_N_MICRO == 0:
		var macro_start := Time.get_ticks_usec()
		_run_macro_tick()
		last_macro_ms = (Time.get_ticks_usec() - macro_start) / 1000.0
		macro_ticks += 1


## Sprint 1 registers the Micro systems here in order:
## integrate velocity -> resolve collision -> rebuild spatial hash -> resolve actions.
func _run_micro_tick(_scaled_delta: float) -> void:
	pass


func _run_fluid_tick(_scaled_delta: float) -> void:
	pass


## Sprint 1: metabolism, schedules, utility AI, LoD state, perception scheduling.
func _run_sim_tick() -> void:
	pass


## Advances the GameClock by one in-game hour (ADR-9).
func _run_macro_tick() -> void:
	pass


## Counters for the debug overlay and the ADR-20 soak harness. Read-only.
func counters() -> Dictionary:
	return {
		"micro_frames": micro_frames,
		"sim_ticks": sim_ticks,
		"macro_ticks": macro_ticks,
		"fluid_ticks": fluid_ticks,
		"last_micro_ms": last_micro_ms,
		"last_sim_ms": last_sim_ms,
		"last_macro_ms": last_macro_ms,
		"time_scale": time_scale,
	}
