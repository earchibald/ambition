## Turns a reasoner's answer into faction behaviour, refusing anything it cannot verify.
##
## THE VALIDATION GATE (Sprint 3 Step 3). Everything arriving here is UNTRUSTED — not because a
## model is malicious, but because it is answering a question about a world that moved while it
## thought, and because a language model will confidently name a faction that does not exist.
##
## The heuristic provider is held to the identical gate. A validator that only runs on the remote
## path is a validator that has never been tested, and the fallbacks it defines are the ones the
## whole no-endpoint mode depends on.
##
## FALLBACK MATRIX (ADR-5, llm doc §6), each with a reason it is the safe answer:
##   * dead leader        -> discard entirely. There is nobody left to obey the order.
##   * malformed JSON     -> FORTIFY. Doing something defensive is always survivable.
##   * unknown objective  -> FORTIFY.
##   * hallucinated target-> FORTIFY, target stripped. Never resolve a raid against an id nobody
##                           can name; that is how a faction marches on empty ground.
##   * timeout            -> keep the CURRENT objective and requeue. Changing plans because a
##                           network call was slow is worse than continuing.
class_name LLMResolutionSystem
extends RefCounted

var accepted: int = 0
var rejected_dead: int = 0
var rejected_malformed: int = 0
var hallucinated_targets: int = 0
var objectives_applied: int = 0


## Applies one answer. Returns the objective actually adopted, which is not always the one asked
## for — that difference IS the gate.
func resolve(
	faction_handle: int, response: Dictionary, generator: DAGGenerator
) -> ECSEnums.Objective:
	# 1. Is there still anyone to give the order to?
	if not ECSManager.is_alive(faction_handle):
		rejected_dead += 1
		return ECSEnums.Objective.IDLE
	var row: int = ECSManager.resolve(faction_handle)
	var core: FactionCoreComponent = ECSManager.faction_cores.get(row)
	if core == null:
		rejected_dead += 1
		return ECSEnums.Objective.IDLE

	# 2. Did we get anything usable at all? An empty Dictionary is how every provider reports
	#    failure, so timeout, refusal and unparseable JSON all land here.
	if response.is_empty():
		rejected_malformed += 1
		return _apply(core, ECSEnums.Objective.FORTIFY, ECSEnums.Emotion.CALM, -1, "Hold fast.")

	var objective: int = _parse_objective(String(response.get("objective", "")))
	if objective < 0:
		rejected_malformed += 1
		objective = ECSEnums.Objective.FORTIFY

	# 3. Anti-hallucination. A target must be a faction that EXISTS AND IS ALIVE right now — not
	#    when the prompt was written.
	var target: int = int(response.get("target_faction_id", -1))
	if target != -1 and not _is_valid_target(target, generator):
		hallucinated_targets += 1
		target = -1
		objective = ECSEnums.Objective.FORTIFY

	# 4. A raid with no target is not a raid. Falling through with RAID_FACTION and target -1
	#    sends the planner marching at nothing.
	if objective == ECSEnums.Objective.RAID_FACTION and target == -1:
		objective = ECSEnums.Objective.FORTIFY

	accepted += 1
	return _apply(
		core,
		objective as ECSEnums.Objective,
		_parse_emotion(String(response.get("emotion_state", ""))),
		target,
		String(response.get("public_declaration", ""))
	)


## Timeout keeps the CURRENT plan. Abandoning a siege because the network was slow is a worse
## outcome than continuing it, and the leader is requeued to try again next hour.
func on_timeout(faction_handle: int) -> ECSEnums.Objective:
	var row: int = ECSManager.resolve(faction_handle)
	var core: FactionCoreComponent = ECSManager.faction_cores.get(row)
	return ECSEnums.Objective.IDLE if core == null else core.current_objective


## The player counts as a valid target (Faction 0, ADR-14) even though they have no DAG node.
func _is_valid_target(target: int, generator: DAGGenerator) -> bool:
	if target == WorldConstants.PLAYER_FACTION_ID:
		return ECSManager.is_alive(ECSManager.player_handle())
	if generator == null:
		return false
	var node: DAGNode = generator.node_by_id(target)
	return node != null and node.is_active()


func _apply(
	core: FactionCoreComponent,
	objective: ECSEnums.Objective,
	emotion: ECSEnums.Emotion,
	target: int,
	declaration: String
) -> ECSEnums.Objective:
	core.current_objective = objective
	core.current_emotion = emotion
	core.last_declaration = declaration
	core.objective_target = target
	objectives_applied += 1
	ECSEvents.faction_decided.emit(core.faction_id, ECSEnums.Objective.keys()[objective], declaration)
	return objective


## Enum names are matched exactly. A loose match would quietly accept "raid" or "Raid_Faction"
## from a model that was told the exact list, and hide a prompt that is not being followed.
func _parse_objective(name: String) -> int:
	var index: int = ECSEnums.Objective.keys().find(name)
	return index


func _parse_emotion(name: String) -> ECSEnums.Emotion:
	var index: int = ECSEnums.Emotion.keys().find(name)
	return ECSEnums.Emotion.CALM if index < 0 else index as ECSEnums.Emotion


func counters() -> Dictionary:
	return {
		"llm_accepted": accepted,
		"llm_rejected_dead": rejected_dead,
		"llm_rejected_malformed": rejected_malformed,
		"llm_hallucinated_targets": hallucinated_targets,
		"llm_objectives_applied": objectives_applied,
	}
