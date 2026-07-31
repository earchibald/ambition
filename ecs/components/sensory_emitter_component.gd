## What an entity emits to be perceived by.
class_name SensoryEmitterComponent
extends RefCounted

var noise_radius_m: float = 0.0
var visibility_modifier: float = 1.0
var scent_tags: Array[StringName] = []


## Converts a noise radius to a source level in decibels for the attenuation model
## (Sprint 1 section 11).
func source_db() -> float:
	return 10.0 + 20.0 * (log(maxf(noise_radius_m, 1.0)) / log(10.0))
