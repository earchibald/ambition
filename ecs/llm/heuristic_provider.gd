## The DEFAULT reasoner. Decides a faction's objective from its own state, with no network.
##
## Per the amended ADR-5 this is a shipped provider, not a test stub. It is what runs when no
## endpoint is configured, which is the normal case: contributors do not need an API key, CI
## exercises this path on every commit, and a player with no internet gets a complete game.
##
## It answers the same question an LLM would and returns the same schema, so
## `LLMResolutionSystem` cannot tell them apart. What it does NOT attempt is the thing the LLM is
## actually good at — voice. Its `public_declaration` is a plain sentence, not a performance.
##
## The rules below are deliberately legible. An emergent-looking decision nobody can explain is
## indistinguishable from a bug, and the debugging spec requires "why did this faction do that?"
## to have an answer.
class_name HeuristicProvider
extends LLMProvider

## Below this many days of food, feeding people outranks everything else.
const STARVATION_DAYS: float = 3.0
const FOOD_PER_PERSON_PER_DAY: float = 1.5

## A faction this much stronger than a neighbour it dislikes will consider raiding.
const RAID_STRENGTH_RATIO: float = 1.6

## Relationship score below which a neighbour counts as an enemy.
const HOSTILE_SCORE: float = -25.0

var decisions: int = 0


func describe() -> String:
	return "heuristic (no endpoint configured)"


## Synchronous work, asynchronous shape. Calling back immediately is honest — there is no
## latency to simulate — but the CALLER must still be written for a late answer, because the
## remote provider genuinely is late.
func request(prompt: String, on_done: Callable) -> void:
	decisions += 1
	on_done.call(decide(_context_from(prompt)))


## THE decision. Ordered by what would actually kill the faction first.
func decide(context: Dictionary) -> Dictionary:
	var population: int = int(context.get("population", 0))
	var food: int = int(context.get("food", 0))
	var strength: float = float(context.get("strength", 0.0))
	var targets: Array = context.get("valid_targets", [])

	# 1. Starving beats everything. A faction that raids while its people die is not being
	#    interesting, it is being wrong.
	var days_of_food: float = (
		999.0
		if population <= 0
		else float(food) / (float(population) * FOOD_PER_PERSON_PER_DAY)
	)
	if days_of_food < STARVATION_DAYS:
		return _answer(
			ECSEnums.Objective.GATHER_RESOURCES,
			ECSEnums.Emotion.DESPERATE,
			-1,
			"We have %d days of food left. Everyone to the fields." % int(days_of_food)
		)

	# 2. A recent attack outranks opportunity. Being hit and going mining reads as a bug.
	if bool(context.get("recently_attacked", false)):
		return _answer(
			ECSEnums.Objective.FORTIFY,
			ECSEnums.Emotion.FEARFUL,
			-1,
			"We were attacked. Bar the doors and post guards."
		)

	# 3. Opportunity: a disliked neighbour we clearly outmatch.
	var prey: Dictionary = _weakest_hated(targets, strength)
	if not prey.is_empty():
		return _answer(
			ECSEnums.Objective.RAID_FACTION,
			ECSEnums.Emotion.AGGRESSIVE,
			int(prey["faction_id"]),
			"%s is weak and owes us. We march." % prey.get("name", "They")
		)

	# 4. Otherwise, get richer.
	return _answer(
		ECSEnums.Objective.GATHER_RESOURCES,
		ECSEnums.Emotion.CALM,
		-1,
		"Quiet season. Work the stone and the fields."
	)


func _weakest_hated(targets: Array, strength: float) -> Dictionary:
	var best: Dictionary = {}
	for target in targets:
		if float(target.get("score", 0.0)) > HOSTILE_SCORE:
			continue
		var their_strength: float = maxf(float(target.get("strength", 0.0)), 0.001)
		if strength / their_strength < RAID_STRENGTH_RATIO:
			continue
		if best.is_empty() or their_strength < float(best.get("strength", 0.0)):
			best = target
	return best


func _answer(
	objective: ECSEnums.Objective, emotion: ECSEnums.Emotion, target: int, line: String
) -> Dictionary:
	# Exactly the schema the scaffolding specifies for the LLM, so the resolution system and its
	# validation gate cannot tell the two providers apart.
	return {
		"reason_summary": line,
		"objective": ECSEnums.Objective.keys()[objective],
		"target_faction_id": target,
		"emotion_state": ECSEnums.Emotion.keys()[emotion],
		"public_declaration": line,
	}


## The prompt is a STRING because that is what a remote provider needs. Rather than maintain two
## parallel context paths, the heuristic reads the machine-readable block the builder appends —
## one context builder, one salience filter, one place to be wrong.
func _context_from(prompt: String) -> Dictionary:
	var marker: int = prompt.find(PromptBuilder.CONTEXT_MARKER)
	if marker < 0:
		return {}
	var payload: String = prompt.substr(marker + PromptBuilder.CONTEXT_MARKER.length())
	var parsed: Variant = JSON.parse_string(payload.strip_edges())
	return {} if typeof(parsed) != TYPE_DICTIONARY else parsed
