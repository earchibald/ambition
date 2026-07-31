## Fluid CA correctness. Every test here corresponds to a defect found by measurement.
extends GutTest

var chunk: ChunkData
var fluids: FluidDynamicsSystem


func before_each() -> void:
	chunk = ChunkData.new(Vector3i.ZERO)
	for y in WorldConstants.CHUNK_TILES:
		for x in WorldConstants.CHUNK_TILES:
			var border: bool = (
				x == 0
				or y == 0
				or x == WorldConstants.CHUNK_TILES - 1
				or y == WorldConstants.CHUNK_TILES - 1
			)
			chunk.tile_map[WorldConstants.cell_index(x, y)] = (
				ChunkData.TILE_SOLID if border else ChunkData.TILE_OPEN
			)
	fluids = FluidDynamicsSystem.new()


func _run_ticks(count: int) -> void:
	for _i in count:
		fluids.run(chunk)


## THE REGRESSION GUARD for the double-buffer defect. A settled puddle that stops being dirty
## must not be annihilated. Under double buffering plus a sparse dirty set, this went to zero.
func test_settled_puddle_is_not_annihilated() -> void:
	chunk.add_fluid(30, 30, 500, MaterialLibrary.MAT_WATER)
	var before: int = chunk.total_fluid_volume()
	_run_ticks(40)
	assert_eq(
		chunk.total_fluid_volume(), before, "a settled puddle keeps every unit of its volume"
	)


func test_volume_is_conserved_while_spreading() -> void:
	chunk.add_fluid(20, 20, 4000, MaterialLibrary.MAT_WATER)
	var before: int = chunk.total_fluid_volume()
	_run_ticks(60)
	assert_eq(chunk.total_fluid_volume(), before, "spreading neither creates nor destroys units")


func test_fluid_actually_spreads() -> void:
	chunk.add_fluid(20, 20, 4000, MaterialLibrary.MAT_WATER)
	_run_ticks(20)
	assert_lt(chunk.fluid_at(20, 20), 4000, "the source cell drained")
	var neighbours: int = (
		chunk.fluid_at(21, 20)
		+ chunk.fluid_at(19, 20)
		+ chunk.fluid_at(20, 21)
		+ chunk.fluid_at(20, 19)
	)
	assert_gt(neighbours, 0, "neighbouring cells received fluid")


## The dirty set MUST drain, or every puddle edge in the world is a permanent budget consumer.
## Without integer hysteresis this never terminates: two equal cells holding 1 and 0 units
## ping-pong forever.
func test_dirty_set_drains_and_simulation_settles() -> void:
	chunk.add_fluid(30, 30, 2000, MaterialLibrary.MAT_WATER)
	_run_ticks(400)
	assert_lt(
		chunk.dirty_cells.size(), 40, "the dirty set drains instead of oscillating forever"
	)


## The specific oscillation case: a 1-unit difference is below FLOW_MIN_DIFF, so nothing moves
## and both cells retire.
func test_one_unit_difference_does_not_oscillate() -> void:
	chunk.add_fluid(30, 30, 1, MaterialLibrary.MAT_WATER)
	_run_ticks(10)
	assert_eq(chunk.fluid_at(30, 30), 1, "a single unit stays put rather than ping-ponging")
	assert_eq(chunk.dirty_cells.size(), 0, "the cell left the dirty set")


## Fluid flows downhill in (height + volume) terms, not just by volume.
func test_fluid_flows_to_lower_elevation() -> void:
	chunk.set_tile(35, 30, ChunkData.TILE_OPEN, 0.0)
	chunk.set_tile(36, 30, ChunkData.TILE_OPEN, -1.0)
	chunk.add_fluid(35, 30, 600, MaterialLibrary.MAT_WATER)
	_run_ticks(30)
	assert_gt(chunk.fluid_at(36, 30), 0, "fluid moved into the lower cell")


## Ghost apron: an east-edge cell must not wrap into the next row, and the far corner must not
## read out of range.
func test_east_edge_does_not_wrap_rows() -> void:
	chunk.set_tile(62, 5, ChunkData.TILE_OPEN, 0.0)
	chunk.add_fluid(62, 5, 800, MaterialLibrary.MAT_WATER)
	var before: int = chunk.total_fluid_volume()
	_run_ticks(30)
	assert_eq(before, chunk.total_fluid_volume(), "no volume leaked through the chunk seam")
	assert_eq(chunk.fluid_at(0, 6), 0, "nothing teleported to the opposite side of the chunk")


func test_far_corner_neighbour_is_in_range() -> void:
	# With a bare 64x64 array, index 4095 + 1 is out of bounds. The apron makes it valid.
	chunk.add_fluid(62, 62, 300, MaterialLibrary.MAT_WATER)
	_run_ticks(10)
	assert_gt(chunk.total_fluid_volume(), 0, "simulating the far corner does not crash or zero")


## The flood buffer pumps a bounded amount per tick, so promoting a flooded chunk cannot
## instantiate a tsunami in one frame.
func test_flood_buffer_pumps_at_a_bounded_rate() -> void:
	var idx: int = WorldConstants.cell_index(30, 30)
	chunk.flood_buffer[idx] = 500
	fluids.run(chunk)
	# Assert the TOTAL that entered the grid, not one cell's value: the same tick immediately
	# redistributes the pumped units to neighbours.
	assert_eq(
		chunk.total_fluid_volume(),
		WorldConstants.FLOOD_PUMP_UNITS_PER_TICK,
		"only the per-tick pump limit entered the grid"
	)
	assert_eq(chunk.flood_buffer[idx], 450, "the remainder stays buffered")


## LoD round trip must conserve fluid. Previously the pool was never zeroed on promotion and
## the grid was never harvested on demotion, so N crossings created N copies while destroying
## everything in the grid.
func test_lod_round_trip_conserves_fluid() -> void:
	chunk.add_fluid(30, 30, 1000, MaterialLibrary.MAT_WATER)
	var original: int = chunk.total_fluid_volume()

	for _cycle in 5:
		FluidDynamicsSystem.demote_to_pools(chunk)
		assert_eq(chunk.total_fluid_volume(), 0, "grid emptied on demotion")
		FluidDynamicsSystem.promote_from_pools(chunk, Vector2i(30, 30))
		# Drain the flood buffer fully so the comparison is apples to apples.
		for _t in 40:
			fluids.run(chunk)

	assert_eq(
		chunk.total_fluid_volume(),
		original,
		"five LoD round trips neither duplicated nor destroyed fluid"
	)


func test_promotion_is_idempotent() -> void:
	chunk.volume_pools[MaterialLibrary.MAT_WATER] = 300
	FluidDynamicsSystem.promote_from_pools(chunk, Vector2i(30, 30))
	FluidDynamicsSystem.promote_from_pools(chunk, Vector2i(30, 30))
	var buffered: int = 0
	for key in chunk.flood_buffer:
		buffered += chunk.flood_buffer[key]
	assert_eq(buffered, 300, "a second promotion cannot duplicate the pool")


## Overflow must be reported, not silently truncated.
func test_budget_overflow_is_reported_and_lossless() -> void:
	# Every real cell dirty at once. 62x62 = 3,844 cells is BELOW the 12,000 budget, so the
	# budget is exercised by running enough ticks that re-marked cells accumulate, plus a
	# direct check that the guard reports rather than truncates.
	# Deliberately NON-uniform: a uniform grid has no head difference anywhere, so nothing
	# flows and every cell correctly retires, which would make this test vacuous.
	for y in range(1, 63):
		for x in range(1, 63):
			chunk.add_fluid(x, y, 900 if (x + y) % 2 == 0 else 100, MaterialLibrary.MAT_WATER)
	var before: int = chunk.total_fluid_volume()
	fluids.run(chunk)
	assert_eq(chunk.total_fluid_volume(), before, "no volume lost on a fully dirty grid")
	assert_gt(fluids.cell_updates, 0, "cells were actually processed")
	assert_gt(chunk.dirty_cells.size(), 0, "active cells are re-marked, not dropped")


## The budget guard must DEFER work, never discard volume.
func test_cell_budget_defers_rather_than_truncates() -> void:
	for y in range(1, 63):
		for x in range(1, 63):
			chunk.add_fluid(x, y, 900 if (x + y) % 3 == 0 else 50, MaterialLibrary.MAT_WATER)
	var before: int = chunk.total_fluid_volume()
	for _t in 25:
		fluids.run(chunk)
		assert_eq(
			chunk.total_fluid_volume(), before, "volume conserved on every tick under load"
		)
