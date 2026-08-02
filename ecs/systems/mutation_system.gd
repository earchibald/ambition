## Biological mutation and the ecology loop (Sprint 4 §4). The environment is the skill tree.
##
## Runs on the SIMULATION tick, not the Micro tick. Exposure is an hours-scale process and
## checking it 60 times a second would be 30x the work for an identical outcome.
##
## EVERY MUTATION DOES SOMETHING MEASURABLE. This project's recurring defect is a doc comment
## describing behaviour the code does not have — four instances in Sprint 3 alone — and a
## mutation table is the perfect shape for it: a list of evocative tag names that read as a
## feature and change no number anywhere. So `MUTATIONS` carries the stat deltas, `_apply` is the
## only thing that writes them, and every entry is asserted in `tests/test_mutation.gd`. If you
## add a mutation without a delta, the test that counts them fails.
##
## MUTATION IS NOT A SECRET (review D3). Gaining one appends a witnessable act, which
## `PerceptionSystem` resolves against line of sight and `ReputationSystem` turns into a
## reputation delta whose SIGN depends on the witness faction's own culture. A Spore-Lord's
## people are pleased; the Surface Village is not. It then travels by gossip like any other news,
## so the village learns about it when someone tells them and not the instant it happens.
class_name MutationSystem
extends RefCounted

## Hazard tag -> the exposure track it feeds and how fast. Rates are per SECOND of exposure, so
## reaching the threshold of 100 takes 50 s in spores and 33 s in something actively toxic.
## Tuned for a play session rather than derived: the roadmap's success state is "wades through
## toxic sludge", which has to be reachable inside a play-test, not inside a campaign.
const HAZARDS: Dictionary = {
	&"Spores": {"track": &"FUNGAL", "per_second": 2.0},
	&"Filth": {"track": &"FILTH", "per_second": 1.4},
	&"Toxic": {"track": &"TOXIC", "per_second": 3.0},
	&"Radiation": {"track": &"ARCANE", "per_second": 3.5},
}

## Track -> the mutations it can produce, each with the stat changes it actually makes.
##
## Every one is a TRADE. "A player might gain Night_Vision but permanently lose Charisma" is the
## design premise (magic doc §4), and a mutation that is purely an upgrade turns a hazard into a
## farm.
const MUTATIONS: Dictionary = {
	&"FUNGAL": [
		{
			"tag": &"Fungal_Lungs",
			"grants": &"Resist_Spores",
			"max_stamina": -20.0,
			"max_health": 0.0,
			"armor": 0.0,
			"toughness": 0.0,
			"sight": 0.0,
		},
	],
	&"FILTH": [
		{
			"tag": &"Chitin_Plates",
			"grants": &"Resist_Filth",
			"max_stamina": 0.0,
			"max_health": 0.0,
			"armor": 8.0,
			"toughness": 0.4,
			"sight": -3.0,
		},
	],
	&"TOXIC": [
		{
			"tag": &"Acid_Blood",
			"grants": &"Resist_Toxic",
			"max_stamina": 0.0,
			"max_health": -10.0,
			"armor": 0.0,
			"toughness": 0.0,
			"sight": 0.0,
		},
	],
	&"ARCANE": [
		{
			"tag": &"Night_Vision",
			"grants": &"Resist_Radiation",
			"max_stamina": 0.0,
			"max_health": 0.0,
			"armor": -2.0,
			"toughness": 0.0,
			"sight": 8.0,
		},
	],
}

## CUMULATIVE for the run, not per tick. A mutation is a rare, permanent event and a counter that
## resets every Simulation tick reads 0 for all but one frame in a thousand — which in the debug
## overlay is indistinguishable from a system that never fires. The reaction counters next to
## these are deliberately per-tick for the opposite reason: they measure a RATE.
var exposures_accrued: int = 0
var mutations_granted: int = 0

## Mutations that happened this tick and might have been seen. Drained by GameLoopManager and
## handed to PerceptionSystem, exactly like `ActionResolutionSystem.witnessed_actions` — the
## system that causes a thing never decides who saw it.
var witnessed_mutations: Array[Dictionary] = []


## `delta_s` is the wall of SIMULATED seconds since the last Simulation tick, passed in rather
## than read (ADR-20 forbids `ecs/` reading a clock).
func run(delta_s: float, chunk: ChunkData) -> void:
	for row in ECSManager.query(ComponentMask.BODY | ComponentMask.POSITION):
		var body: BodyComponent = ECSManager.bodies.get(row)
		if body == null or not body.is_alive():
			continue
		_accrue(row, body, delta_s, chunk)


## Exposure from two sources, and both are needed.
##   * The entity's OWN tags — how you get exposed by wading through sludge or standing in a
##     spore cloud, since both of those arrive as tags via the aura path.
##   * The CHUNK's hazard tags — a whole zone that is irradiated, which no per-entity tag models.
func _accrue(row: int, body: BodyComponent, delta_s: float, chunk: ChunkData) -> void:
	var chemistry: ChemistryComponent = ECSManager.chemistries.get(row)
	for hazard in HAZARDS:
		var present: bool = chemistry != null and chemistry.has_tag(hazard)
		if not present and chunk != null and chunk.hazard_tags.has(hazard):
			present = true
		if not present:
			continue
		var track: StringName = HAZARDS[hazard]["track"]
		if _is_protected(row, body, chemistry, track):
			continue
		var gained: float = float(HAZARDS[hazard]["per_second"]) * delta_s
		body.exposure[track] = float(body.exposure.get(track, 0.0)) + gained
		exposures_accrued += 1
		if float(body.exposure[track]) >= WorldConstants.EXPOSURE_MUTATION_THRESHOLD:
			# RESET FIRST, unconditionally. The scaffolding resets only after a successful roll,
			# so an entity already at MAX_MUTATIONS sits pinned at the threshold and re-enters
			# this branch on every single tick forever.
			body.exposure[track] = 0.0
			_mutate(row, body, track)


## Protective gear and previous mutations both count. `Resist_X` on the chemistry component is
## what a filter mask grants; the same tag in `mutations` is what a previous mutation grants —
## so Fungal_Lungs really does stop the next fungal mutation, rather than being a name that
## sounds like it should.
func _is_protected(
	_row: int, body: BodyComponent, chemistry: ChemistryComponent, track: StringName
) -> bool:
	for candidate in MUTATIONS.get(track, []):
		var grant: StringName = candidate["grants"]
		if body.mutations.has(grant):
			return true
		if chemistry != null and chemistry.has_tag(grant):
			return true
	return false


## Rolls on the table for one track. Uses the `mutation` RNG stream (ADR-8), never `randf()`.
func _mutate(row: int, body: BodyComponent, track: StringName) -> void:
	if body.mutations.size() >= WorldConstants.MAX_MUTATIONS:
		return
	var options: Array = MUTATIONS.get(track, [])
	if options.is_empty():
		return
	var pick: Dictionary = options[
		RNGService.randi_range_in(&"mutation", 0, options.size() - 1)
	]
	if body.mutations.has(pick["tag"]):
		return
	_apply(row, body, pick)
	mutations_granted += 1
	# WITNESSABLE, not announced. Who learns about it is perception's problem and gossip's.
	witnessed_mutations.append({
		"subject": row,
		"action": StringName("MUTATION_%s" % track),
		"location": ECSManager.position_of(row),
	})
	ECSEvents.entity_mutated.emit(ECSManager.handle_of(row), pick["tag"])


## The only place a mutation changes a number. Health and stamina are clamped to their new
## maxima, or a mutation that lowers max_health leaves a body reporting 100/90.
func _apply(row: int, body: BodyComponent, mutation: Dictionary) -> void:
	body.mutations.append(mutation["tag"])
	body.mutations.append(mutation["grants"])
	body.max_stamina = maxf(10.0, body.max_stamina + float(mutation["max_stamina"]))
	body.max_health = maxf(10.0, body.max_health + float(mutation["max_health"]))
	body.stamina = minf(body.stamina, body.max_stamina)
	body.health = minf(body.health, body.max_health)
	body.armor_rating = maxf(0.0, body.armor_rating + float(mutation["armor"]))
	body.structural_toughness = maxf(
		0.05, body.structural_toughness + float(mutation["toughness"])
	)

	var sight: float = float(mutation["sight"])
	if is_zero_approx(sight):
		return
	var perception: PerceptionComponent = ECSManager.perceptions.get(row)
	if perception != null:
		perception.sight_range_m = maxf(1.0, perception.sight_range_m + sight)


## Drains the tick's mutations. Mirrors `take_witness_events` so the caller cannot read the same
## batch twice.
func take_witnessed_mutations() -> Array[Dictionary]:
	var out: Array[Dictionary] = witnessed_mutations.duplicate()
	witnessed_mutations.clear()
	return out


func counters() -> Dictionary:
	return {"exposures": exposures_accrued, "mutations": mutations_granted}
