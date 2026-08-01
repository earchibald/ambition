## One historical event linking two DAG nodes (DAG spec §2).
##
## The scaffolding sketched edges as bare Dictionaries. A typed record is used instead for the
## same reason `ECSEnums` exists: a misspelled key in a Dictionary is a silent nil at read time,
## and this graph is the ONLY record of why the world looks the way it does. There is no second
## source to reconcile against when an edge turns out to be malformed.
class_name DAGEdge
extends RefCounted

var source_id: int = -1
var target_id: int = -1
var type: ECSEnums.EdgeType = ECSEnums.EdgeType.FOUNDED
var epoch: int = 0


static func create(
	source_id: int, target_id: int, type: ECSEnums.EdgeType, epoch: int
) -> DAGEdge:
	var edge := DAGEdge.new()
	edge.source_id = source_id
	edge.target_id = target_id
	edge.type = type
	edge.epoch = epoch
	return edge


func to_dict() -> Dictionary:
	return {
		"source_id": source_id,
		"target_id": target_id,
		"type": int(type),
		"epoch": epoch,
	}
