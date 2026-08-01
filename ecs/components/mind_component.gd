## Diegetic knowledge. Gates what the Tactical Lens will reveal.
class_name MindComponent
extends RefCounted

var known_runes: Array[StringName] = []

## Action_ID -> CompiledSpell. The bound spells this mind can cast (magic doc §5). Lives on the
## MIND rather than in a system dictionary because it is knowledge: it survives a LoD demotion,
## it is what the Lineage Journal carries across a death, and a system-side map keyed by row
## would hand a recycled row somebody else's grimoire.
var grimoire: Dictionary = {}

## The Action_ID the cast key fires. Set by the last successful bind, so "press Q to cast what
## you just bound" needs no state in the viewer at all.
var active_spell: StringName = &""
## Registry section 2: a Dictionary, never a bare scalar. The Spell Compiler gates on the
## Rune_Stability key specifically.
var insight: Dictionary = {}
var faction_reputations: Dictionary = {}
var language_fluency: Dictionary = {}


func insight_in(topic: StringName) -> int:
	return int(insight.get(topic, 0))


## Run 1 seeds a "Field Primer" so a new player is not blind: the Lens gates DETAIL, never
## PRESENCE (ui_ux section 2).
##
## `Rune_Stability` is seeded here too, and it is not cosmetic. The Spell Compiler gates total
## complexity on `Rune_Stability * 1.5`, so a player who starts at 0 has a budget of 0 and CANNOT
## COMPILE ANY SPELL AT ALL — the entire magic layer would be present, tested, and unreachable.
## A spec audit flagged that the key had no bootstrap value anywhere and left it to this sprint;
## 10 gives a budget of 15, which is the fireball plus change and not two shapes.
func seed_field_primer() -> void:
	for topic in [&"Water", &"Fire", &"Cold", &"Biomass", &"Filth", &"Iron"]:
		if not insight.has(topic):
			insight[topic] = 10
	if not insight.has(&"Rune_Stability"):
		insight[&"Rune_Stability"] = 10
	for rune_id in RuneLibrary.STARTING_RUNES:
		if not known_runes.has(rune_id):
			known_runes.append(rune_id)
