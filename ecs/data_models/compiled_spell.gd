## A validated spell, ready to cast (Sprint 4 scaffolding §2).
##
## Produced only by `SpellCompilerSystem.compile`, which is the single place the complexity gate
## and the geometric caps are applied. Nothing else may construct one with arbitrary numbers in
## it: the caps are anti-crash rules, and a second construction path is a second place to forget
## them.
class_name CompiledSpell
extends RefCounted

var spell_id: StringName = &""
var runes: Array[StringName] = []
var complexity: int = 0
var strain_cost: float = 0.0

var trigger: StringName = &""
var shape: StringName = &""
var radius_m: float = 0.0
var speed_mps: float = 0.0
var ttl_s: float = 1.0
var expansion_mps: float = 0.0
## How long an On_Timer spell waits before it goes off.
var delay_s: float = 0.0
## Half-angle of a Cone, in degrees. 0 means the effect is spherical.
var cone_angle_deg: float = 0.0

## What the spell does on contact: `{apply: Array[StringName], remove: Array[StringName],
## energy_j: float}`. Flattened from the catalyst runes at compile time so the cast path does no
## rune lookups at all.
var applies_tags: Array[StringName] = []
var removes_tags: Array[StringName] = []
var energy_j: float = 0.0

## Absorb_Tag: what the spell must find in the world, and how much of it (review D8).
var absorbs: StringName = &""
var absorb_j: float = 0.0

## Which geometric caps were hit. Carried rather than discarded so the Grimoire can say
## "WARN: Radius > 15m" instead of silently handing back a different spell than was authored.
var caps_applied: Array[StringName] = []


func was_capped() -> bool:
	return not caps_applied.is_empty()


## One line for the Grimoire and the event feed.
func describe() -> String:
	var effect: String = ""
	if not applies_tags.is_empty():
		effect = " +%s" % ", ".join(applies_tags)
	if not is_zero_approx(energy_j):
		effect += " %+.0fkJ" % (energy_j / 1000.0)
	return "%s [%s/%s] r%.1fm v%.0f ttl%.1fs strain %.1f%s" % [
		spell_id, trigger, shape, radius_m, speed_mps, ttl_s, strain_cost, effect
	]
