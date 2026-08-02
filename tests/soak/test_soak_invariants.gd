## Long-horizon soak testing (ADR-20).
##
## This project's real failure modes are long-horizon and INVISIBLE to unit, property,
## integration, and smoke tests, all of which are short-horizon:
##   * a faction ledger reaching 10^7 by in-game day 40
##   * rat populations saturating every chunk
##   * every faction converging to WAR because grievances never decay
##   * fluid dirty-cell count growing monotonically
##   * job queues growing without bound
##
## The gate is NOT "did it crash". It is "did any metric leave its band or change slope".
extends GutTest

const SOAK_TICKS: int = 1200


func test_fluid_volume_is_conserved_over_a_long_run() -> void:
	var chunk: ChunkData = TestArena.build(Vector3i.ZERO)
	var fluids := FluidDynamicsSystem.new()
	chunk.add_fluid(20, 20, 6000, MaterialLibrary.MAT_WATER)
	chunk.add_fluid(45, 45, 3000, MaterialLibrary.MAT_WATER)
	var expected: int = chunk.total_fluid_volume()

	var dirty_samples: PackedInt32Array = PackedInt32Array()
	for tick in SOAK_TICKS:
		fluids.run(chunk)
		if tick % 100 == 0:
			dirty_samples.append(chunk.dirty_cells.size())
		assert_eq(
			chunk.total_fluid_volume(),
			expected,
			"fluid conserved at tick %d of a %d-tick soak" % [tick, SOAK_TICKS]
		)

	# The dirty set must TREND DOWN, not grow monotonically. Monotonic growth is the specific
	# failure that a short test cannot see.
	var first: int = dirty_samples[0]
	var last: int = dirty_samples[dirty_samples.size() - 1]
	gut.p("SOAK  dirty cells: first=%d last=%d samples=%s" % [first, last, dirty_samples])
	assert_lte(last, first, "the dirty-cell count settles rather than growing without bound")


func test_entity_registry_does_not_leak_over_many_create_destroy_cycles() -> void:
	var before: Dictionary = ECSManager.counters()
	var baseline_alive: int = before["alive_count"]

	for _cycle in 400:
		var handle: int = ECSManager.allocate_entity()
		var row: int = EH.index_of(handle)
		ECSManager.bodies[row] = BodyComponent.new()
		ECSManager.add_component_bit(row, ComponentMask.BODY)
		ECSManager.needs[row] = NeedsComponent.new()
		ECSManager.add_component_bit(row, ComponentMask.NEEDS)
		ECSManager.destroy_entity(handle)

	var after: Dictionary = ECSManager.counters()
	assert_eq(after["alive_count"], baseline_alive, "no entity leaked across 400 cycles")
	# Rows are RECYCLED, so capacity must not grow linearly with churn.
	assert_lt(
		after["row_capacity"] - before["row_capacity"],
		10,
		"destroyed rows are reused instead of growing the table forever"
	)


func test_component_registries_are_empty_for_dead_rows() -> void:
	var handles: PackedInt64Array = PackedInt64Array()
	for _i in 50:
		var handle: int = ECSManager.allocate_entity()
		var row: int = EH.index_of(handle)
		ECSManager.bodies[row] = BodyComponent.new()
		ECSManager.needs[row] = NeedsComponent.new()
		ECSManager.chemistries[row] = ChemistryComponent.new()
		ECSManager.memories[row] = MemoryComponent.new()
		handles.append(handle)
	for i in handles.size():
		ECSManager.destroy_entity(handles[i])

	for i in handles.size():
		var row: int = EH.index_of(handles[i])
		assert_false(ECSManager.bodies.has(row), "body registry cleared")
		assert_false(ECSManager.needs.has(row), "needs registry cleared")
		assert_false(ECSManager.chemistries.has(row), "chemistry registry cleared")
		assert_false(ECSManager.memories.has(row), "memory registry cleared")


func test_memory_does_not_grow_without_bound_under_gossip_pressure() -> void:
	var memory := MemoryComponent.new()
	# Simulate the gossip loop unioning events repeatedly, including re-delivery of the same ones.
	var pool: Array[MemoryEvent] = []
	for i in 100:
		pool.append(MemoryEvent.create(&"IDLE_CHAT", &"rumour", i, false))
	for _round in 20:
		for event in pool:
			memory.remember(event)
	assert_lte(
		memory.events.size(),
		MemoryComponent.MEMORY_CAP,
		"twenty rounds of gossip cannot grow memory past its cap"
	)


func test_needs_stay_in_range_over_a_long_run() -> void:
	var chunk: ChunkData = TestArena.build(Vector3i.ZERO)
	chunk.ambient_temperature_c = 5.0
	var metabolism := MetabolismSystem.new()
	var handle: int = ECSManager.allocate_entity()
	var row: int = EH.index_of(handle)
	ECSManager.needs[row] = NeedsComponent.new()
	ECSManager.add_component_bit(row, ComponentMask.NEEDS)
	ECSManager.bodies[row] = BodyComponent.new()
	ECSManager.add_component_bit(row, ComponentMask.BODY)
	ECSManager.flush_structural_changes()

	for _tick in SOAK_TICKS:
		metabolism.run(chunk)
		var need: NeedsComponent = ECSManager.needs[row]
		assert_between(need.hunger, 0.0, 100.0, "hunger stays in range")
		assert_between(need.energy, 0.0, 100.0, "energy stays in range")
		assert_between(need.morale, 0.0, 100.0, "morale stays in range")
		assert_between(ECSManager.bodies[row].stamina, 0.0, 100.0, "stamina stays in range")

	ECSManager.destroy_entity(handle)


## Hunger must reach the interrupt threshold on a sane timescale, not in seconds or never.
func test_hunger_reaches_the_interrupt_threshold_on_a_sane_timescale() -> void:
	var need := NeedsComponent.new()
	var ticks: int = 0
	while need.hunger < JobResolutionSystem.HUNGER_ENTER and ticks < 100000:
		need.hunger += MetabolismSystem.HUNGER_PER_TICK
		ticks += 1
	# 20 Simulation ticks per in-game hour (ADR-9).
	var in_game_hours: float = float(ticks) / 20.0
	gut.p(
		"SOAK  hunger 0 -> %.0f takes %.1f in-game hours"
		% [JobResolutionSystem.HUNGER_ENTER, in_game_hours]
	)
	assert_between(
		in_game_hours, 12.0, 48.0, "an NPC gets hungry over most of a day, not seconds or weeks"
	)


## An NPC must survive the night. At a naive 1.0/tick it would gain +160 hunger overnight and
## every NPC in the world would starve every single night.
func test_npc_survives_an_eight_hour_sleep_block() -> void:
	var overnight_ticks: int = 8 * 20
	var gained: float = MetabolismSystem.HUNGER_PER_TICK * float(overnight_ticks)
	gut.p("SOAK  hunger gained across an 8-hour sleep block: %.1f" % gained)
	assert_lt(gained, 40.0, "sleeping through the night does not starve an NPC")
