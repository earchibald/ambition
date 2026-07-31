## Perception, hearing, and witness events (Sprint 1 gate).
##
## The three tests the spec explicitly demands are all here:
##   * noise behind a wall creates Investigating, not Combat
##   * an unseen crime does not revoke Guest_Status
##   * a sight blocker breaks line of sight
extends GutTest

var chunk: ChunkData
var hash: SpatialHash
var perception: PerceptionSystem
var spawned: PackedInt64Array = PackedInt64Array()


func before_each() -> void:
	chunk = TestArena.build(Vector3i.ZERO)
	hash = SpatialHash.new()
	hash.set_origin(Vector3(-64.0, 0.0, -64.0))
	perception = PerceptionSystem.new()
	spawned = PackedInt64Array()


func after_each() -> void:
	for i in spawned.size():
		ECSManager.destroy_entity(spawned[i])


func _spawn_observer(position: Vector3) -> int:
	var handle: int = ECSManager.allocate_entity()
	var row: int = EH.index_of(handle)
	ECSManager.set_position(row, position)
	ECSManager.add_component_bit(row, ComponentMask.POSITION)
	ECSManager.bounds[row] = BoundsComponent.new()
	ECSManager.add_component_bit(row, ComponentMask.BOUNDS)
	ECSManager.perceptions[row] = PerceptionComponent.new()
	ECSManager.add_component_bit(row, ComponentMask.PERCEPTION)
	ECSManager.memories[row] = MemoryComponent.new()
	ECSManager.add_component_bit(row, ComponentMask.MEMORY)
	var chemistry := ChemistryComponent.new()
	chemistry.add_tag(&"Guest_Status")
	ECSManager.chemistries[row] = chemistry
	ECSManager.add_component_bit(row, ComponentMask.CHEMISTRY)
	spawned.append(handle)
	return handle


func _spawn_noise_maker(position: Vector3, radius: float) -> int:
	var handle: int = ECSManager.allocate_entity()
	var row: int = EH.index_of(handle)
	ECSManager.set_position(row, position)
	ECSManager.add_component_bit(row, ComponentMask.POSITION)
	ECSManager.bounds[row] = BoundsComponent.new()
	ECSManager.add_component_bit(row, ComponentMask.BOUNDS)
	var emitter := SensoryEmitterComponent.new()
	emitter.noise_radius_m = radius
	ECSManager.emitters[row] = emitter
	ECSManager.add_component_bit(row, ComponentMask.SENSORY_EMITTER)
	spawned.append(handle)
	return handle


func _rebuild() -> void:
	ECSManager.flush_structural_changes()
	hash.rebuild(ECSManager.query(ComponentMask.SPATIAL))


# --- The three mandated tests -----------------------------------------------------------------


## A stone wall must make a sword impact inaudible at 15 m.
func test_noise_behind_a_wall_is_not_heard() -> void:
	var emitter := SensoryEmitterComponent.new()
	emitter.noise_radius_m = 18.0
	var listener := PerceptionComponent.new()
	var west: Vector3 = chunk.tile_to_world(16, 10) + Vector3(0.0, 1.0, 0.0)
	var east: Vector3 = chunk.tile_to_world(31, 10) + Vector3(0.0, 1.0, 0.0)
	assert_false(
		PerceptionSystem.can_hear(emitter, listener, west, east, chunk),
		"a stone wall between source and listener blocks the sound"
	)


func test_the_same_noise_is_heard_in_open_air() -> void:
	var emitter := SensoryEmitterComponent.new()
	emitter.noise_radius_m = 18.0
	var listener := PerceptionComponent.new()
	var from: Vector3 = chunk.tile_to_world(5, 10) + Vector3(0.0, 1.0, 0.0)
	var to: Vector3 = chunk.tile_to_world(20, 10) + Vector3(0.0, 1.0, 0.0)
	assert_true(
		PerceptionSystem.can_hear(emitter, listener, from, to, chunk),
		"the same impact IS audible at the same distance with no wall"
	)


## Heard-but-unseen must produce INVESTIGATING, never COMBAT. That distinction is the whole
## point of the acoustic-injection fix.
func test_unseen_noise_produces_investigating_not_combat() -> void:
	var observer: int = _spawn_observer(chunk.tile_to_world(31, 10) + Vector3(0.0, 1.0, 0.0))
	# Loud enough to carry, but on the far side of the interior wall.
	_spawn_noise_maker(chunk.tile_to_world(16, 10) + Vector3(0.0, 1.0, 0.0), 400.0)
	_rebuild()
	perception.run(chunk, hash, 1)
	var component: PerceptionComponent = ECSManager.perceptions[EH.index_of(observer)]
	assert_ne(
		component.awareness_state,
		ECSEnums.AwarenessState.COMBAT,
		"hearing something never jumps straight to combat"
	)
	assert_eq(
		component.awareness_state,
		ECSEnums.AwarenessState.INVESTIGATING,
		"an unseen noise makes the observer investigate"
	)


## An unwitnessed crime must not change social state. There is no global crime flag.
func test_unseen_crime_does_not_revoke_guest_status() -> void:
	var observer: int = _spawn_observer(chunk.tile_to_world(31, 10) + Vector3(0.0, 1.0, 0.0))
	var criminal: int = _spawn_observer(chunk.tile_to_world(10, 10) + Vector3(0.0, 1.0, 0.0))
	_rebuild()
	# The crime happens behind the interior wall, out of sight.
	var witnesses: int = perception.report_crime(
		EH.index_of(criminal), &"THEFT", ECSManager.position_of(EH.index_of(criminal)), chunk, hash
	)
	assert_eq(witnesses, 0, "nobody could see the crime")
	var chemistry: ChemistryComponent = ECSManager.chemistries[EH.index_of(observer)]
	assert_true(
		chemistry.has_tag(&"Guest_Status"), "an unwitnessed crime leaves Guest_Status intact"
	)
	var memory: MemoryComponent = ECSManager.memories[EH.index_of(observer)]
	assert_eq(memory.events.size(), 0, "no memory was written for an unseen crime")


## The same crime IN VIEW must generate a witness event and a memory.
func test_witnessed_crime_creates_a_witness_event_and_memory() -> void:
	var observer: int = _spawn_observer(chunk.tile_to_world(12, 10) + Vector3(0.0, 1.0, 0.0))
	var criminal: int = _spawn_observer(chunk.tile_to_world(10, 10) + Vector3(0.0, 1.0, 0.0))
	_rebuild()
	var witnesses: int = perception.report_crime(
		EH.index_of(criminal), &"MURDER", ECSManager.position_of(EH.index_of(criminal)), chunk, hash
	)
	assert_gt(witnesses, 0, "a visible crime is witnessed")
	var memory: MemoryComponent = ECSManager.memories[EH.index_of(observer)]
	assert_gt(memory.events.size(), 0, "the witness wrote a memory")
	assert_eq(memory.events[0].kind, &"WITNESSED_MURDER", "the memory records what was seen")


# --- Line of sight and cost control -----------------------------------------------------------


func test_line_of_sight_is_symmetric() -> void:
	var a: Vector3 = chunk.tile_to_world(10, 10) + Vector3(0.0, 1.0, 0.0)
	var b: Vector3 = chunk.tile_to_world(40, 10) + Vector3(0.0, 1.0, 0.0)
	assert_eq(
		GridDDA.has_line_of_sight(a, b, chunk),
		GridDDA.has_line_of_sight(b, a, chunk),
		"occlusion is symmetric, which is what makes the LoS cache valid"
	)


func test_observer_sees_a_target_in_the_open() -> void:
	var observer: int = _spawn_observer(chunk.tile_to_world(10, 10) + Vector3(0.0, 1.0, 0.0))
	var row: int = EH.index_of(observer)
	# Facing is derived from velocity; give it a heading so the FOV test can pass.
	ECSManager.set_velocity(row, Vector3(1.0, 0.0, 0.0))
	_spawn_observer(chunk.tile_to_world(14, 10) + Vector3(0.0, 1.0, 0.0))
	_rebuild()
	perception.run(chunk, hash, 1)
	var component: PerceptionComponent = ECSManager.perceptions[row]
	assert_gt(component.last_known_targets.size(), 0, "the observer noticed the target")


func test_awareness_tiering_reduces_evaluation_frequency() -> void:
	var component := PerceptionComponent.new()
	component.awareness_state = ECSEnums.AwarenessState.UNAWARE
	assert_eq(component.eval_interval_ticks(), 20, "unaware observers re-check rarely")
	component.awareness_state = ECSEnums.AwarenessState.COMBAT
	assert_eq(component.eval_interval_ticks(), 1, "observers in combat re-check every tick")


## The march budget is what keeps a 65 ms synchronous burst from happening.
func test_los_march_budget_is_respected() -> void:
	for i in 60:
		var handle: int = _spawn_observer(
			chunk.tile_to_world(6 + i % 12, 6 + i / 12) + Vector3(0.0, 1.0, 0.0)
		)
		ECSManager.set_velocity(EH.index_of(handle), Vector3(1.0, 0.0, 0.0))
	_rebuild()
	perception.run(chunk, hash, 1)
	assert_lte(
		perception.los_marches,
		WorldConstants.PERCEPTION_MARCH_BUDGET,
		"the system never exceeds its per-tick march budget"
	)


func test_candidates_per_observer_are_capped() -> void:
	var observer: int = _spawn_observer(chunk.tile_to_world(10, 30) + Vector3(0.0, 1.0, 0.0))
	ECSManager.set_velocity(EH.index_of(observer), Vector3(1.0, 0.0, 0.0))
	for i in 30:
		_spawn_observer(chunk.tile_to_world(11 + i % 6, 29 + i / 6) + Vector3(0.0, 1.0, 0.0))
	_rebuild()
	perception.run(chunk, hash, 1)
	var component: PerceptionComponent = ECSManager.perceptions[EH.index_of(observer)]
	assert_lte(
		component.last_known_targets.size(),
		WorldConstants.MAX_CANDIDATES_PER_OBSERVER,
		"no observer tracks more than the candidate cap"
	)


func test_attenuation_accumulates_through_material() -> void:
	var open_path: float = PerceptionSystem.attenuation_between(
		chunk.tile_to_world(5, 10) + Vector3(0.0, 1.0, 0.0),
		chunk.tile_to_world(20, 10) + Vector3(0.0, 1.0, 0.0),
		chunk
	)
	var through_wall: float = PerceptionSystem.attenuation_between(
		chunk.tile_to_world(16, 10) + Vector3(0.0, 1.0, 0.0),
		chunk.tile_to_world(31, 10) + Vector3(0.0, 1.0, 0.0),
		chunk
	)
	assert_eq(open_path, 0.0, "open air attenuates nothing")
	assert_gt(through_wall, 20.0, "a stone wall costs at least 20 dB")
