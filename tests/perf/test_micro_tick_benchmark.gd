## Headless performance harness (ADR-10).
##
## ADR-10's budgets were asserted, never measured — and measurement showed the CA budget was
## 164% of the whole frame budget on its own reference hardware. This harness exists so that
## never happens again: it prints REAL numbers for N entities so the budgets stay honest.
##
## It deliberately does NOT hard-fail on absolute timing, because CI runners vary wildly and a
## flaky perf gate gets disabled, which is worse than no gate. It fails only on scaling that is
## qualitatively wrong (super-linear growth), and always prints the numbers for a human to read.
extends GutTest

const SAMPLE_TICKS: int = 30
const ENTITY_COUNTS: Array[int] = [50, 500, 1500]

var chunk: ChunkData
var hash: SpatialHash
var collision: CollisionResolveSystem
var spawned: PackedInt64Array = PackedInt64Array()


func before_each() -> void:
	chunk = TestArena.build(Vector3i.ZERO)
	hash = SpatialHash.new()
	hash.set_origin(Vector3(-64.0, 0.0, -64.0))
	collision = CollisionResolveSystem.new()
	spawned = PackedInt64Array()


func after_each() -> void:
	for i in spawned.size():
		ECSManager.destroy_entity(spawned[i])
	ECSManager.flush_structural_changes()


func _populate(count: int) -> void:
	for i in count:
		var handle: int = ECSManager.allocate_entity()
		var row: int = EH.index_of(handle)
		# Spread across the whole open interior, avoiding the border and the interior wall.
		# Density matters enormously here: cramming N entities into a small area makes
		# entity-vs-entity checks look quadratic when the real cause is occupancy per cell.
		# 60x50 open tiles approximates the ADR-10 implied density at N=1500.
		var x: float = 25.0 + float(i % 37)
		var z: float = 2.0 + float((i / 37) % 60)
		ECSManager.set_position(row, Vector3(x, 0.9, z))
		ECSManager.set_velocity(row, Vector3(0.5, 0.0, 0.3))
		ECSManager.add_component_bit(row, ComponentMask.POSITION)
		ECSManager.bounds[row] = BoundsComponent.new(Vector3(0.2, 0.2, 0.2))
		ECSManager.add_component_bit(row, ComponentMask.BOUNDS)
		spawned.append(handle)
	ECSManager.flush_structural_changes()


func test_micro_tick_scales_with_entity_count() -> void:
	var results: Array = []
	for count in ENTITY_COUNTS:
		for i in spawned.size():
			ECSManager.destroy_entity(spawned[i])
		spawned = PackedInt64Array()
		ECSManager.flush_structural_changes()
		_populate(count)

		var rows: PackedInt32Array = ECSManager.query(ComponentMask.SPATIAL)
		var start: int = Time.get_ticks_usec()
		for _t in SAMPLE_TICKS:
			collision.run(1.0 / 60.0, chunk, hash)
			hash.rebuild(rows)
		var per_tick_ms: float = (
			float(Time.get_ticks_usec() - start) / 1000.0 / float(SAMPLE_TICKS)
		)
		results.append({"count": count, "ms": per_tick_ms})
		gut.p(
			"PERF  entities=%5d  micro(collision+hash)=%6.3f ms  budget=%.1f ms  %s" % [
				count,
				per_tick_ms,
				WorldConstants.MICRO_BUDGET_MS,
				"OVER" if per_tick_ms > WorldConstants.MICRO_BUDGET_MS else "ok",
			]
		)

	assert_gt(results.size(), 0, "the benchmark produced measurements")

	# Scaling sanity: 30x the entities must not cost more than ~60x the time. Anything worse
	# means an accidental O(n^2) crept into a hot loop.
	var smallest: float = maxf(results[0]["ms"], 0.001)
	var largest: float = results[results.size() - 1]["ms"]
	var entity_ratio: float = float(ENTITY_COUNTS[ENTITY_COUNTS.size() - 1]) / float(ENTITY_COUNTS[0])
	assert_lt(
		largest / smallest,
		entity_ratio * 2.0,
		"micro-tick cost scales roughly linearly, not quadratically, in entity count"
	)


func test_fluid_ca_cost_is_reported() -> void:
	var fluids := FluidDynamicsSystem.new()
	for y in range(1, 63):
		for x in range(1, 63):
			chunk.add_fluid(x, y, 900 if (x + y) % 3 == 0 else 50, MaterialLibrary.MAT_WATER)

	var start: int = Time.get_ticks_usec()
	fluids.run(chunk)
	var elapsed_ms: float = float(Time.get_ticks_usec() - start) / 1000.0
	var per_cell_us: float = 0.0
	if fluids.cell_updates > 0:
		per_cell_us = (elapsed_ms * 1000.0) / float(fluids.cell_updates)

	gut.p(
		"PERF  CA cells=%5d  %6.3f ms  %.3f us/cell  -> 20k cells would cost %.1f ms" % [
			fluids.cell_updates, elapsed_ms, per_cell_us, per_cell_us * 20000.0 / 1000.0
		]
	)
	assert_gt(fluids.cell_updates, 0, "the CA benchmark actually processed cells")


func test_spatial_hash_rebuild_cost_is_reported() -> void:
	_populate(1500)
	var rows: PackedInt32Array = ECSManager.query(ComponentMask.SPATIAL)
	var start: int = Time.get_ticks_usec()
	for _t in SAMPLE_TICKS:
		hash.rebuild(rows)
	var per_tick_ms: float = float(Time.get_ticks_usec() - start) / 1000.0 / float(SAMPLE_TICKS)
	gut.p("PERF  spatial hash rebuild, 1500 entities = %.3f ms" % per_tick_ms)
	assert_lt(per_tick_ms, WorldConstants.MICRO_BUDGET_MS, "the rebuild fits inside one frame")
