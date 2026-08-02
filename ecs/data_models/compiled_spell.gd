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

## Branded at FORCED compile time (grimoire spec §2C) and never cleared: an Unstable spell rolls
## the d100 mishap table on every cast for as long as it exists. Permanence is the spec's word
## ("permanently brands the spell"), and it is what makes overclocking a debt rather than a fee.
var unstable: bool = false


## A per-cast copy, for mishaps that mutate geometry. An Over-Pressure roll doubles the RADIUS
## OF THIS CAST — mutating the grimoire's stored spell would ratchet it bigger on every mishap.
func clone() -> CompiledSpell:
	var copy := CompiledSpell.new()
	copy.spell_id = spell_id
	copy.runes = runes.duplicate()
	copy.complexity = complexity
	copy.strain_cost = strain_cost
	copy.trigger = trigger
	copy.shape = shape
	copy.radius_m = radius_m
	copy.speed_mps = speed_mps
	copy.ttl_s = ttl_s
	copy.expansion_mps = expansion_mps
	copy.delay_s = delay_s
	copy.cone_angle_deg = cone_angle_deg
	copy.applies_tags = applies_tags.duplicate()
	copy.removes_tags = removes_tags.duplicate()
	copy.energy_j = energy_j
	copy.absorbs = absorbs
	copy.absorb_j = absorb_j
	copy.caps_applied = caps_applied.duplicate()
	copy.unstable = unstable
	return copy


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
