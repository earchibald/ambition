## The ONE shared transient primitive: noise events, alert auras, bard morale auras, and
## Sprint 4 magic effects all use this (entity_behavior section 6).
##
## TTL cleanup is mandatory. An ephemeral that never expires is a leak with a radius.
class_name EphemeralComponent
extends RefCounted

var time_to_live: float = 1.0
var source_entity: int = EH.INVALID
## Expanding radius in metres. 0 means a point event.
var radius_m: float = 0.0
var expansion_mps: float = 0.0
## Tags applied to entities the aura overlaps, via the SpatialHash.
var applies_tags: Array[StringName] = []
var payload: Dictionary = {}


func is_expired() -> bool:
	return time_to_live <= 0.0


func advance(delta: float) -> void:
	time_to_live -= delta
	radius_m += expansion_mps * delta
