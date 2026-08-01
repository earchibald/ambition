## The rune vocabulary (magic doc §2). Spells are composed from these, never hardcoded.
##
## A spell needs three KINDS of rune to function: a Trigger (when), a Shape (how it moves), and
## at least one Catalyst (what it does to ECS tags). That rule lives in the compiler; this file
## only says what exists and what each one costs.
##
## COMPLEXITY IS THE ONLY BALANCE LEVER HERE and it is deliberately small-integer. The compiler
## gates total complexity against `MindComponent.insight[&"Rune_Stability"] * 1.5`, so with the
## bootstrap value of 10 a new player has a budget of 15 — enough for the fireball and the trap
## from the magic doc, not enough for either plus a second shape.
##
## Parameters here are REQUESTS. The compiler clamps every spatial value against the geometric
## caps in `WorldConstants`, because "max projectile speed" and "max aura radius" are anti-crash
## rules rather than balance ones: an uncapped radius is a CPU-wiping map nuke, and an uncapped
## speed is an entity that leaves the chunk between two collision sweeps.
class_name RuneLibrary
extends RefCounted

const KIND_TRIGGER: StringName = &"TRIGGER"
const KIND_SHAPE: StringName = &"SHAPE"
const KIND_CATALYST: StringName = &"CATALYST"

const SHAPE_SELF: StringName = &"Self"
const SHAPE_PROJECTILE: StringName = &"Projectile"
const SHAPE_AURA: StringName = &"Aura"
const SHAPE_CONE: StringName = &"Cone"

const TRIGGER_ON_CAST: StringName = &"On_Cast"
const TRIGGER_ON_IMPACT: StringName = &"On_Impact"
const TRIGGER_ON_TIMER: StringName = &"On_Timer"
const TRIGGER_ON_PROXIMITY: StringName = &"On_Proximity"

## MOST SPECIFIC WINS when a spell carries more than one trigger, which the magic doc's own
## standard fireball does — `On_Cast + Projectile(High) + On_Impact + Add_Temperature`.
##
## The alternative, last-wins, makes the behaviour depend on the order the player happened to
## press the number keys in. Two identical spells would then do different things, which is
## indefensible in a system whose entire premise is that the player composes the logic.
##
## Read the ordering as "how late does this fire": proximity waits for someone to walk into it,
## a timer waits for a clock, an impact waits for contact, and On_Cast does not wait at all.
const TRIGGER_PRECEDENCE: Array[StringName] = [
	TRIGGER_ON_PROXIMITY,
	TRIGGER_ON_TIMER,
	TRIGGER_ON_IMPACT,
	TRIGGER_ON_CAST,
]

## Every rune the game knows about. `params` are the rune's requested values; the compiler owns
## whether they survive contact with the caps.
const RUNES: Dictionary = {
	# --- Triggers ---
	&"On_Cast": {"kind": KIND_TRIGGER, "complexity": 1, "params": {}},
	&"On_Impact": {"kind": KIND_TRIGGER, "complexity": 1, "params": {}},
	&"On_Timer": {"kind": KIND_TRIGGER, "complexity": 2, "params": {"delay_s": 3.0}},
	&"On_Proximity": {"kind": KIND_TRIGGER, "complexity": 3, "params": {}},

	# --- Shapes ---
	&"Self": {
		"kind": KIND_SHAPE,
		"complexity": 1,
		"params": {"shape": SHAPE_SELF, "radius_m": 1.0, "speed_mps": 0.0, "ttl_s": 1.0},
	},
	&"Projectile": {
		"kind": KIND_SHAPE,
		"complexity": 2,
		"params": {"shape": SHAPE_PROJECTILE, "radius_m": 1.5, "speed_mps": 18.0, "ttl_s": 3.0},
	},
	&"Heavy_Projectile": {
		"kind": KIND_SHAPE,
		"complexity": 3,
		# Deliberately authored ABOVE the speed cap. A rune that cannot be over-specified would
		# make the geometric clamp untestable through the real content, which is exactly how a cap
		# ends up written, tested against a synthetic value, and wrong in the shipped table.
		"params": {"shape": SHAPE_PROJECTILE, "radius_m": 2.5, "speed_mps": 60.0, "ttl_s": 4.0},
	},
	&"Aura": {
		"kind": KIND_SHAPE,
		"complexity": 3,
		"params": {
			"shape": SHAPE_AURA,
			"radius_m": 4.0,
			"speed_mps": 0.0,
			"ttl_s": 4.0,
			"expansion_mps": 2.0,
		},
	},
	&"Great_Aura": {
		"kind": KIND_SHAPE,
		"complexity": 5,
		# Also over the cap on purpose, for the same reason as Heavy_Projectile.
		"params": {
			"shape": SHAPE_AURA,
			"radius_m": 40.0,
			"speed_mps": 0.0,
			"ttl_s": 9.0,
			"expansion_mps": 4.0,
		},
	},
	&"Cone": {
		"kind": KIND_SHAPE,
		"complexity": 3,
		# The half-angle of the wedge. A cone that ignored it would be a sphere with a
		# misleading name, which is what it was until the angle was actually read.
		"params": {
			"shape": SHAPE_CONE,
			"radius_m": 6.0,
			"speed_mps": 0.0,
			"ttl_s": 1.0,
			"cone_angle_deg": 35.0,
		},
	},

	# --- Catalysts ---
	&"Add_Temperature": {
		"kind": KIND_CATALYST,
		"complexity": 2,
		# JOULES, not degrees (review H2). "Add_Temperature(500)" as a flat per-entity temperature
		# heats a coin and a barrel by the same amount, which is not a heat model at all.
		"params": {"energy_j": 900000.0},
	},
	&"Chill": {
		"kind": KIND_CATALYST,
		"complexity": 2,
		"params": {"energy_j": -400000.0},
	},
	&"Apply_Burning": {
		"kind": KIND_CATALYST,
		"complexity": 2,
		"params": {"apply_tag": &"Burning"},
	},
	&"Apply_Water": {
		"kind": KIND_CATALYST,
		"complexity": 1,
		"params": {"apply_tag": &"Water"},
	},
	&"Apply_Filth": {
		"kind": KIND_CATALYST,
		"complexity": 3,
		"params": {"apply_tag": &"Filth"},
	},
	&"Apply_Spores": {
		"kind": KIND_CATALYST,
		"complexity": 3,
		"params": {"apply_tag": &"Spores"},
	},
	&"Remove_Wet": {
		"kind": KIND_CATALYST,
		"complexity": 1,
		"params": {"remove_tag": &"Wet"},
	},
	&"Absorb_Heat": {
		"kind": KIND_CATALYST,
		"complexity": 2,
		# Absorb consumes a QUANTIFIED environmental resource (review D8), so it names both what
		# it takes and how much it needs. A caster that finds less than this Fizzles.
		"params": {"absorb": &"Heat", "absorb_j": 200000.0},
	},
}

## What a new adventurer already knows. Deliberately small: the magic doc's premise is that
## knowledge is excavated, so a starter grimoire that contained everything would remove the
## reason the DAG generates ruined libraries at all.
const STARTING_RUNES: Array[StringName] = [
	&"On_Cast",
	&"On_Impact",
	&"Projectile",
	&"Aura",
	&"Add_Temperature",
	&"Apply_Burning",
	&"Apply_Water",
]


static func exists(rune_id: StringName) -> bool:
	return RUNES.has(rune_id)


static func kind_of(rune_id: StringName) -> StringName:
	if not RUNES.has(rune_id):
		return &""
	return RUNES[rune_id]["kind"]


static func complexity_of(rune_id: StringName) -> int:
	if not RUNES.has(rune_id):
		return 0
	return int(RUNES[rune_id]["complexity"])


static func params_of(rune_id: StringName) -> Dictionary:
	if not RUNES.has(rune_id):
		return {}
	return RUNES[rune_id]["params"]
