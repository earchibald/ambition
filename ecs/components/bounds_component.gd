## Axis-aligned half-extents in METRES (ADR-18).
##
## Collision cannot be written without this: the spec said "sweep the entity's AABB" while no
## component carried an AABB. Any entity that collides or is pickable must have one.
class_name BoundsComponent
extends RefCounted

## Humanoid default. Rat is Vector3(0.125, 0.125, 0.25).
var half_extents: Vector3 = Vector3(0.3, 0.9, 0.3)


func _init(extents: Vector3 = Vector3(0.3, 0.9, 0.3)) -> void:
	half_extents = extents


func height() -> float:
	return half_extents.y * 2.0


## Largest horizontal extent, used to size spatial-hash cell footprints.
func max_horizontal_extent() -> float:
	return maxf(half_extents.x, half_extents.z)
