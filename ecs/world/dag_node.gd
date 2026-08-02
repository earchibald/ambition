## One node in the history graph (DAG spec §2, Sprint 2 scaffolding §1).
##
## Pure data. The DAG is generated in memory before any chunk exists and before any entity is
## created, so nothing here may reference an EntityHandle, a ChunkData, or a scene node.
##
## The `anchor_chunk_id` is the GESTALT FIX from the roadmap: every faction owns a specific
## chunk — a plaza, a throne room — and its people spawn THERE. Defaulting to the world origin
## piles every faction on top of each other at (0,0,0) and reads as a generation bug.
class_name DAGNode
extends RefCounted

## Sentinel for "no anchor has been assigned yet". Vector3i.ZERO is a legal chunk, so it cannot
## double as the unset value — that ambiguity is exactly how everything ends up at the origin.
const NO_ANCHOR := Vector3i(2147483647, 2147483647, 2147483647)

var node_id: int = 0
var type: ECSEnums.NodeType = ECSEnums.NodeType.FACTION
var status: ECSEnums.NodeStatus = ECSEnums.NodeStatus.ACTIVE
var birth_epoch: int = 0
var death_epoch: int = -1
var name: StringName = &""
var culture_tags: Array[StringName] = []
var tags: Array[StringName] = []

var anchor_chunk_id: Vector3i = NO_ANCHOR
var home_floor: int = 0

## Faction-specific.
var population: int = 0
var abstract_wealth_ledger: Dictionary = {}

## Set when this faction was conquered, so the chronicle can say BY WHOM.
var conquered_by: int = -1


func is_active() -> bool:
	return status == ECSEnums.NodeStatus.ACTIVE


func has_anchor() -> bool:
	return anchor_chunk_id != NO_ANCHOR


## Total ledger value in raw material units. Used by the LoD conservation property test, which
## asserts this is invariant across boundary crossings.
func ledger_total() -> int:
	var total: int = 0
	for material in abstract_wealth_ledger:
		total += int(abstract_wealth_ledger[material])
	return total


func add_wealth(material: StringName, amount: int) -> void:
	abstract_wealth_ledger[material] = int(abstract_wealth_ledger.get(material, 0)) + amount


## ADR-21: JSON coerces every number to a double, so integers above 2^53 are silently corrupted.
## Ledger amounts and populations stay well inside that, but node ids are written explicitly as
## ints so a future save format cannot quietly widen them.
func to_dict() -> Dictionary:
	return {
		"node_id": node_id,
		"type": int(type),
		"status": int(status),
		"birth_epoch": birth_epoch,
		"death_epoch": death_epoch,
		"name": String(name),
		"culture_tags": culture_tags.map(func(t: StringName) -> String: return String(t)),
		"anchor": [anchor_chunk_id.x, anchor_chunk_id.y, anchor_chunk_id.z],
		"home_floor": home_floor,
		"population": population,
		"ledger": abstract_wealth_ledger.duplicate(),
		"conquered_by": conquered_by,
	}
