## Marks a solid that is in free motion: dropped, thrown, scattered, or ejected by a backpack
## rupture. Uses the SAME integrator and grid collision as creatures, plus sleep-on-rest.
## There is no Godot rigid-body physics anywhere.
class_name LooseItemComponent
extends RefCounted

const REST_SPEED_MPS: float = 0.15
const REST_TICKS_REQUIRED: int = 6

var resting: bool = false
## Consecutive Micro ticks below the rest threshold. Debounces so an item does not sleep
## mid-bounce.
var still_ticks: int = 0

## Runes readable off this object (a lectern, a tablet — anything tagged `Inscribed`). The route
## into rune knowledge that play never had: ten of seventeen runes were reachable only from
## tests, because the DAG placed "ruined libraries" and nothing made them readable (gap G-3).
var inscribed_runes: Array[StringName] = []


## Returns true when the item has come to rest and should leave the active mover set.
func update_rest(speed_mps: float) -> bool:
	if speed_mps > REST_SPEED_MPS:
		still_ticks = 0
		resting = false
		return false
	still_ticks += 1
	if still_ticks >= REST_TICKS_REQUIRED:
		resting = true
	return resting
