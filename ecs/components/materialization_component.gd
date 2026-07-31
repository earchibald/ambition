## Controls whether an entity ledgerizes or keeps identity when LoD downgrades.
##
## Only LEDGERIZE items become ledger entries. Equipped gear, artifacts, containers, stash
## contents, and caravan cargo preserve identity through manifests (invariants section 2).
class_name MaterializationComponent
extends RefCounted

var policy: ECSEnums.MaterializationPolicy = ECSEnums.MaterializationPolicy.PRESERVE_ENTITY
var item_class: StringName = &""
var manifest_id: int = -1


func can_ledgerize() -> bool:
	return policy == ECSEnums.MaterializationPolicy.LEDGERIZE
