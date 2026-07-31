## Authoritative ECS state owner.
##
## MUST `extends Node` to be autoloadable. Load order is ECSEvents -> ECSManager ->
## GameLoopManager, so `_ready()` here may touch ECSEvents but NOT GameLoopManager.
##
## SPRINT 0 SCOPE: entity identity only — the generational handle allocator, the alive set,
## the canonical registry list, and atomic destroy (ADR-7). Component columns, the query
## facade's typed columns, and the systems land in Sprint 1.
##
## Handles are packed ints (ADR-19). Registries key on the handle's INDEX and validate the
## generation at the API boundary, which is what lets hot storage be dense `Packed*Array`
## columns later (ADR-10) without changing call sites.
extends Node

# --- Observability counters (debug spec §4, read-only surfaces). ---
var alive_count: int = 0
var destroy_count: int = 0
var stale_handle_rejections: int = 0
var indices_reused: int = 0

## Per-index generation. Index i is alive iff `_alive[i]` is true; a retired index keeps its
## generation so stale handles remain detectable after reuse.
var _generations: PackedInt32Array = PackedInt32Array()
var _alive: PackedByteArray = PackedByteArray()
var _free_indices: PackedInt32Array = PackedInt32Array()

## Canonical registry list (ADR-7). `destroy_entity` MUST clear an index from every entry
## here in one operation. Sprint 1 appends its component registries; the destroy path is
## written once so adding a registry cannot silently leak.
var _registries: Array[Dictionary] = []


func _ready() -> void:
	_reserve_player_index()


## ADR-14: Player = Entity index 0 = Faction 0. Index 0 is reserved at boot so no other
## entity can ever occupy the player slot.
func _reserve_player_index() -> void:
	var player := allocate_entity()
	assert(EH.index_of(player) == WorldConstants.PLAYER_INDEX, "player must occupy index 0")


func register_registry(registry: Dictionary) -> void:
	_registries.append(registry)


func allocate_entity() -> int:
	var index: int
	if _free_indices.is_empty():
		index = _generations.size()
		_generations.append(1)
		_alive.append(1)
	else:
		index = _free_indices[_free_indices.size() - 1]
		_free_indices.remove_at(_free_indices.size() - 1)
		# Bump on REUSE so every previously issued handle for this index is now stale.
		_generations[index] = _generations[index] + 1
		_alive[index] = 1
		indices_reused += 1
	alive_count += 1
	return EH.make(index, _generations[index])


## True only if the handle names a live entity at the generation it was issued for.
func is_alive(handle: int) -> bool:
	if not EH.is_valid(handle):
		return false
	var index := EH.index_of(handle)
	if index >= _generations.size():
		return false
	if _alive[index] == 0:
		return false
	return _generations[index] == EH.gen_of(handle)


## Atomic destroy (ADR-7): removes the index from EVERY registered registry, or from none.
## Returns false for a stale/invalid handle without mutating anything.
func destroy_entity(handle: int) -> bool:
	if not is_alive(handle):
		stale_handle_rejections += 1
		return false
	var index := EH.index_of(handle)
	for registry in _registries:
		registry.erase(index)
	_alive[index] = 0
	_free_indices.append(index)
	alive_count -= 1
	destroy_count += 1
	ECSEvents.entity_destroyed.emit(handle)
	return true


## Current handle for the player slot, whose generation changes across the death loop.
func player_handle() -> int:
	if _generations.is_empty():
		return EH.INVALID
	return EH.make(WorldConstants.PLAYER_INDEX, _generations[WorldConstants.PLAYER_INDEX])


func is_player(handle: int) -> bool:
	return EH.index_of(handle) == WorldConstants.PLAYER_INDEX and is_alive(handle)


## Total indices ever allocated, including retired ones. Used by the debug inspector and by
## the save format's free-list state.
func index_capacity() -> int:
	return _generations.size()


func generation_at(index: int) -> int:
	if index < 0 or index >= _generations.size():
		return 0
	return _generations[index]


func registry_count() -> int:
	return _registries.size()


## Snapshot for the debug overlay and the soak harness CSV (ADR-20).
func counters() -> Dictionary:
	return {
		"alive_count": alive_count,
		"index_capacity": index_capacity(),
		"free_indices": _free_indices.size(),
		"destroy_count": destroy_count,
		"stale_handle_rejections": stale_handle_rejections,
		"indices_reused": indices_reused,
		"registries": _registries.size(),
	}
