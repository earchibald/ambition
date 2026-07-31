## Diegetic knowledge. Gates what the Tactical Lens will reveal.
class_name MindComponent
extends RefCounted

var known_runes: Array[StringName] = []
## Registry section 2: a Dictionary, never a bare scalar. The Spell Compiler gates on the
## Rune_Stability key specifically.
var insight: Dictionary = {}
var faction_reputations: Dictionary = {}
var language_fluency: Dictionary = {}


func insight_in(topic: StringName) -> int:
	return int(insight.get(topic, 0))


## Run 1 seeds a "Field Primer" so a new player is not blind: the Lens gates DETAIL, never
## PRESENCE (ui_ux section 2).
func seed_field_primer() -> void:
	for topic in [&"Water", &"Fire", &"Cold", &"Biomass", &"Filth", &"Iron"]:
		if not insight.has(topic):
			insight[topic] = 10
