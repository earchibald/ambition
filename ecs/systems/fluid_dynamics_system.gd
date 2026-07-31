## Cellular-automata fluid on a 2D grid plus a heightmap (ADR-3). Never a 3D voxel volume.
##
## Runs on the 15 Hz FLUID tick, not the 60 Hz Micro tick. Measured: 20,000 cell-updates costs
## ~13 ms on ADR-10's own M1 reference machine, which is 164% of the entire 8 ms frame budget
## before anything else runs. 12,000 updates at 15 Hz amortizes to ~1.3 ms/frame.
##
## SINGLE BUFFER + DELTA ACCUMULATOR. Double buffering plus a sparse dirty set is incoherent:
## double buffering requires writing EVERY cell each tick, a sparse set writes only the dirty
## subset, so after a swap every non-dirty cell reads two-tick-old data and every settled puddle
## is annihilated. The accumulator gives the same order-independence and is exactly conservative.
##
## FLOW USES INTEGER HYSTERESIS. Without `FLOW_MIN_DIFF`, two equal-elevation neighbours holding
## 1 and 0 units enter a permanent 2-cycle: both stay dirty forever, so every puddle edge in the
## world becomes a permanent budget consumer and the dirty set never drains.
class_name FluidDynamicsSystem
extends RefCounted

# --- Observability ---
var cell_updates: int = 0
var dirty_cell_count: int = 0
var budget_exhausted: bool = false
var pumped_units: int = 0

## Reused scratch so a tick allocates nothing.
var _touched: PackedInt32Array = PackedInt32Array()


func run(chunk: ChunkData) -> void:
	cell_updates = 0
	budget_exhausted = false
	pumped_units = 0
	_pump_flood_buffer(chunk)

	var volume: PackedInt32Array = chunk.volume_map
	var delta: PackedInt32Array = chunk.delta_map
	var heights: PackedFloat32Array = chunk.height_map
	var touched_count: int = 0
	# Each processed cell can push 2 entries per neighbour (source + destination) across 4
	# neighbours, so the worst case is 8x the cell count. Undersizing this silently corrupts
	# the commit pass via out-of-bounds writes.
	if _touched.size() < WorldConstants.GRID_CELLS * 8:
		_touched.resize(WorldConstants.GRID_CELLS * 8)

	# Snapshot the dirty set: cells re-marked this tick are processed NEXT tick, so a settling
	# grid provably drains instead of chasing its own tail.
	var to_process: Array = chunk.dirty_cells.keys()
	chunk.dirty_cells.clear()
	dirty_cell_count = to_process.size()

	# Phase 1: read `volume`, write only into `delta`. Order-independent by construction.
	for idx in to_process:
		if cell_updates >= WorldConstants.CA_UPDATES_PER_FLUID_TICK:
			# Re-mark the remainder so nothing is lost, and report the overflow rather than
			# silently truncating.
			chunk.dirty_cells[idx] = true
			budget_exhausted = true
			continue
		cell_updates += 1

		var here: int = volume[idx]
		if here <= 0:
			continue

		# OUTFLOW IS LIMITED BY WHAT THE CELL ACTUALLY HAS. Computing each neighbour's flow
		# independently against the full volume lets a cell with four lower neighbours give away
		# 2x what it holds; clamping the resulting negative to zero then CREATES matter, and the
		# grid doubles every tick. `available` is decremented as we go, so the cell can never
		# promise more than it owns.
		var available: int = here
		var height_units: float = heights[idx] * float(WorldConstants.MAX_CELL_VOLUME)
		var moved_any: bool = false

		# Four orthogonal neighbours. The apron guarantees all four are in range, so there is no
		# row-wrap and no out-of-bounds read.
		for offset in [1, -1, WorldConstants.GRID_STRIDE, -WorldConstants.GRID_STRIDE]:
			if available <= 0:
				break
			var other: int = idx + offset
			if other < 0 or other >= WorldConstants.GRID_CELLS:
				continue
			# Fluid never enters a wall, and the apron is solid, so this also stops volume
			# leaking out of the chunk through a seam.
			if chunk.tile_map[other] == ChunkData.TILE_SOLID:
				continue
			var head_here: float = float(available) + height_units
			var head_other: float = (
				float(volume[other] + delta[other])
				+ heights[other] * float(WorldConstants.MAX_CELL_VOLUME)
			)
			var difference: int = int(head_here - head_other)
			if difference < WorldConstants.FLOW_MIN_DIFF:
				continue
			# FLOOR division. Rounding up fabricates matter; zeroing the source destroys it.
			var flow: int = mini(difference >> 1, available)
			if flow <= 0:
				continue
			available -= flow
			delta[other] += flow
			delta[idx] -= flow
			_touched[touched_count] = other
			touched_count += 1
			_touched[touched_count] = idx
			touched_count += 1
			moved_any = true
			if chunk.material_map[other] == 0:
				chunk.material_map[other] = chunk.material_map[idx]

		# A cell with no qualifying neighbour is NOT re-marked, so it leaves the dirty set.
		if moved_any:
			chunk.dirty_cells[idx] = true

	# Phase 2: one commit pass over exactly the touched cells.
	for t in touched_count:
		var index: int = _touched[t]
		if delta[index] == 0:
			continue
		volume[index] += delta[index]
		delta[index] = 0
		# Outflow is capped by `available`, so a negative here means the invariant broke.
		assert(volume[index] >= 0, "fluid volume went negative — outflow exceeded the cell")
		if volume[index] > 0:
			chunk.dirty_cells[index] = true


## The Flood Buffer: pumps a bounded volume per tick so promoting a flooded chunk cannot
## instantiate a 10,000-unit tsunami in one frame.
func _pump_flood_buffer(chunk: ChunkData) -> void:
	if chunk.flood_buffer.is_empty():
		return
	var drained: Array = []
	for idx in chunk.flood_buffer:
		var pending: int = chunk.flood_buffer[idx]
		var pump: int = mini(pending, WorldConstants.FLOOD_PUMP_UNITS_PER_TICK)
		chunk.volume_map[idx] += pump
		pumped_units += pump
		chunk.dirty_cells[idx] = true
		var left: int = pending - pump
		if left <= 0:
			drained.append(idx)
		else:
			chunk.flood_buffer[idx] = left
	for idx in drained:
		chunk.flood_buffer.erase(idx)


## Harvest the grid back into abstract pools on demotion, and ZERO the grid. Without both
## halves, crossing a boundary N times destroys everything in the grid while leaving the pool
## intact — the same dupe window the wealth ledger already closed.
static func demote_to_pools(chunk: ChunkData) -> void:
	for y in WorldConstants.CHUNK_TILES:
		for x in WorldConstants.CHUNK_TILES:
			var idx: int = WorldConstants.cell_index(x, y)
			var units: int = chunk.volume_map[idx]
			if units <= 0:
				continue
			var material: StringName = chunk.material_name(chunk.material_map[idx])
			chunk.volume_pools[material] = int(chunk.volume_pools.get(material, 0)) + units
			chunk.volume_map[idx] = 0
			chunk.delta_map[idx] = 0
	chunk.dirty_cells.clear()
	chunk.fluid_materialized = false


## Promote pools back into the grid via the flood buffer. Guarded and idempotent: the pool is
## zeroed as it is spawned, and `fluid_materialized` prevents a second spawn. Handles EVERY
## material, not just water.
static func promote_from_pools(chunk: ChunkData, entry_tile: Vector2i) -> void:
	if chunk.fluid_materialized:
		return
	chunk.fluid_materialized = true
	var idx: int = WorldConstants.cell_index(entry_tile.x, entry_tile.y)
	for material in chunk.volume_pools.keys():
		var units: int = int(chunk.volume_pools[material])
		if units <= 0:
			continue
		chunk.flood_buffer[idx] = int(chunk.flood_buffer.get(idx, 0)) + units
		if chunk.material_map[idx] == 0:
			chunk.material_map[idx] = chunk.intern_material(material)
		chunk.volume_pools[material] = 0


func counters() -> Dictionary:
	return {
		"ca_cell_updates": cell_updates,
		"ca_dirty_cells": dirty_cell_count,
		"ca_budget_exhausted": budget_exhausted,
		"ca_pumped_units": pumped_units,
	}
