## The master clock. Drives every ECS tick class from Godot's fixed physics step, and owns the
## system registry.
##
## MUST `extends Node` to be autoloadable. Loaded LAST so its `_physics_process` runs after the
## state it drives exists.
##
## TICKS ARE COUNTED IN PHYSICS FRAMES, NOT ACCUMULATED FLOATS (ADR-9). `_physics_process` delta
## is exactly 1/60 in Godot, so a frame counter is exact, testable, and cannot drift or
## double-fire. The float-accumulator version in the original scaffolding could do both.
##
## Dropped ticks are DELIBERATE. If the process stalls we do not run catch-up ticks, because a
## catch-up burst is how a hitch becomes a death spiral.
##
## ADR-20 forbids simulation code in `ecs/` from reading wall-clock time, so the soak harness is
## reproducible from RNG seeds alone. The `Time.get_ticks_usec()` calls here are PROFILING ONLY:
## they feed observability counters, never gate a branch that changes the world, and never leave
## this file. Cadence comes from the frame counter, not from elapsed time.
extends Node

## Bullet-time scales the per-tick delta used for integration. It NEVER changes the tick rate,
## which ADR-9 fixes at 60 Hz.
var time_scale: float = 1.0
var paused: bool = false

var micro_frames: int = 0
var sim_ticks: int = 0
var macro_ticks: int = 0
var fluid_ticks: int = 0

# --- Observability: last measured duration per tick class, in milliseconds. ---
var last_micro_ms: float = 0.0
var last_sim_ms: float = 0.0
var last_macro_ms: float = 0.0
var last_fluid_ms: float = 0.0
var last_spatial_ms: float = 0.0

# --- Systems, registered in tick order. ---
var spatial_hash: SpatialHash = SpatialHash.new()
var collision: CollisionResolveSystem = CollisionResolveSystem.new()
var picking: PickSystem = PickSystem.new()
var fluids: FluidDynamicsSystem = FluidDynamicsSystem.new()
var thermodynamics: ThermodynamicsSystem = ThermodynamicsSystem.new()
var ephemerals: EphemeralSystem = EphemeralSystem.new()
var perception: PerceptionSystem = PerceptionSystem.new()
var metabolism: MetabolismSystem = MetabolismSystem.new()
var jobs: JobResolutionSystem = JobResolutionSystem.new()
var combat: ActionResolutionSystem = ActionResolutionSystem.new()
var spoilage: SpoilageSystem = SpoilageSystem.new()
var lod: LoDSystem = LoDSystem.new()
var inventory: InventorySystem = InventorySystem.new()


func _physics_process(delta: float) -> void:
	if paused or not World.booted:
		return
	var scaled_delta: float = delta * time_scale
	var chunk: ChunkData = World.active_chunk
	if chunk == null:
		return

	var micro_start: int = Time.get_ticks_usec()
	_run_micro_tick(scaled_delta, chunk)
	last_micro_ms = float(Time.get_ticks_usec() - micro_start) / 1000.0
	micro_frames += 1

	# Fluids run at 15 Hz, NOT 60 Hz. Measured: 20,000 cell-updates costs ~13 ms on ADR-10's own
	# M1 reference, which is 164% of the entire 8 ms frame budget on its own.
	if micro_frames % WorldConstants.FLUID_TICK_EVERY_N_MICRO == 0:
		var fluid_start: int = Time.get_ticks_usec()
		fluids.run(chunk)
		last_fluid_ms = float(Time.get_ticks_usec() - fluid_start) / 1000.0
		fluid_ticks += 1

	if micro_frames % WorldConstants.SIM_TICK_EVERY_N_MICRO == 0:
		var sim_start: int = Time.get_ticks_usec()
		_run_sim_tick(chunk)
		last_sim_ms = float(Time.get_ticks_usec() - sim_start) / 1000.0
		sim_ticks += 1

	if micro_frames % WorldConstants.MACRO_TICK_EVERY_N_MICRO == 0:
		var macro_start: int = Time.get_ticks_usec()
		_run_macro_tick(chunk)
		last_macro_ms = float(Time.get_ticks_usec() - macro_start) / 1000.0
		macro_ticks += 1

	ECSEvents.tick_completed.emit(&"micro", last_micro_ms, collision.movers_processed)


## Micro order is load-bearing: intents produce velocity, velocity integrates into position and
## resolves against geometry, and only THEN is the spatial hash rebuilt — so every query this
## frame sees post-collision positions.
func _run_micro_tick(scaled_delta: float, chunk: ChunkData) -> void:
	ECSManager.flush_structural_changes()
	_apply_intents(scaled_delta)
	collision.run(scaled_delta, chunk, spatial_hash)

	var spatial_start: int = Time.get_ticks_usec()
	spatial_hash.set_origin(_active_origin(chunk))
	spatial_hash.rebuild(ECSManager.query(ComponentMask.SPATIAL))
	last_spatial_ms = float(Time.get_ticks_usec() - spatial_start) / 1000.0

	ephemerals.run(scaled_delta, spatial_hash)
	thermodynamics.run(scaled_delta, chunk)


func _run_sim_tick(chunk: ChunkData) -> void:
	metabolism.run(chunk)
	jobs.run(sim_ticks)
	perception.run(chunk, spatial_hash, sim_ticks)
	lod.run(World.player_chunk_id)


## Advances the GameClock by one in-game hour (ADR-9).
func _run_macro_tick(chunk: ChunkData) -> void:
	GameClock.advance_hour()
	spoilage.run(chunk)


## Pops each entity's queued intents and turns them into velocity or an action.
func _apply_intents(scaled_delta: float) -> void:
	var rows: PackedInt32Array = ECSManager.query(ComponentMask.POSITION)
	for i in rows.size():
		var row: int = rows[i]
		var queued: Array = ECSManager.take_intents(row)
		for intent in queued:
			_apply_intent(row, intent, scaled_delta)


func _apply_intent(row: int, intent: ActionIntent, _scaled_delta: float) -> void:
	match intent.type:
		ActionIntent.MOVE:
			# Pressing a key does NOT move the player. It sets ECS velocity, and the mass
			# divisor is applied here in the ECS, not in the viewer.
			var speed: float = (
				WorldConstants.BASE_SPEED_MPS * InventorySystem.speed_multiplier(row)
			)
			var direction: Vector3 = intent.vector_data
			if direction.length() > 1.0:
				direction = direction.normalized()
			ECSManager.set_velocity(row, direction * speed)
		ActionIntent.MELEE:
			var target_row: int = ECSManager.resolve(intent.target)
			if target_row >= 0:
				combat.resolve_melee(row, target_row, intent.vector_data, 1.5)
		ActionIntent.TAKE:
			inventory.try_insert(row, intent.target)
		ActionIntent.CONSUME:
			var need: NeedsComponent = ECSManager.needs.get(row)
			if need != null:
				MetabolismSystem.consume_meal(need)
		_:
			pass


## Minimum world corner the spatial grid covers: one chunk out from the player's chunk.
func _active_origin(chunk: ChunkData) -> Vector3:
	return Vector3(
		float(chunk.chunk_id.x - 1) * WorldConstants.CHUNK_SIZE_M,
		0.0,
		float(chunk.chunk_id.y - 1) * WorldConstants.CHUNK_SIZE_M
	)


## Aggregated counters for the debug overlay and the ADR-20 soak harness CSV.
func counters() -> Dictionary:
	var out: Dictionary = {
		"micro_frames": micro_frames,
		"sim_ticks": sim_ticks,
		"macro_ticks": macro_ticks,
		"fluid_ticks": fluid_ticks,
		"last_micro_ms": last_micro_ms,
		"last_sim_ms": last_sim_ms,
		"last_macro_ms": last_macro_ms,
		"last_fluid_ms": last_fluid_ms,
		"last_spatial_ms": last_spatial_ms,
		"micro_budget_ms": WorldConstants.MICRO_BUDGET_MS,
		"over_micro_budget": last_micro_ms > WorldConstants.MICRO_BUDGET_MS,
		"time_scale": time_scale,
		"clock": GameClock.to_display_string(),
	}
	for system in [
		spatial_hash, collision, picking, fluids, thermodynamics, ephemerals, perception,
		metabolism, jobs, combat, spoilage, lod, inventory
	]:
		out.merge(system.counters())
	out.merge(ECSManager.counters())
	return out
