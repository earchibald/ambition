## Marker attached ONLY to Entity 0 while alive (registry section 2).
##
## Detached on death, before the player handle is retired and index 0 is reused.
class_name PlayerInputComponent
extends RefCounted

## Latest movement intent in world space, written by the input bridge each frame.
var move_vector: Vector3 = Vector3.ZERO
var wants_attack: bool = false
var wants_interact: bool = false
