## The Grimoire's back end (Sprint 4 §2). Turns an array of Rune ids into a validated
## `CompiledSpell`, or refuses with a reason.
##
## TWO CAPS, AND THEY FAIL DIFFERENTLY. That difference is the design, not an accident:
##
##   * THE COMPLEXITY CAP REFUSES. Total complexity above
##     `insight[&"Rune_Stability"] * RUNE_STABILITY_MULTIPLIER` means the caster cannot hold the
##     spell in their head, so there is nothing to hand back. It is a knowledge gate and it must
##     produce a refusal the player can act on — learn more, or use fewer runes.
##
##   * THE GEOMETRIC CAPS CLAMP. A 400 m radius is not a knowledge problem, it is a CPU-wiping
##     map nuke, and refusing it would let a player author a spell they can never cast and never
##     find out why. The scaffolding is explicit — "Force override" — so the value is overwritten,
##     the fact is RECORDED in `caps_applied`, and the Grimoire shows "radius capped at 15 m".
##     Silently clamping without recording is the worse half of both options.
##
## FAILURE RETURNS A REASON, NEVER A BARE NULL. The scaffolding's sketch printed to stdout and
## returned null, which from the UI's seat is indistinguishable from a crash. `compile` returns a
## result dictionary, and `last_failure` names which rule refused.
##
## THIS SYSTEM IS PURE. It reads a MindComponent and returns a value; it mutates nothing, spawns
## nothing, and never touches the live world. The Dry Run hologram in the grimoire spec needs
## exactly that — a validation pass that costs no Strain and consumes no materials — so the dry
## run and the real compile are the same code rather than two implementations that disagree.
class_name SpellCompilerSystem
extends RefCounted

const REASON_NONE: StringName = &""
const REASON_NO_RUNES: StringName = &"no runes"
const REASON_TOO_MANY: StringName = &"too many runes"
const REASON_UNKNOWN_RUNE: StringName = &"unknown rune"
const REASON_NOT_LEARNED: StringName = &"you do not know that rune"
const REASON_NEEDS_TRIGGER: StringName = &"needs a trigger rune"
const REASON_NEEDS_SHAPE: StringName = &"needs a shape rune"
const REASON_NEEDS_CATALYST: StringName = &"needs a catalyst rune"
const REASON_TOO_COMPLEX: StringName = &"exceeds cognitive limits"

const CAP_RADIUS: StringName = &"radius"
const CAP_SPEED: StringName = &"speed"
const CAP_TTL: StringName = &"lifetime"

var compiles_attempted: int = 0
var compiles_rejected: int = 0
var caps_enforced: int = 0
var last_failure: StringName = REASON_NONE


## The complexity a caster may hold. Static and separate so the Grimoire can show the budget
## before the player has assembled anything to spend it on.
static func complexity_budget(mind: MindComponent) -> float:
	if mind == null:
		return 0.0
	return float(mind.insight_in(&"Rune_Stability")) * WorldConstants.RUNE_STABILITY_MULTIPLIER


## Returns `{ok: bool, spell: CompiledSpell, reason: StringName}`. `spell` is null when `ok` is
## false, and `reason` is empty when it is true.
func compile(rune_ids: Array, mind: MindComponent) -> Dictionary:
	compiles_attempted += 1
	var problem: StringName = _structural_problem(rune_ids, mind)
	if problem != REASON_NONE:
		return _refuse(problem)

	var spell := CompiledSpell.new()
	for rune_id in rune_ids:
		spell.runes.append(rune_id)
		spell.complexity += RuneLibrary.complexity_of(rune_id)
		_absorb_rune(spell, rune_id)

	if float(spell.complexity) > complexity_budget(mind):
		return _refuse(REASON_TOO_COMPLEX)

	_apply_geometric_caps(spell)
	spell.strain_cost = float(spell.complexity) * WorldConstants.STRAIN_PER_COMPLEXITY
	spell.spell_id = StringName("+".join(spell.runes))
	last_failure = REASON_NONE
	return {"ok": true, "spell": spell, "reason": REASON_NONE}


## Compiles AND registers, which is the only mutating entry point here.
##
## The split matters. `compile` is pure, so the Grimoire's live preview — the "Dry Run" that the
## grimoire spec says must cost zero Strain and consume no materials — can call it on every
## keystroke without touching the world. `bind` is what commits, it is reached only through an
## ActionIntent, and it is therefore the one path that writes a spell into a mind.
##
## Reports through the bus either way, because a Bind button that does nothing visible on failure
## is the same defect as a cast that resolves silently.
func bind(caster_row: int, rune_ids: Array) -> Dictionary:
	var mind: MindComponent = ECSManager.minds.get(caster_row)
	var caster: int = ECSManager.handle_of(caster_row)
	var result: Dictionary = compile(rune_ids, mind)
	if not result["ok"]:
		ECSEvents.spell_bound.emit(caster, &"", false, result["reason"])
		return result
	var spell: CompiledSpell = result["spell"]
	mind.grimoire[spell.spell_id] = spell
	mind.active_spell = spell.spell_id
	ECSEvents.spell_bound.emit(caster, spell.spell_id, true, REASON_NONE)
	return result


## Everything that can be judged without adding anything up. Split across two functions because
## `compile` was otherwise a single function with eight exits, and gdlint caps a function at six
## returns for the same reason a reader would.
func _structural_problem(rune_ids: Array, mind: MindComponent) -> StringName:
	if rune_ids.is_empty():
		return REASON_NO_RUNES
	if rune_ids.size() > WorldConstants.MAX_SPELL_RUNES:
		return REASON_TOO_MANY
	var per_rune: StringName = _rune_problem(rune_ids, mind)
	if per_rune != REASON_NONE:
		return per_rune
	return _shape_problem(rune_ids)


## Judged rune by rune: does it exist, and has the caster excavated it?
func _rune_problem(rune_ids: Array, mind: MindComponent) -> StringName:
	for rune_id in rune_ids:
		if not RuneLibrary.exists(rune_id):
			return REASON_UNKNOWN_RUNE
		# KNOWLEDGE IS DIEGETIC (magic doc §1). A rune you have not excavated is not castable
		# even if the compiler could otherwise validate it.
		if mind != null and not mind.known_runes.has(rune_id):
			return REASON_NOT_LEARNED
	return REASON_NONE


## Judged over the whole array: a spell needs one of each kind to be a spell at all.
func _shape_problem(rune_ids: Array) -> StringName:
	var kinds: Dictionary = {}
	for rune_id in rune_ids:
		kinds[RuneLibrary.kind_of(rune_id)] = true
	if not kinds.has(RuneLibrary.KIND_TRIGGER):
		return REASON_NEEDS_TRIGGER
	if not kinds.has(RuneLibrary.KIND_SHAPE):
		return REASON_NEEDS_SHAPE
	return REASON_NONE if kinds.has(RuneLibrary.KIND_CATALYST) else REASON_NEEDS_CATALYST


## Folds one rune's parameters into the spell. Catalysts accumulate — two heat runes are twice
## the energy — while shape is last-wins and TRIGGER IS BY PRECEDENCE.
##
## Trigger precedence rather than last-wins because the magic doc's own standard fireball carries
## two of them, and because last-wins would make a spell's behaviour depend on the order the
## player pressed the number keys in. See `RuneLibrary.TRIGGER_PRECEDENCE`.
func _absorb_rune(spell: CompiledSpell, rune_id: StringName) -> void:
	var kind: StringName = RuneLibrary.kind_of(rune_id)
	var params: Dictionary = RuneLibrary.params_of(rune_id)
	if kind == RuneLibrary.KIND_TRIGGER:
		if _outranks(rune_id, spell.trigger):
			spell.trigger = rune_id
			spell.delay_s = float(params.get("delay_s", 0.0))
		return
	if kind == RuneLibrary.KIND_SHAPE:
		spell.shape = params.get("shape", RuneLibrary.SHAPE_SELF)
		spell.radius_m = float(params.get("radius_m", 1.0))
		spell.speed_mps = float(params.get("speed_mps", 0.0))
		spell.ttl_s = float(params.get("ttl_s", 1.0))
		spell.expansion_mps = float(params.get("expansion_mps", 0.0))
		spell.cone_angle_deg = float(params.get("cone_angle_deg", 0.0))
		return
	spell.energy_j += float(params.get("energy_j", 0.0))
	if params.has("apply_tag"):
		spell.applies_tags.append(params["apply_tag"])
	if params.has("remove_tag"):
		spell.removes_tags.append(params["remove_tag"])
	if params.has("absorb"):
		spell.absorbs = params["absorb"]
		spell.absorb_j = float(params.get("absorb_j", 0.0))


## Whether `candidate` fires later than `held` and therefore wins. An unset trigger loses to
## everything, so the first one seen always takes.
static func _outranks(candidate: StringName, held: StringName) -> bool:
	if held == &"":
		return true
	var order: Array[StringName] = RuneLibrary.TRIGGER_PRECEDENCE
	return order.find(candidate) < order.find(held)


## THE GEOMETRIC PATCH. Overrides rather than refuses, and records what it overrode.
func _apply_geometric_caps(spell: CompiledSpell) -> void:
	if spell.radius_m > WorldConstants.MAX_SPELL_RADIUS_M:
		spell.radius_m = WorldConstants.MAX_SPELL_RADIUS_M
		spell.caps_applied.append(CAP_RADIUS)
	if spell.speed_mps > WorldConstants.MAX_SPELL_SPEED_MPS:
		spell.speed_mps = WorldConstants.MAX_SPELL_SPEED_MPS
		spell.caps_applied.append(CAP_SPEED)
	if spell.ttl_s > WorldConstants.MAX_SPELL_TTL_S:
		spell.ttl_s = WorldConstants.MAX_SPELL_TTL_S
		spell.caps_applied.append(CAP_TTL)
	# An expanding aura reaches `radius + expansion * ttl`, so capping the STARTING radius alone
	# leaves the cap trivially defeatable by any rune with an expansion rate. The final extent is
	# what matters to the SpatialHash query this eventually becomes.
	var final_extent: float = spell.radius_m + spell.expansion_mps * spell.ttl_s
	if final_extent > WorldConstants.MAX_SPELL_RADIUS_M:
		spell.expansion_mps = maxf(
			0.0, (WorldConstants.MAX_SPELL_RADIUS_M - spell.radius_m) / maxf(spell.ttl_s, 0.001)
		)
		if not spell.caps_applied.has(CAP_RADIUS):
			spell.caps_applied.append(CAP_RADIUS)
	caps_enforced += spell.caps_applied.size()


func _refuse(reason: StringName) -> Dictionary:
	compiles_rejected += 1
	last_failure = reason
	return {"ok": false, "spell": null, "reason": reason}


func counters() -> Dictionary:
	return {
		"spells_compiled": compiles_attempted - compiles_rejected,
		"spells_rejected": compiles_rejected,
		"spell_caps_enforced": caps_enforced,
	}
