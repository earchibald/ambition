## Biological mutation and the gossip-propagated faction shift (Sprint 4 §4).
##
## The half of this that is easy to get wrong is not the exposure arithmetic — it is that a
## mutation table can look complete while changing no number anywhere, and that an affinity table
## can look complete while naming cultures no faction has. Both are asserted below against the
## real content rather than against a fixture.
extends GutTest

var _chunk: ChunkData
var _player_row: int
var _system: MutationSystem


func before_each() -> void:
	GameLoopManager.set_physics_process(false)
	World.boot_scenario(World.SCENARIO_TEST_ARENA, 1)
	_chunk = World.active_chunk
	_chunk.hazard_tags.clear()
	_player_row = ECSManager.resolve(ECSManager.player_handle())
	_system = MutationSystem.new()


func after_all() -> void:
	GameLoopManager.set_physics_process(true)


func _soak(row: int, tag: StringName, seconds: float) -> void:
	ECSManager.chemistries[row].add_tag(tag)
	var elapsed: float = 0.0
	while elapsed < seconds:
		_system.run(0.5, _chunk)
		elapsed += 0.5


# --- Exposure -----------------------------------------------------------------------------------


func test_standing_in_spores_accrues_exposure() -> void:
	var body: BodyComponent = ECSManager.bodies[_player_row]
	ECSManager.chemistries[_player_row].add_tag(&"Spores")
	_system.run(0.5, _chunk)
	assert_almost_eq(
		float(body.exposure.get(&"FUNGAL", 0.0)), 1.0, 0.001, "2.0 per second for half a second"
	)


func test_clean_air_accrues_nothing() -> void:
	_system.run(0.5, _chunk)
	assert_eq(_system.exposures_accrued, 0, "nothing hazardous is present")
	assert_true(ECSManager.bodies[_player_row].exposure.is_empty(), "and no track was opened")


## A ZONE hazard, not a per-entity tag. Nothing about the player is tagged; the chunk is.
func test_a_hazardous_chunk_exposes_everything_standing_in_it() -> void:
	_chunk.hazard_tags.append(&"Radiation")
	_system.run(0.5, _chunk)
	assert_gt(
		float(ECSManager.bodies[_player_row].exposure.get(&"ARCANE", 0.0)),
		0.0,
		"a whole irradiated region is a hazard no entity tag models"
	)


# --- The mutation itself --------------------------------------------------------------------


func test_enough_exposure_produces_a_mutation() -> void:
	_soak(_player_row, &"Spores", 60.0)
	var body: BodyComponent = ECSManager.bodies[_player_row]
	assert_true(body.mutations.has(&"Fungal_Lungs"), "the fungal track produced its mutation")
	assert_eq(_system.mutations_granted, 1, "exactly one, not one per tick")


## THE PIN. The scaffolding resets exposure only after a SUCCESSFUL roll, so an entity already at
## MAX_MUTATIONS sits at the threshold and re-enters the mutation branch every single tick,
## forever. Resetting unconditionally is what stops that.
func test_exposure_resets_even_when_no_mutation_is_granted() -> void:
	var body: BodyComponent = ECSManager.bodies[_player_row]
	body.mutations = [&"A", &"B", &"C"]
	_soak(_player_row, &"Spores", 60.0)
	assert_lt(
		float(body.exposure.get(&"FUNGAL", 0.0)),
		WorldConstants.EXPOSURE_MUTATION_THRESHOLD,
		"a capped body does not stay pinned at the threshold"
	)


func test_mutations_are_capped() -> void:
	var body: BodyComponent = ECSManager.bodies[_player_row]
	body.mutations = [&"A", &"B", &"C"]
	_soak(_player_row, &"Spores", 60.0)
	assert_false(body.mutations.has(&"Fungal_Lungs"), "MAX_MUTATIONS is a hard cap")


## Every mutation must CHANGE A NUMBER. A table of evocative tag names that alters nothing is
## this codebase's signature defect, and a mutation table is the ideal shape for it.
func test_every_mutation_in_the_table_actually_changes_something() -> void:
	var inert: Array[String] = []
	for track in MutationSystem.MUTATIONS:
		for mutation in MutationSystem.MUTATIONS[track]:
			var moves: bool = (
				not is_zero_approx(float(mutation["max_stamina"]))
				or not is_zero_approx(float(mutation["max_health"]))
				or not is_zero_approx(float(mutation["armor"]))
				or not is_zero_approx(float(mutation["toughness"]))
				or not is_zero_approx(float(mutation["sight"]))
			)
			if not moves:
				inert.append(String(mutation["tag"]))
	assert_eq(inert, [] as Array[String], "no mutation is a name with no effect behind it")


func test_a_mutation_is_a_trade_not_an_upgrade() -> void:
	var traded: Array[String] = []
	for track in MutationSystem.MUTATIONS:
		for mutation in MutationSystem.MUTATIONS[track]:
			var cost: bool = false
			for field in ["max_stamina", "max_health", "armor", "toughness", "sight"]:
				if float(mutation[field]) < 0.0:
					cost = true
			if not cost:
				traded.append(String(mutation["tag"]))
	assert_eq(
		traded,
		[] as Array[String],
		"every mutation costs something, or a hazard becomes a farm"
	)


func test_fungal_lungs_costs_stamina_and_grants_resistance() -> void:
	var body: BodyComponent = ECSManager.bodies[_player_row]
	var before: float = body.max_stamina
	_soak(_player_row, &"Spores", 60.0)
	assert_almost_eq(body.max_stamina, before - 20.0, 0.001, "the lungs are worse at running")
	assert_true(body.mutations.has(&"Resist_Spores"), "and better at breathing spores")


## The resistance has to actually resist, or `Resist_Spores` is another name with nothing behind
## it. A body that already carries it accrues no further fungal exposure.
func test_resistance_stops_further_exposure_on_that_track() -> void:
	var body: BodyComponent = ECSManager.bodies[_player_row]
	_soak(_player_row, &"Spores", 60.0)
	body.exposure[&"FUNGAL"] = 0.0
	_system.run(0.5, _chunk)
	assert_almost_eq(
		float(body.exposure.get(&"FUNGAL", 0.0)), 0.0, 0.001, "Resist_Spores does its job"
	)


func test_lowering_max_health_clamps_current_health_with_it() -> void:
	var body: BodyComponent = ECSManager.bodies[_player_row]
	body.health = body.max_health
	_soak(_player_row, &"Toxic", 60.0)
	assert_lte(body.health, body.max_health, "a body never reports 100 out of 90")


func test_a_dead_body_does_not_mutate() -> void:
	var body: BodyComponent = ECSManager.bodies[_player_row]
	body.health = 0.0
	_soak(_player_row, &"Spores", 60.0)
	assert_true(body.mutations.is_empty(), "corpses are not part of the ecology loop this way")


# --- The faction shift (review D3) ------------------------------------------------------------


## THE DEAD-TABLE GUARD. The first draft of `MUTATION_AFFINITY` named `CULTURE_FUNGAL` and three
## siblings that no generated faction has ever carried, which would have made every affinity
## branch unreachable and the whole mechanism a constant revulsion wearing a lookup table.
func test_every_mutation_affinity_names_a_real_culture() -> void:
	var real: Dictionary = {}
	for culture in DAGGenerator.CULTURES:
		for tag in culture["tags"]:
			real[tag] = true
	var invented: Array[String] = []
	for action in ReputationSystem.MUTATION_AFFINITY:
		var tag: StringName = ReputationSystem.MUTATION_AFFINITY[action]
		if not real.has(tag):
			invented.append("%s -> %s" % [action, tag])
	assert_eq(invented, [] as Array[String], "every affinity tag is one a faction can actually hold")


## And the other direction: every mutation track the system can produce has an affinity entry, or
## a whole track silently defaults to revulsion.
func test_every_mutation_track_has_an_affinity_entry() -> void:
	var missing: Array[String] = []
	for track in MutationSystem.MUTATIONS:
		if not ReputationSystem.MUTATION_AFFINITY.has(StringName("MUTATION_%s" % track)):
			missing.append(String(track))
	assert_eq(missing, [] as Array[String], "no track falls through to the default by accident")


func _culture(tags: Array[StringName]) -> FactionCoreComponent:
	var core := FactionCoreComponent.new()
	core.faction_id = 77
	core.culture_tags = tags
	return core


func test_a_scavenger_culture_welcomes_what_a_farmer_recoils_from() -> void:
	var goblins: FactionCoreComponent = _culture([&"Raiding", &"Scavenging"])
	var villagers: FactionCoreComponent = _culture([&"Farming", &"Trade"])
	assert_gt(
		ReputationSystem.severity_for(&"MUTATION_FUNGAL", goblins),
		0.0,
		"the goblins are pleased"
	)
	assert_lt(
		ReputationSystem.severity_for(&"MUTATION_FUNGAL", villagers),
		0.0,
		"the village is not"
	)


## Crime severity is unchanged by culture. Only mutation is culture-dependent; making murder
## negotiable would be a much larger design change than this sprint is making.
func test_murder_is_murder_to_everybody() -> void:
	assert_eq(
		ReputationSystem.severity_for(&"MURDER", _culture([&"Raiding", &"Scavenging"])),
		ReputationSystem.severity_for(&"MURDER", _culture([&"Farming", &"Trade"])),
		"culture does not make a killing acceptable"
	)


## NOT INSTANT, NOT A HIVEMIND. A mutation is queued as a witnessable act; who learns about it is
## perception's problem. Nobody watching means nothing changes.
func test_a_mutation_nobody_saw_changes_no_relationship() -> void:
	_soak(_player_row, &"Spores", 60.0)
	var acts: Array[Dictionary] = _system.take_witnessed_mutations()
	assert_eq(acts.size(), 1, "the mutation was queued as witnessable")
	assert_eq(
		StringName(acts[0]["action"]),
		&"MUTATION_FUNGAL",
		"and named its track, so the witness's culture can decide how to take it"
	)
	assert_eq(
		_system.take_witnessed_mutations().size(),
		0,
		"draining is one-shot — reading the batch twice would double every consequence"
	)


func test_the_mutation_signal_carries_the_tag() -> void:
	var seen: Array[String] = []
	ECSEvents.entity_mutated.connect(
		func(_e: int, mutation: StringName) -> void: seen.append(String(mutation))
	)
	_soak(_player_row, &"Spores", 60.0)
	assert_eq(seen, ["Fungal_Lungs"], "the UI does not have to poll BodyComponent to notice")


# --- Death resets the body, not the mind -------------------------------------------------------


## Mutations are permanent WITHIN a run and reset on death; insight and runes carry (magic §6).
func test_mutations_do_not_survive_death() -> void:
	_soak(_player_row, &"Spores", 60.0)
	assert_false(ECSManager.bodies[_player_row].mutations.is_empty(), "the run had a mutation")

	LineageJournal.erase()
	GameLoopManager.death_loop.on_player_death(EH.INVALID, null)
	GameLoopManager.death_loop.spawn_successor(_chunk, LineageJournal.load_journal())

	var successor: int = ECSManager.resolve(ECSManager.player_handle())
	assert_true(
		ECSManager.bodies[successor].mutations.is_empty(),
		"the next adventurer is a different person, not a reload"
	)


## THE REGRESSION THIS ALMOST SHIPPED WITH. `LineageJournal.apply_to` used to REPLACE the whole
## insight dictionary, so a successor born with an empty journal — a first death with no file on
## disk — had `Rune_Stability` wiped to 0 and could never compile a spell again, with no error
## anywhere to explain it.
func test_a_successor_born_with_no_journal_can_still_cast() -> void:
	LineageJournal.erase()
	GameLoopManager.death_loop.on_player_death(EH.INVALID, null)
	GameLoopManager.death_loop.spawn_successor(_chunk, LineageJournal._empty())

	var successor: int = ECSManager.resolve(ECSManager.player_handle())
	var mind: MindComponent = ECSManager.minds[successor]
	assert_gt(
		SpellCompilerSystem.complexity_budget(mind),
		0.0,
		"an empty journal must not erase the field primer it was merged into"
	)
	var compiler := SpellCompilerSystem.new()
	assert_true(
		compiler.compile(
			[&"On_Cast", &"On_Impact", &"Projectile", &"Add_Temperature", &"Apply_Burning"],
			mind
		)["ok"],
		"and the successor can actually cast"
	)
