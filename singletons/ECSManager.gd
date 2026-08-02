## Authoritative ECS state owner.
##
## MUST `extends Node` to be autoloadable. Load order is ECSEvents -> ECSManager -> everything
## else, so `_ready()` here may touch ECSEvents but nothing loaded after it.
##
## STORAGE SHAPE (ADR-19). The query facade's SIGNATURE is the load-bearing decision, not its
## backing implementation, because handle-list-versus-row-list is what every system's inner loop
## is written against. So:
##   * `query(mask)` returns `PackedInt32Array` of dense ROW indices, never handles.
##   * Hot position/velocity data lives in typed COLUMNS fetched once per system per tick,
##     outside the loop — never via per-entity accessor objects.
##   * `resolve(handle)` is an explicit COLD-PATH call for boundaries (events, UI, save).
##   * Rows are returned in ascending order, so the later archetype-block compaction is a no-op
##     at every call site.
##
## In Sprint 1 a row IS the entity index. That keeps rows stable and monotonic while leaving the
## contract free to swap in compacted archetype blocks later without touching a single system.
extends Node

## Rows grow in blocks so the Packed columns are not resized one element at a time.
const GROW_BLOCK: int = 256

# --- Observability counters (debug spec §4, read-only surfaces). ---
var alive_count: int = 0
var destroy_count: int = 0
var stale_handle_rejections: int = 0
var indices_reused: int = 0
var query_cache_rebuilds: int = 0

# --- Hot position columns (SoA). Indexed by ROW. ---
var col_pos_x: PackedFloat32Array = PackedFloat32Array()
var col_pos_y: PackedFloat32Array = PackedFloat32Array()
var col_pos_z: PackedFloat32Array = PackedFloat32Array()
var col_vel_x: PackedFloat32Array = PackedFloat32Array()
var col_vel_y: PackedFloat32Array = PackedFloat32Array()
var col_vel_z: PackedFloat32Array = PackedFloat32Array()
var col_floor: PackedInt32Array = PackedInt32Array()
var col_chunk_x: PackedInt32Array = PackedInt32Array()
var col_chunk_y: PackedInt32Array = PackedInt32Array()

## Abstract-graph traversal state for Simulated movers, so a world coordinate can be
## reconstructed for interception and promotion to Active.
var col_edge: PackedInt32Array = PackedInt32Array()
var col_edge_progress: PackedFloat32Array = PackedFloat32Array()
var col_edge_speed: PackedFloat32Array = PackedFloat32Array()
var col_node_id: PackedInt32Array = PackedInt32Array()

# --- Cold component registries, keyed by ROW. ---
var bounds: Dictionary = {}
var physicals: Dictionary = {}
var materials: Dictionary = {}
var chemistries: Dictionary = {}
var qualities: Dictionary = {}
var bodies: Dictionary = {}
var needs: Dictionary = {}
var perceptions: Dictionary = {}
var emitters: Dictionary = {}
var inventories: Dictionary = {}
var containers: Dictionary = {}
var jobs: Dictionary = {}
var schedules: Dictionary = {}
var professions: Dictionary = {}
var social_identities: Dictionary = {}
var ownerships: Dictionary = {}
var memories: Dictionary = {}
var ephemerals: Dictionary = {}
var lods: Dictionary = {}
var materializations: Dictionary = {}
var minds: Dictionary = {}
var heat_sources: Dictionary = {}
var loose_items: Dictionary = {}
var player_inputs: Dictionary = {}
## One per faction, on a macro-entity that owns no position. THE abstract wealth ledger.
var faction_cores: Dictionary = {}
## Routes in progress. A component, not system state, so a Simulated mover keeps its progress
## across a LoD demotion instead of restarting from its anchor (review G4).
var locomotions: Dictionary = {}

## Pending ActionIntents per row. Popped by the Micro tick.
var action_queues: Dictionary = {}

## Rows in use. Distinct from the Packed columns' capacity, which grows in blocks.
var _row_count: int = 0

var _generations: PackedInt32Array = PackedInt32Array()
var _alive: PackedByteArray = PackedByteArray()
var _free_indices: PackedInt32Array = PackedInt32Array()
var _masks: PackedInt32Array = PackedInt32Array()

## Canonical registry list (ADR-7). `destroy_entity` clears a row from EVERY entry here in one
## operation. Written once, so adding a registry cannot silently leak.
var _registries: Array[Dictionary] = []

## mask -> PackedInt32Array of rows. Invalidated wholesale on any structural change, which is
## deferred to a tick boundary so rows stay stable for the duration of a system pass.
var _query_cache: Dictionary = {}
var _structure_dirty: bool = true


func _ready() -> void:
	_register_all_registries()
	_reserve_player_row()


func _register_all_registries() -> void:
	for registry in [
		bounds,
		physicals,
		materials,
		chemistries,
		qualities,
		bodies,
		needs,
		perceptions,
		emitters,
		inventories,
		containers,
		jobs,
		schedules,
		professions,
		social_identities,
		ownerships,
		memories,
		ephemerals,
		lods,
		materializations,
		minds,
		heat_sources,
		loose_items,
		player_inputs,
		faction_cores,
		locomotions,
		action_queues,
	]:
		_registries.append(registry)


## ADR-14: Player = row 0 = Faction 0. Reserved at boot so nothing else can occupy the slot.
func _reserve_player_row() -> void:
	var player := allocate_entity()
	assert(EH.index_of(player) == WorldConstants.PLAYER_INDEX, "player must occupy row 0")


func register_registry(registry: Dictionary) -> void:
	_registries.append(registry)


# --- Identity ------------------------------------------------------------------------------


func allocate_entity() -> int:
	var row: int
	if _free_indices.is_empty():
		# `_row_count` is the number of rows in use. The Packed columns are grown in blocks, so
		# their .size() is CAPACITY and must never be used as the next row index.
		row = _row_count
		_row_count += 1
		_grow_to(_row_count)
		_generations[row] = 1
		_alive[row] = 1
	else:
		row = _free_indices[_free_indices.size() - 1]
		_free_indices.remove_at(_free_indices.size() - 1)
		# Bump on REUSE, so every handle previously issued for this row is now stale.
		_generations[row] = _generations[row] + 1
		_alive[row] = 1
		indices_reused += 1
	_masks[row] = ComponentMask.NONE
	_clear_columns(row)
	alive_count += 1
	_structure_dirty = true
	return EH.make(row, _generations[row])


func _grow_to(size: int) -> void:
	if _generations.size() >= size:
		return
	var target: int = int(ceil(float(size) / GROW_BLOCK)) * GROW_BLOCK
	_generations.resize(target)
	_alive.resize(target)
	_masks.resize(target)
	col_pos_x.resize(target)
	col_pos_y.resize(target)
	col_pos_z.resize(target)
	col_vel_x.resize(target)
	col_vel_y.resize(target)
	col_vel_z.resize(target)
	col_floor.resize(target)
	col_chunk_x.resize(target)
	col_chunk_y.resize(target)
	col_edge.resize(target)
	col_edge_progress.resize(target)
	col_edge_speed.resize(target)
	col_node_id.resize(target)


func _clear_columns(row: int) -> void:
	col_pos_x[row] = 0.0
	col_pos_y[row] = 0.0
	col_pos_z[row] = 0.0
	col_vel_x[row] = 0.0
	col_vel_y[row] = 0.0
	col_vel_z[row] = 0.0
	col_floor[row] = 0
	col_chunk_x[row] = 0
	col_chunk_y[row] = 0
	col_edge[row] = -1
	col_edge_progress[row] = 0.0
	col_edge_speed[row] = 0.0
	col_node_id[row] = -1


func is_alive(handle: int) -> bool:
	if not EH.is_valid(handle):
		return false
	var row := EH.index_of(handle)
	if row >= _row_count:
		return false
	if _alive[row] == 0:
		return false
	return _generations[row] == EH.gen_of(handle)


## COLD PATH. Resolves a handle to a row, or -1 if stale. Deliberately awkward to call inside a
## hot loop — systems iterate rows from `query()` instead.
func resolve(handle: int) -> int:
	if not is_alive(handle):
		stale_handle_rejections += 1
		return -1
	return EH.index_of(handle)


## Boundary use only: rebuild a handle from a row for an event, UI, or save payload.
func handle_of(row: int) -> int:
	if row < 0 or row >= _row_count or _alive[row] == 0:
		return EH.INVALID
	return EH.make(row, _generations[row])


## Atomic destroy (ADR-7): removes the row from EVERY registered registry, or from none.
func destroy_entity(handle: int) -> bool:
	if not is_alive(handle):
		stale_handle_rejections += 1
		return false
	var row := EH.index_of(handle)
	for registry in _registries:
		registry.erase(row)
	_masks[row] = ComponentMask.NONE
	_alive[row] = 0
	_free_indices.append(row)
	alive_count -= 1
	destroy_count += 1
	_structure_dirty = true
	ECSEvents.entity_destroyed.emit(handle)
	return true


## Retires whoever currently occupies a row and hands the slot to a successor, WITHOUT freeing
## the row (ADR-14, ADR-19).
##
## Row 0 is reserved for the player forever, so the ordinary destroy path is wrong for a death:
## it would push row 0 onto the free list and let the next allocation hand the player's reserved
## slot to a rat. This clears the components and bumps the generation, so every handle anyone
## still holds to the previous adventurer fails `is_alive` rather than silently resolving to
## their replacement — which is the subtlest possible bug and the reason handles carry a
## generation at all.
func bump_generation(row: int) -> int:
	assert(row >= 0 and row < _row_count, "cannot bump a row that was never allocated")
	for registry in _registries:
		registry.erase(row)
	_masks[row] = ComponentMask.NONE
	var was_alive: bool = _alive[row] == 1
	_generations[row] += 1
	_alive[row] = 1
	if not was_alive:
		alive_count += 1
	_structure_dirty = true
	return handle_of(row)


# --- Component mask & query facade (ADR-13 / ADR-19) ---------------------------------------


func add_component_bit(row: int, bit: int) -> void:
	_masks[row] = _masks[row] | bit
	_structure_dirty = true


func remove_component_bit(row: int, bit: int) -> void:
	_masks[row] = _masks[row] & ~bit
	_structure_dirty = true


func mask_of(row: int) -> int:
	if row < 0 or row >= _masks.size():
		return ComponentMask.NONE
	return _masks[row]


func has_components(row: int, mask: int) -> bool:
	return (_masks[row] & mask) == mask


## THE query entry point. Returns ascending ROW indices whose mask is a superset of `mask`.
## Never returns handles; never scans linearly at the call site.
func query(mask: int) -> PackedInt32Array:
	if _structure_dirty:
		_query_cache.clear()
		_structure_dirty = false
	if _query_cache.has(mask):
		return _query_cache[mask]
	var rows := PackedInt32Array()
	for row in range(_row_count):
		if _alive[row] == 0:
			continue
		if (_masks[row] & mask) == mask:
			rows.append(row)
	_query_cache[mask] = rows
	query_cache_rebuilds += 1
	return rows


## Rows matching `mask` that are ALSO on the given floor.
##
## Floors are discrete 2.5D planes (ADR-3) stacked at the SAME world X and Z — the floor index
## lives in `chunk_id.z`, not in the Y coordinate. So an entity on floor 0 and one on floor -1 can
## occupy the identical world position, and the spatial hash, which is 2D, cannot tell them apart.
## Without this filter a villager upstairs collides with you downstairs, is picked by your cursor,
## and is perceived through solid rock.
func rows_on_floor(mask: int, floor_index: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for row in query(mask):
		if col_floor[row] == floor_index:
			out.append(row)
	return out


## Structural changes are applied immediately but the cache is only rebuilt at a tick boundary,
## so rows stay stable for the duration of a system pass.
func flush_structural_changes() -> void:
	if _structure_dirty:
		_query_cache.clear()
		_structure_dirty = false


# --- Position helpers (boundary/readability only; hot loops use the columns directly) -------


func position_of(row: int) -> Vector3:
	return Vector3(col_pos_x[row], col_pos_y[row], col_pos_z[row])


func set_position(row: int, value: Vector3) -> void:
	col_pos_x[row] = value.x
	col_pos_y[row] = value.y
	col_pos_z[row] = value.z


func velocity_of(row: int) -> Vector3:
	return Vector3(col_vel_x[row], col_vel_y[row], col_vel_z[row])


func set_velocity(row: int, value: Vector3) -> void:
	col_vel_x[row] = value.x
	col_vel_y[row] = value.y
	col_vel_z[row] = value.z


func chunk_id_of(row: int) -> Vector3i:
	return Vector3i(col_chunk_x[row], col_chunk_y[row], col_floor[row])


# --- Player identity (ADR-14) ---------------------------------------------------------------


func player_handle() -> int:
	if _row_count == 0:
		return EH.INVALID
	return handle_of(WorldConstants.PLAYER_INDEX)


func is_player(handle: int) -> bool:
	return EH.index_of(handle) == WorldConstants.PLAYER_INDEX and is_alive(handle)


# --- Action intents --------------------------------------------------------------------------


func push_intent(row: int, intent: ActionIntent) -> void:
	if not action_queues.has(row):
		action_queues[row] = []
	action_queues[row].append(intent)


func take_intents(row: int) -> Array:
	if not action_queues.has(row):
		return []
	var queued: Array = action_queues[row]
	action_queues[row] = []
	return queued


# --- Introspection --------------------------------------------------------------------------


func row_capacity() -> int:
	return _row_count


func counters() -> Dictionary:
	return {
		"alive_count": alive_count,
		"row_capacity": row_capacity(),
		"free_rows": _free_indices.size(),
		"destroy_count": destroy_count,
		"stale_handle_rejections": stale_handle_rejections,
		"indices_reused": indices_reused,
		"query_cache_rebuilds": query_cache_rebuilds,
		"registries": _registries.size(),
	}
