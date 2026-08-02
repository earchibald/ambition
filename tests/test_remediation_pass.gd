## The 2026-08-01 remediation pass: overclocking, the event trace, smoke, territory, and the
## calendar. Everything here was either a declared gap or an audit finding; each test names its
## source so a future reader knows which claim it pins.
extends GutTest

const SEED: int = 77

var _chunk: ChunkData


func before_each() -> void:
	GameLoopManager.set_physics_process(false)
	World.boot_scenario(World.SCENARIO_TEST_ARENA, SEED)
	RNGService.reseed_all(SEED)
	_chunk = World.active_chunk
	EventTrace.clear()
	DebugFlags.event_trace_enabled = false


func after_all() -> void:
	DebugFlags.event_trace_enabled = false
	GameLoopManager.set_physics_process(true)


# --- Overclocking and the mishap table (grimoire spec §2C, declared gap G-2) --------------------

## A structurally VALID spell whose complexity exceeds a deliberately starved budget: the
## starting-rune fireball (complexity 8) against Rune_Stability 1 (budget 1.5).
func _heavy_runes() -> Array:
	return [&"On_Cast", &"Projectile", &"Add_Temperature", &"Apply_Burning"]


func _starved_mind() -> MindComponent:
	var mind: MindComponent = ECSManager.minds[WorldConstants.PLAYER_INDEX]
	mind.insight[&"Rune_Stability"] = 1
	return mind


func test_a_too_complex_spell_is_still_refused_without_overclock() -> void:
	var compiler := SpellCompilerSystem.new()
	var result: Dictionary = compiler.compile(_heavy_runes(), _starved_mind())
	assert_false(result["ok"], "the complexity gate still refuses by default")


func test_overclock_forces_the_compile_and_brands_it_unstable() -> void:
	var compiler := SpellCompilerSystem.new()
	var result: Dictionary = compiler.compile(_heavy_runes(), _starved_mind(), true)
	assert_true(result["ok"], "the refusal can be FORCED past")
	assert_true(result["spell"].unstable, "and the price is a permanent [Unstable] brand")
	assert_eq(compiler.overclocked_compiles, 1)


func test_a_structural_problem_cannot_be_overclocked() -> void:
	var compiler := SpellCompilerSystem.new()
	var mind: MindComponent = ECSManager.minds[WorldConstants.PLAYER_INDEX]
	var result: Dictionary = compiler.compile([&"On_Cast"], mind, true)
	assert_false(result["ok"], "a spell with no shape is not risky — it is not a spell")


func test_an_unstable_cast_rolls_the_mishap_table() -> void:
	var combat := ActionResolutionSystem.new()
	var mind: MindComponent = ECSManager.minds[WorldConstants.PLAYER_INDEX]
	var spell := CompiledSpell.new()
	spell.spell_id = &"unstable_test"
	spell.strain_cost = 5.0
	spell.shape = RuneLibrary.SHAPE_SELF
	spell.unstable = true
	mind.grimoire[&"unstable_test"] = spell
	assert_true(
		combat.resolve_cast(WorldConstants.PLAYER_INDEX, &"unstable_test", Vector3.FORWARD)
	)
	assert_eq(combat.mishaps_rolled, 1, "unstable means the d100 rolls on EVERY cast")


func test_the_mercy_cap_cannot_kill_the_player() -> void:
	var combat := ActionResolutionSystem.new()
	var body: BodyComponent = ECSManager.bodies[WorldConstants.PLAYER_INDEX]
	body.health = 3.0
	combat._mishap_wound(WorldConstants.PLAYER_INDEX, 500.0, &"Bleeding")
	assert_almost_eq(body.health, 1.0, 0.001, "no mishap reduces Entity 0 below 1 HP")
	var chemistry: ChemistryComponent = ECSManager.chemistries[WorldConstants.PLAYER_INDEX]
	assert_true(
		chemistry.has_tag(&"Arcane_Burn"),
		"the excess converts to trauma that cripples recovery, per the spec"
	)


func test_over_pressure_doubles_a_copy_never_the_grimoire() -> void:
	var combat := ActionResolutionSystem.new()
	var spell := CompiledSpell.new()
	spell.radius_m = 5.0
	spell.unstable = true
	spell.shape = RuneLibrary.SHAPE_PROJECTILE
	# Walk the seeded stream until an Over-Pressure roll (51-85) is next, then roll for real.
	var probe := RandomNumberGenerator.new()
	probe.seed = RNGService.stream(&"magic").seed
	probe.state = RNGService.stream(&"magic").state
	while true:
		var upcoming: int = probe.randi_range(1, 100)
		if upcoming > 50 and upcoming <= 85:
			break
		RNGService.randi_range_in(&"magic", 1, 100)
		probe.seed = RNGService.stream(&"magic").seed
		probe.state = RNGService.stream(&"magic").state
	var cast: CompiledSpell = combat._roll_mishap(WorldConstants.PLAYER_INDEX, spell)
	assert_almost_eq(cast.radius_m, 10.0, 0.001, "the CAST doubles")
	assert_almost_eq(spell.radius_m, 5.0, 0.001, "the grimoire's copy never ratchets")


# --- The event trace (debugging spec §3, built 2026-08-01) --------------------------------------

func test_the_trace_records_nothing_while_disabled() -> void:
	EventTrace.record(&"test", &"noop", 0)
	assert_eq(EventTrace.snapshot().size(), 0, "a disabled trace costs a boolean")


func test_the_trace_is_a_ring_at_the_configured_capacity() -> void:
	DebugFlags.event_trace_enabled = true
	DebugFlags.trace_capacity = 8
	for i in 20:
		EventTrace.record(&"test", &"tick", i)
	var events: Array[Dictionary] = EventTrace.snapshot()
	assert_eq(events.size(), 8, "the ring holds exactly the configured capacity")
	assert_eq(int(events[0]["entity"]), 12, "oldest surviving record is the 13th")
	assert_eq(int(events[7]["entity"]), 19, "newest is the last")
	DebugFlags.trace_capacity = DebugFlags.DEFAULT_TRACE_CAPACITY


func test_the_trace_dumps_a_csv_into_the_trace_dir() -> void:
	DebugFlags.event_trace_enabled = true
	EventTrace.record(&"test", &"boom", 42, "detail")
	var path: String = EventTrace.dump_to_file("guttest")
	assert_true(FileAccess.file_exists(path), "the dump exists where the spec says")
	var text: String = FileAccess.open(path, FileAccess.READ).get_as_text()
	assert_string_contains(text, "frame,clock_h,system,event,entity,detail", "with a header")
	assert_string_contains(text, "boom", "and the record")


func test_bus_events_land_in_the_trace() -> void:
	DebugFlags.event_trace_enabled = true
	ECSEvents.entity_died.emit(ECSManager.player_handle(), &"test")
	var found: bool = false
	for entry in EventTrace.snapshot():
		if entry["event"] == &"died":
			found = true
	assert_true(found, "the loop wired the outcome bus into the trace")


# --- Smoke blocks sight (Sprint 1 scaffolding mandate, unbuilt for four sprints) ----------------

func test_a_smoke_cloud_blocks_line_of_sight() -> void:
	var perception := PerceptionSystem.new()
	var from := Vector3(2.0, 0.5, 2.0)
	var to := Vector3(10.0, 0.5, 2.0)
	assert_true(
		GridDDA.has_line_of_sight(from, to, _chunk), "the corridor is open without smoke"
	)
	var smoke_tags: Array[StringName] = [&"Smoke"]
	EphemeralSystem.spawn_aura(Vector3(6.0, 0.5, 2.0), smoke_tags, 2.0, 5.0, EH.INVALID)
	perception._collect_vision_clouds()
	assert_false(
		perception._line_of_sight(1, 2, from, to, _chunk),
		"a sight line through the cloud is blocked"
	)
	assert_gt(perception.sight_blocked_by_smoke, 0, "and counted")


func test_sight_around_the_cloud_survives() -> void:
	var perception := PerceptionSystem.new()
	var smoke_tags: Array[StringName] = [&"Smoke"]
	EphemeralSystem.spawn_aura(Vector3(6.0, 0.5, 2.0), smoke_tags, 1.0, 5.0, EH.INVALID)
	perception._collect_vision_clouds()
	assert_true(
		perception._line_of_sight(1, 2, Vector3(2.0, 0.5, 6.0), Vector3(10.0, 0.5, 6.0), _chunk),
		"smoke is a cloud, not a wall across the whole room"
	)


# --- ClaimTags, trespass, and Guest_Status ------------------------------------------------------

func test_trespass_on_claimed_ground_without_guest_status_is_a_grievance() -> void:
	var social := SocialSystem.new()
	var core := FactionCoreComponent.new()
	core.faction_id = 600
	var macro: int = EH.index_of(ECSManager.allocate_entity())
	ECSManager.faction_cores[macro] = core
	ECSManager.add_component_bit(macro, ComponentMask.FACTION_CORE)
	_chunk.claim_faction_id = 600
	ECSManager.chemistries[WorldConstants.PLAYER_INDEX].remove_tag(&"Guest_Status")

	social._check_trespass()

	assert_eq(social.trespasses, 1, "standing on claimed ground uninvited is noticed")
	assert_lt(
		ReputationSystem.relationship_score(core, WorldConstants.PLAYER_FACTION_ID), 0.0,
		"and held against you"
	)


func test_a_guest_does_not_trespass() -> void:
	var social := SocialSystem.new()
	var core := FactionCoreComponent.new()
	core.faction_id = 601
	var macro: int = EH.index_of(ECSManager.allocate_entity())
	ECSManager.faction_cores[macro] = core
	ECSManager.add_component_bit(macro, ComponentMask.FACTION_CORE)
	_chunk.claim_faction_id = 601
	ECSManager.chemistries[WorldConstants.PLAYER_INDEX].add_tag(&"Guest_Status")
	social._check_trespass()
	assert_eq(social.trespasses, 0, "Guest_Status means welcome")


func test_a_witnessed_crime_revokes_guest_status() -> void:
	var reputation := ReputationSystem.new()
	var chemistry: ChemistryComponent = ECSManager.chemistries[WorldConstants.PLAYER_INDEX]
	chemistry.add_tag(&"Guest_Status")
	var core := FactionCoreComponent.new()
	core.faction_id = 602
	var macro: int = EH.index_of(ECSManager.allocate_entity())
	ECSManager.faction_cores[macro] = core
	ECSManager.add_component_bit(macro, ComponentMask.FACTION_CORE)
	var witness: int = EH.index_of(ECSManager.allocate_entity())
	ECSManager.social_identities[witness] = SocialIdentityComponent.new(602)
	ECSManager.add_component_bit(witness, ComponentMask.SOCIAL_IDENTITY)

	reputation._record(WitnessEvent.create(
		ECSManager.handle_of(witness), ECSManager.player_handle(), &"THEFT",
		Vector3.ZERO, 0, 1.0
	))

	assert_false(
		chemistry.has_tag(&"Guest_Status"),
		"seen stealing, no longer a guest — the invariant's missing half"
	)
	assert_eq(reputation.guest_status_revoked, 1)


# --- The Interregnum moves the calendar ---------------------------------------------------------

func test_the_interregnum_advances_the_year() -> void:
	var year_before: int = GameClock.total_hours()
	var bootstrapper := Bootstrapper.new()
	bootstrapper.economy = GrayBoxSystem.new()
	bootstrapper._run_interregnum()
	assert_gte(
		GameClock.total_hours() - year_before, 8000,
		"a year of absence is a year on the calendar — 'recently' comparisons need it"
	)


# --- DAG compaction (ADR-12) --------------------------------------------------------------------

func test_compaction_prunes_only_the_unremembered_dead() -> void:
	var generator := DAGGenerator.new()
	generator.run_history_generation()
	var kept_victims: Array[int] = []
	for node_id in generator.nodes:
		var node: DAGNode = generator.nodes[node_id]
		if not node.is_active() and node.conquered_by >= 0:
			if generator._is_active(node.conquered_by):
				kept_victims.append(node_id)
	generator.compact()
	for node_id in kept_victims:
		assert_true(
			generator.nodes.has(node_id),
			"a conquest victim survives while its conqueror lives — the DAG answers 'why'"
		)
	for node_id in generator.nodes:
		var node: DAGNode = generator.nodes[node_id]
		if node.type != ECSEnums.NodeType.FACTION or node.is_active():
			continue
		var justified: bool = generator._forged_anything(node_id)
		for edge in generator.edges:
			if edge.source_id == node_id and generator._is_active(edge.target_id):
				justified = true
			if edge.target_id == node_id and generator._is_active(edge.source_id):
				justified = true
		assert_true(justified, "every surviving dead node %d has a living reason" % node_id)


# --- The two vacuities my own review of THIS pass found -----------------------------------------

## The spawn floor cannot bind at today's constants (-100 x 0.30 = -30 sits above the -40
## line), so the integration test passes with or without the clamp — the exact "enforced by
## coincidence" trap the audit flagged. The rule is therefore asserted DIRECTLY, with a score
## the decay cannot currently produce.
func test_the_spawn_floor_binds_when_the_arithmetic_accident_stops_protecting() -> void:
	assert_gt(
		DeathLoopSystem.spawn_faction_floor(-90.0),
		ReputationSystem.HOSTILE_BELOW,
		"a hypothetical -90 after decay is still clamped out of WAR"
	)
	assert_almost_eq(
		DeathLoopSystem.spawn_faction_floor(-10.0), -10.0, 0.001,
		"and a score already above the line is untouched"
	)
