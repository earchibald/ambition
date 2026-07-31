## Sight, hearing, and witness generation (ADR-16).
##
## Combat, crime, and reputation are NOT omniscient. This is the shared primitive.
##
## COST IS THE DESIGN CONSTRAINT. A DDA line-of-sight march is ~2.77 us on ADR-10's M1
## reference. Naive all-pairs sight at the 1,500-entity target is 23,436 marches per Simulation
## tick = 65 ms IN ONE FRAME, twice per second (a 4-frame hitch); at the 3,000 hard cap it is
## 260 ms. Four mitigations make it fit, and all four are required:
##   1. Tier by awareness state (UNAWARE re-checks at 0.1 Hz, COMBAT at 2 Hz).
##   2. Cap candidates per observer, nearest-first so real threats win.
##   3. Cache pairwise LoS per sorted row pair — occlusion is symmetric.
##   4. Amortize against a march budget instead of bursting synchronously.
class_name PerceptionSystem
extends RefCounted

const FLOOR_DB: float = 10.0
const MAX_HEARING_RANGE_M: float = 40.0
const MAX_NOISE_EVENTS_PER_TICK: int = 8
const MAX_LISTENERS_PER_EVENT: int = 16

# --- Observability ---
var sight_checks: int = 0
var los_marches: int = 0
var los_cache_hits: int = 0
var los_failures: int = 0
var targets_perceived: int = 0
var witness_events_created: int = 0
var noise_events_consumed: int = 0
var budget_exhausted: bool = false

## Sorted-pair key -> bool, cleared each tick. Halves cost in clustered scenes, which is exactly
## the worst case.
var _los_cache: Dictionary = {}
var _pending_witnesses: Array[WitnessEvent] = []
## Round-robin cursor so tiered observers are visited fairly rather than always the same prefix.
var _cursor: int = 0


func run(chunk: ChunkData, hash: SpatialHash, sim_tick: int) -> void:
	sight_checks = 0
	los_marches = 0
	los_cache_hits = 0
	los_failures = 0
	targets_perceived = 0
	noise_events_consumed = 0
	budget_exhausted = false
	_los_cache.clear()

	var observers: PackedInt32Array = ECSManager.query(ComponentMask.PERCEIVER)
	if observers.is_empty():
		return

	var count: int = observers.size()
	for offset in count:
		if los_marches >= WorldConstants.PERCEPTION_MARCH_BUDGET:
			budget_exhausted = true
			break
		var row: int = observers[(_cursor + offset) % count]
		var perception: PerceptionComponent = ECSManager.perceptions[row]
		# Tiering: an unaware NPC does not need 2 Hz threat detection.
		if sim_tick < perception.next_eval_tick:
			continue
		perception.next_eval_tick = sim_tick + perception.eval_interval_ticks()
		_evaluate_sight(row, perception, chunk, hash)
	_cursor = (_cursor + 1) % maxi(1, count)

	_process_noise(chunk, hash)


func _evaluate_sight(
	row: int, perception: PerceptionComponent, chunk: ChunkData, hash: SpatialHash
) -> void:
	var origin: Vector3 = ECSManager.position_of(row)
	var candidates: PackedInt32Array = hash.query_radius(origin, perception.sight_range_m)
	if candidates.is_empty():
		return

	# Nearest-first, then capped, so the cap never hides the closest threat.
	var ordered: Array = []
	for i in candidates.size():
		var other: int = candidates[i]
		if other == row:
			continue
		ordered.append([origin.distance_squared_to(ECSManager.position_of(other)), other])
	ordered.sort_custom(func(a, b): return a[0] < b[0])

	var facing: Vector3 = _facing_of(row)
	var limit: int = mini(ordered.size(), WorldConstants.MAX_CANDIDATES_PER_OBSERVER)
	for i in limit:
		var other: int = ordered[i][1]
		sight_checks += 1
		var target_pos: Vector3 = ECSManager.position_of(other)

		# Cheap rejects before the expensive march.
		var to_target: Vector3 = target_pos - origin
		var flat: Vector3 = Vector3(to_target.x, 0.0, to_target.z)
		if flat.length() > 0.001 and facing.length() > 0.001:
			var angle: float = rad_to_deg(facing.angle_to(flat.normalized()))
			if angle > perception.fov_degrees * 0.5:
				continue

		if not _line_of_sight(row, other, origin, target_pos, chunk):
			los_failures += 1
			continue
		perception.note_target(ECSManager.handle_of(other), target_pos)
		targets_perceived += 1
		if perception.awareness_state == ECSEnums.AwarenessState.UNAWARE:
			perception.awareness_state = ECSEnums.AwarenessState.SUSPICIOUS


## Symmetric LoS with a per-tick cache. Occlusion is symmetric, so LoS(A,B) == LoS(B,A).
func _line_of_sight(
	row_a: int, row_b: int, from: Vector3, to: Vector3, chunk: ChunkData
) -> bool:
	var low: int = mini(row_a, row_b)
	var high: int = maxi(row_a, row_b)
	var key: int = low * 100000 + high
	if _los_cache.has(key):
		los_cache_hits += 1
		return _los_cache[key]
	los_marches += 1
	var visible: bool = GridDDA.has_line_of_sight(from, to, chunk)
	_los_cache[key] = visible
	return visible


func _facing_of(row: int) -> Vector3:
	var velocity: Vector3 = ECSManager.velocity_of(row)
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() > 0.01:
		return flat.normalized()
	# Standing still: treat as omnidirectional rather than blind.
	return Vector3.ZERO


## Hearing. Sound falls off with distance and is attenuated per tile of intervening material.
## The old spec said only "applies wall/material attenuation" with no formula, no falloff, no
## threshold, and no attenuation field, so its own mandated test could not be written.
func _process_noise(chunk: ChunkData, hash: SpatialHash) -> void:
	var emitter_rows: PackedInt32Array = ECSManager.query(ComponentMask.SENSORY_EMITTER)
	var processed: int = 0
	for i in emitter_rows.size():
		if processed >= MAX_NOISE_EVENTS_PER_TICK:
			break
		var source_row: int = emitter_rows[i]
		var emitter: SensoryEmitterComponent = ECSManager.emitters[source_row]
		if emitter.noise_radius_m <= 0.0:
			continue
		processed += 1
		noise_events_consumed += 1
		var source_pos: Vector3 = ECSManager.position_of(source_row)
		var listeners: PackedInt32Array = hash.query_radius(source_pos, MAX_HEARING_RANGE_M)
		var heard: int = 0
		for j in listeners.size():
			if heard >= MAX_LISTENERS_PER_EVENT:
				break
			var listener_row: int = listeners[j]
			if listener_row == source_row:
				continue
			var perception: PerceptionComponent = ECSManager.perceptions.get(listener_row)
			if perception == null:
				continue
			heard += 1
			var listener_pos: Vector3 = ECSManager.position_of(listener_row)
			if not can_hear(emitter, perception, source_pos, listener_pos, chunk):
				continue
			# Heard but not seen: INVESTIGATE the location, never jump straight to combat on an
			# unseen target.
			if perception.awareness_state == ECSEnums.AwarenessState.UNAWARE:
				perception.awareness_state = ECSEnums.AwarenessState.INVESTIGATING
			perception.note_target(ECSManager.handle_of(source_row), source_pos)


## Decibel model. Verified: a sword impact (noise_radius 18 -> 35.1 dB) is inaudible at 15 m
## through one stone wall (35.1 - 23.5 - 25 = -13.4) but audible in open air (11.6 > 10).
static func can_hear(
	emitter: SensoryEmitterComponent,
	perception: PerceptionComponent,
	source: Vector3,
	listener: Vector3,
	chunk: ChunkData
) -> bool:
	var distance: float = maxf(source.distance_to(listener), 1.0)
	if distance > MAX_HEARING_RANGE_M:
		return false
	var loudness: float = emitter.source_db()
	loudness -= 20.0 * (log(distance) / log(10.0))
	loudness -= attenuation_between(source, listener, chunk)
	var threshold: float = FLOOR_DB - 10.0 * (
		log(maxf(perception.hearing_sensitivity, 0.01)) / log(10.0)
	)
	return loudness > threshold


## Summed per-tile sound loss along the segment.
static func attenuation_between(from: Vector3, to: Vector3, chunk: ChunkData) -> float:
	var total: float = 0.0
	for tile in GridDDA.tiles_along(from, to, chunk):
		if not chunk.in_bounds(tile.x, tile.y):
			continue
		if not chunk.is_solid(tile.x, tile.y):
			continue
		var idx: int = WorldConstants.cell_index(tile.x, tile.y)
		var material: StringName = chunk.material_name(chunk.tile_material[idx])
		total += MaterialLibrary.attenuation_db(material)
	return total


## A crime becomes reputation data ONLY through a witness. There is no global crime flag.
func report_crime(
	subject_row: int, action: StringName, location: Vector3, chunk: ChunkData, hash: SpatialHash
) -> int:
	var witnesses: int = 0
	var observers: PackedInt32Array = hash.query_radius(location, 20.0)
	for i in observers.size():
		var observer_row: int = observers[i]
		if observer_row == subject_row:
			continue
		var perception: PerceptionComponent = ECSManager.perceptions.get(observer_row)
		if perception == null:
			continue
		var observer_pos: Vector3 = ECSManager.position_of(observer_row)
		if not GridDDA.has_line_of_sight(observer_pos, location, chunk):
			continue
		var distance: float = observer_pos.distance_to(location)
		var confidence: float = clampf(
			1.0 - distance / maxf(perception.sight_range_m, 1.0), 0.0, 1.0
		)
		if confidence <= 0.0:
			continue
		var event: WitnessEvent = WitnessEvent.create(
			ECSManager.handle_of(observer_row),
			ECSManager.handle_of(subject_row),
			action,
			location,
			GameClock.total_hours(),
			confidence
		)
		_pending_witnesses.append(event)
		witness_events_created += 1
		witnesses += 1
		_write_memory(observer_row, event)
	return witnesses


func _write_memory(observer_row: int, event: WitnessEvent) -> void:
	var memory: MemoryComponent = ECSManager.memories.get(observer_row)
	if memory == null:
		return
	var kind: StringName = &"WITNESSED_THEFT"
	if event.action == &"MURDER":
		kind = &"WITNESSED_MURDER"
	var record: MemoryEvent = MemoryEvent.create(
		kind, event.action, GameClock.total_hours(), event.is_actionable()
	)
	record.subject = event.subject
	memory.remember(record)


func take_witness_events() -> Array[WitnessEvent]:
	var out: Array[WitnessEvent] = _pending_witnesses.duplicate()
	_pending_witnesses.clear()
	return out


func counters() -> Dictionary:
	return {
		"sight_checks": sight_checks,
		"los_marches": los_marches,
		"los_cache_hits": los_cache_hits,
		"los_failures": los_failures,
		"targets_perceived": targets_perceived,
		"witness_events": witness_events_created,
		"noise_events": noise_events_consumed,
		"perception_budget_exhausted": budget_exhausted,
	}
