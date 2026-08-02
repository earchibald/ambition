## Level-of-detail transitions (ECS spec section 3).
##
## Per ADR-3 the Active set is the 3x3 SAME-FLOOR neighbourhood (9 chunks) plus the single
## entry/landing chunk of the floor directly above and below — NOT a 3x3x3 cube.
class_name LoDSystem
extends RefCounted

var transitions: int = 0
var active_entities: int = 0
var over_budget: bool = false


## Chunks that should be Active for a player standing in `centre`.
static func active_set(centre: Vector3i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			out.append(Vector3i(centre.x + dx, centre.y + dy, centre.z))
	# The landing chunk directly above and below, for stair and elevator transitions.
	out.append(Vector3i(centre.x, centre.y, centre.z + 1))
	out.append(Vector3i(centre.x, centre.y, centre.z - 1))
	return out


static func is_in_active_set(chunk_id: Vector3i, centre: Vector3i) -> bool:
	if chunk_id.z == centre.z:
		return absi(chunk_id.x - centre.x) <= 1 and absi(chunk_id.y - centre.y) <= 1
	if absi(chunk_id.z - centre.z) == 1:
		return chunk_id.x == centre.x and chunk_id.y == centre.y
	return false


## Updates each entity's LoD from its chunk membership, and reports budget pressure.
func run(player_chunk: Vector3i) -> void:
	transitions = 0
	active_entities = 0
	var rows: PackedInt32Array = ECSManager.query(ComponentMask.LOD)
	for i in rows.size():
		var row: int = rows[i]
		var lod: LoDComponent = ECSManager.lods[row]
		var chunk_id: Vector3i = ECSManager.chunk_id_of(row)
		var desired: ECSEnums.LoD = ECSEnums.LoD.ABSTRACTED
		if is_in_active_set(chunk_id, player_chunk):
			desired = ECSEnums.LoD.ACTIVE
		elif absi(chunk_id.x - player_chunk.x) <= 2 and absi(chunk_id.y - player_chunk.y) <= 2:
			desired = ECSEnums.LoD.SIMULATED

		if desired != lod.current_state:
			lod.current_state = desired
			transitions += 1
			ECSEvents.chunk_state_changed.emit(chunk_id, desired == ECSEnums.LoD.ACTIVE)
		if desired == ECSEnums.LoD.ACTIVE:
			active_entities += 1

	# ADR-10 caps. Reported rather than silently exceeded, so the budget is visible.
	over_budget = active_entities > WorldConstants.ACTIVE_ENTITY_HARD_CAP


func counters() -> Dictionary:
	return {
		"lod_transitions": transitions,
		"lod_active_entities": active_entities,
		"lod_over_budget": over_budget,
	}
