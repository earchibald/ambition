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
##
## GAS IS THE SAME GRID AT A DIFFERENT TEMPERATURE (Sprint 4 §1). A material is gaseous when the
## chunk's ambient temperature is at or above its boiling point — so heating a room past 100 C
## turns its puddles into steam without a second grid, a second buffer, or a second conservation
## contract. Two behaviours change, and only two:
##   * ELEVATION STOPS MATTERING. Liquid flows downhill; gas fills whatever volume it is in. The
##     height term is dropped from the head comparison, so steam climbs a ledge that water pools
##     below.
##   * IT DISSIPATES. Gas thins out and eventually vanishes. This is a DELIBERATE break in the
##     conservation invariant, and it is confined to gaseous cells: the LoD conservation property
##     asserted since Sprint 2 still holds exactly for liquids, which is what it was written
##     about. A gas that conserved would be a permanent fog bank the player could never clear.
class_name FluidDynamicsSystem
extends RefCounted

## Fraction of a gaseous cell's volume lost per fluid tick. 12% at 15 Hz halves a cloud in about
## 0.4 s and clears it in ~2 s, which is long enough to see and short enough not to accumulate.
const GAS_DISSIPATION: float = 0.12

## Below this a gaseous cell is rounded away rather than left to decay by fractions forever.
const GAS_MIN_UNITS: int = 2

# --- Observability ---
var cell_updates: int = 0
var dirty_cell_count: int = 0
var budget_exhausted: bool = false
var pumped_units: int = 0
var gas_cells: int = 0
var dissipated_units: int = 0

## Reused scratch so a tick allocates nothing.
var _touched: PackedInt32Array = PackedInt32Array()

## Interned material id -> 1 when it is gaseous at this tick's ambient temperature. Rebuilt once
## per tick, because ambient changes and boiling points do not.
##
## THIS IS A TABLE, NOT A FUNCTION CALL, and the difference was measured. The first version asked
## `_is_gaseous()` per processed cell — a call plus a Dictionary probe plus a `MaterialLibrary`
## lookup — inside the hottest loop in the build. It cost **+48%**: 0.85 to 1.25 us/cell, which
## at ADR-10's 20,000-cell figure is 17 ms becoming 25 ms, against an 8 ms budget for ALL Micro
## systems. A flat array index plus the `_any_gas` early-out costs nothing measurable, and the
## overwhelmingly common case — a 20 C room where nothing boils — never indexes it at all.
var _gas_by_id: PackedByteArray = PackedByteArray()
## False when nothing in this chunk is gaseous, which is almost always. One bool test per cell.
var _any_gas: bool = false


func run(chunk: ChunkData) -> void:
	cell_updates = 0
	budget_exhausted = false
	pumped_units = 0
	gas_cells = 0
	dissipated_units = 0
	_build_gas_table(chunk)
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
		# Gas ignores elevation entirely — that is the whole difference between a puddle and a
		# cloud. The height term is zeroed rather than the neighbour loop being branched, so the
		# flow arithmetic stays byte-identical for both and exactly ONE behaviour changes.
		var is_gas: bool = _any_gas and _gas_by_id[chunk.material_map[idx]] == 1
		if is_gas:
			gas_cells += 1
		var height_units: float = 0.0
		if not is_gas:
			height_units = heights[idx] * float(WorldConstants.MAX_CELL_VOLUME)
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
			# BOTH sides drop the height term for gas, not just the source. Comparing a gas
			# source's zeroed head against a liquid-style neighbour head would make a cloud
			# refuse to climb rather than climb freely — the bug the zeroing exists to avoid.
			var other_height: float = 0.0
			if not is_gas:
				other_height = heights[other] * float(WorldConstants.MAX_CELL_VOLUME)
			var head_other: float = float(volume[other] + delta[other]) + other_height
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

	_dissipate_gas(chunk, to_process)


## Gas thins out. Runs over the cells PROCESSED this tick, not over the surviving dirty set.
##
## The distinction is the whole correctness of this pass. Phase 1 drops a cell from the dirty set
## the moment it stops flowing — that is what makes a settling puddle provably drain — so a gas
## cloud that has finished spreading is already gone from the set by the time this runs. Iterating
## the survivors left exactly the residue that had stopped moving, permanently, which is the fog
## bank this feature exists to avoid. Gaseous cells are re-marked here instead, so a cloud keeps
## decaying after it stops flowing and only leaves the set when it is empty.
##
## THIS IS THE ONE PLACE THE GRID IS NOT CONSERVATIVE, and it is deliberate. Everything else in
## this file exists to make volume exactly conservative; the LoD conservation property test stays
## valid because it is written about liquids.
func _dissipate_gas(chunk: ChunkData, processed: Array) -> void:
	if not _any_gas:
		return
	for idx in processed:
		var units: int = chunk.volume_map[idx]
		if units <= 0 or not _is_gaseous(chunk, chunk.material_map[idx]):
			continue
		# At least one unit, or a cell of 8 decays by 0.96 -> 0 and sits there forever.
		var lost: int = maxi(1, int(float(units) * GAS_DISSIPATION))
		if units - lost < GAS_MIN_UNITS:
			lost = units
		chunk.volume_map[idx] = units - lost
		dissipated_units += lost
		if chunk.volume_map[idx] > 0:
			chunk.dirty_cells[idx] = true


## Which of this chunk's interned materials are gases AT THIS TEMPERATURE. Boiling point comes
## from the material library, so this is the same physics the thermodynamics phase model uses
## rather than a second, disagreeing notion of what "gas" means. A `NAN` boil means the material
## chars instead of boiling and is never gaseous.
##
## Built once per tick. A chunk has a handful of materials and tens of thousands of cells.
func _build_gas_table(chunk: ChunkData) -> void:
	var count: int = chunk.material_count()
	if _gas_by_id.size() < count:
		_gas_by_id.resize(count)
	_any_gas = false
	# Id 0 means "no material" and is never a gas.
	_gas_by_id[0] = 0
	for interned in range(1, count):
		var boil: float = MaterialLibrary.field(chunk.material_name(interned), "boil", NAN)
		var gaseous: bool = not is_nan(boil) and chunk.ambient_temperature_c >= boil
		_gas_by_id[interned] = 1 if gaseous else 0
		_any_gas = _any_gas or gaseous


## Table lookup, guarded by the early-out. Kept as a named function only because it is called
## from three places; it inlines to an array index.
func _is_gaseous(_chunk: ChunkData, interned: int) -> bool:
	return _any_gas and interned < _gas_by_id.size() and _gas_by_id[interned] == 1


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
		"ca_gas_cells": gas_cells,
		"ca_dissipated": dissipated_units,
	}
