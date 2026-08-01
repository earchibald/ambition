## Death, the Interregnum, and the Lineage Journal (Sprint 3D).
##
## The premise of the death loop is that the WORLD persists and the CHARACTER does not. Most of
## these tests defend that boundary in one direction or the other: carry everything forward and
## death costs nothing, carry nothing and forty hours of learning evaporates.
extends GutTest

const SEED: int = 909

var deaths: DeathLoopSystem
var generator: DAGGenerator


func before_each() -> void:
	GameLoopManager.set_physics_process(false)
	LineageJournal.erase()
	World.boot_scenario(World.SCENARIO_TEST_ARENA, SEED)
	RNGService.reseed_all(SEED)
	generator = DAGGenerator.new()
	generator.run_history_generation()
	deaths = DeathLoopSystem.new()


func after_all() -> void:
	LineageJournal.erase()
	GameLoopManager.set_physics_process(true)


# --- The death event ----------------------------------------------------------------------------

## Row 0 is reserved for the player forever (ADR-14), so the corpse CANNOT be left there — every
## system that asks "where is the player" would find a body.
func test_the_corpse_is_a_separate_entity_not_the_player_row() -> void:
	var corpse: int = deaths.on_player_death(EH.INVALID, generator)
	assert_ne(EH.index_of(corpse), WorldConstants.PLAYER_INDEX, "the corpse is not on row 0")
	assert_true(ECSManager.is_alive(corpse), "and it is a real entity in the world")


## A dead player who can still walk is the worst possible frame.
func test_control_is_severed_immediately() -> void:
	var row: int = EH.index_of(ECSManager.player_handle())
	assert_true(ECSManager.player_inputs.has(row), "the player starts controllable")
	deaths.on_player_death(EH.INVALID, generator)
	assert_false(ECSManager.player_inputs.has(row), "and is not, once dead")
	assert_eq(ECSManager.velocity_of(row), Vector3.ZERO, "and has stopped moving")


## The roadmap's success state is watching your killer pick up your sword, which needs the sword
## to be a real object rather than a line in a save file.
func test_possessions_move_into_the_corpse() -> void:
	var row: int = EH.index_of(ECSManager.player_handle())
	var sword: int = World.spawn_item(
		ECSManager.position_of(row), MaterialLibrary.MAT_IRON, 900.0, 1
	)
	GameLoopManager.inventory.try_insert(row, sword)
	assert_eq(ECSManager.inventories[row].held_items.size(), 1, "the sword is carried")

	var corpse: int = deaths.on_player_death(EH.INVALID, generator)
	var corpse_row: int = ECSManager.resolve(corpse)
	assert_eq(ECSManager.inventories[corpse_row].held_items.size(), 1, "and is now on the body")
	assert_eq(ECSManager.inventories[row].held_items.size(), 0, "and no longer on the player")
	assert_eq(deaths.items_spilled, 1, "reported")


## Loot must not stay owned by the dead, or the LoD sweep banks it into a faction ledger the
## player was never a member of.
func test_spilled_loot_belongs_to_nobody() -> void:
	var row: int = EH.index_of(ECSManager.player_handle())
	var sword: int = World.spawn_item(
		ECSManager.position_of(row), MaterialLibrary.MAT_IRON, 900.0, 1
	)
	var sword_row: int = ECSManager.resolve(sword)
	ECSManager.ownerships[sword_row] = OwnershipComponent.new(WorldConstants.PLAYER_FACTION_ID)
	ECSManager.add_component_bit(sword_row, ComponentMask.OWNERSHIP)
	GameLoopManager.inventory.try_insert(row, sword)

	deaths.on_player_death(EH.INVALID, generator)
	assert_false(ECSManager.ownerships.has(sword_row), "the sword is loot now")


## THE GENERATION BUMP. Every handle to the previous adventurer must fail, not silently resolve
## to their replacement — which is the subtlest bug this architecture can produce, and the whole
## reason handles carry a generation.
func test_the_old_player_handle_dies_when_the_successor_arrives() -> void:
	var before: int = ECSManager.player_handle()
	deaths.on_player_death(EH.INVALID, generator)
	deaths.spawn_successor(World.active_chunk, LineageJournal.load_journal())

	assert_false(ECSManager.is_alive(before), "the old handle is dead")
	assert_true(ECSManager.is_alive(ECSManager.player_handle()), "the new one is alive")
	assert_ne(before, ECSManager.player_handle(), "and they are different handles")
	assert_eq(
		EH.index_of(ECSManager.player_handle()),
		WorldConstants.PLAYER_INDEX,
		"while still occupying the reserved row"
	)


## Row 0 must never reach the free list, or the next allocation hands the player's reserved slot
## to a rat.
func test_the_reserved_row_is_never_recycled() -> void:
	deaths.on_player_death(EH.INVALID, generator)
	deaths.spawn_successor(World.active_chunk, LineageJournal.load_journal())
	var next: int = ECSManager.allocate_entity()
	assert_ne(EH.index_of(next), WorldConstants.PLAYER_INDEX, "row 0 was not handed out")


func test_the_death_is_written_into_history() -> void:
	var before: int = generator.edges.size()
	deaths.on_player_death(EH.INVALID, generator)
	assert_eq(generator.edges.size(), before + 1, "an edge was added")
	var edge: DAGEdge = generator.edges[generator.edges.size() - 1]
	assert_eq(edge.source_id, WorldConstants.PLAYER_FACTION_ID, "hung off Faction 0 (ADR-14)")
	assert_eq(edge.type, ECSEnums.EdgeType.KILLED_BY, "and says what kind of event it was")


## THE EDGE POINTED THE WRONG WAY. It was `DESTROYED(player, killer)`, which under this graph's
## own convention — `CONQUERED(aggressor, victim)` — reads as the player having wiped out the
## killer's faction. The old test asserted only `source_id`, so it passed throughout.
func test_the_death_edge_does_not_claim_the_player_destroyed_anyone() -> void:
	var rat: int = World.spawn_creature(ECSManager.position_of(0) + Vector3(1.0, 0.0, 0.0))
	var rat_row: int = ECSManager.resolve(rat)
	var identity := SocialIdentityComponent.new()
	identity.faction_id = 7
	ECSManager.social_identities[rat_row] = identity
	ECSManager.add_component_bit(rat_row, ComponentMask.SOCIAL_IDENTITY)

	deaths.on_player_death(rat, generator)
	var edge: DAGEdge = generator.edges[generator.edges.size() - 1]
	assert_eq(edge.type, ECSEnums.EdgeType.KILLED_BY, "the type says who did what to whom")
	assert_eq(edge.target_id, 7, "the killer is the other end of the edge")
	for written in generator.edges:
		if written.type == ECSEnums.EdgeType.DESTROYED:
			assert_ne(written.target_id, 7, "faction 7 was NOT destroyed; it won")


## A fall or a starvation has no killer. An edge to faction -1 is a dangling reference in the
## only record of why the world looks the way it does, so an unwitnessed death is a self-loop.
func test_a_death_with_no_killer_records_a_valid_edge() -> void:
	deaths.on_player_death(EH.INVALID, generator)
	var edge: DAGEdge = generator.edges[generator.edges.size() - 1]
	assert_eq(edge.target_id, WorldConstants.PLAYER_FACTION_ID, "a self-loop, not faction -1")
	assert_gte(edge.target_id, 0, "and never a node that does not exist")


# --- The grudge decay ---------------------------------------------------------------------------

## Reputation was PERMANENT. Sprint 3.5 gave factions a reason to hate the player and Sprint 3D
## gave the player a way to die, and nothing connected them, so a hostile village stayed hostile
## across every future life. That makes the death loop a respawn, not a fresh start.
func test_a_year_away_cools_a_grudge() -> void:
	var core: FactionCoreComponent = _make_core(0)
	ReputationSystem.adjust(core, WorldConstants.PLAYER_FACTION_ID, -80.0, &"MURDER")
	var before: float = ReputationSystem.relationship_score(
		core, WorldConstants.PLAYER_FACTION_ID
	)
	deaths._decay_grudges()
	var after: float = ReputationSystem.relationship_score(
		core, WorldConstants.PLAYER_FACTION_ID
	)
	assert_gt(after, before, "they are less angry than they were")
	assert_lt(after, 0.0, "and have not forgotten entirely")
	assert_eq(deaths.grudges_decayed, 1, "reported")


## The score decays. The grievance list does not. They stop acting on it and still remember.
func test_the_year_does_not_erase_what_you_did() -> void:
	var core: FactionCoreComponent = _make_core(0)
	ReputationSystem.adjust(core, WorldConstants.PLAYER_FACTION_ID, -80.0, &"MURDER")
	deaths._decay_grudges()
	var state: Dictionary = core.diplomacy[WorldConstants.PLAYER_FACTION_ID]
	assert_true(state["grievances"].has(&"MURDER"), "the record of the murder survives")


## Crossing back out of hostility has to update the status, or a faction reads as at WAR with a
## score that is no longer hostile and the two disagree forever.
func test_cooling_below_the_threshold_restores_the_status() -> void:
	var core: FactionCoreComponent = _make_core(0)
	ReputationSystem.adjust(core, WorldConstants.PLAYER_FACTION_ID, -60.0, &"MURDER")
	assert_eq(
		core.diplomacy[WorldConstants.PLAYER_FACTION_ID]["status"],
		ECSEnums.RelationshipStatus.WAR,
		"hostile to begin with"
	)
	deaths._decay_grudges()
	assert_eq(
		core.diplomacy[WorldConstants.PLAYER_FACTION_ID]["status"],
		ECSEnums.RelationshipStatus.NEUTRAL,
		"and no longer at war once the score says so"
	)


## Everyone else's opinion is none of the dead player's business.
func test_the_decay_only_touches_the_players_reputation() -> void:
	var core: FactionCoreComponent = _make_core(0)
	ReputationSystem.adjust(core, 9, -80.0, &"MURDER")
	var before: float = ReputationSystem.relationship_score(core, 9)
	deaths._decay_grudges()
	assert_almost_eq(
		ReputationSystem.relationship_score(core, 9), before, 0.01,
		"a feud between two other factions is not settled by the player dying"
	)


# --- The Interregnum taxes -------------------------------------------------------------------

## ADR-11: the tax is levied on LEDGERS. Taxing physical entities would mean materializing the
## world in order to delete it.
func test_the_entropy_tax_takes_forty_percent_of_ledger_wealth() -> void:
	var core: FactionCoreComponent = _make_core(1000)
	deaths._levy_entropy_tax()
	assert_eq(
		int(core.abstract_wealth_ledger[MaterialLibrary.MAT_IRON]),
		600,
		"sixty percent survives a year of nobody minding the store"
	)
	assert_eq(deaths.wealth_taxed, 400, "and the loss is reported")


## Rats breed geometrically in an abstract counter. Twelve unchecked months is a number that
## overflows the save format before it overflows the dungeon.
func test_swarms_are_capped_on_the_counter_not_by_deleting_entities() -> void:
	var grid := WorldGrid.new(SEED)
	grid.generate_village()
	var chunk: ChunkData = grid.chunk_at(Vector3i.ZERO)
	chunk.swarm_population = 5000
	var before: int = ECSManager.alive_count

	deaths._cap_swarms(grid)
	assert_eq(chunk.swarm_population, DeathLoopSystem.SWARM_CAP_PER_CHUNK, "capped")
	assert_eq(ECSManager.alive_count, before, "and not one entity was created or destroyed")


func test_filth_is_always_collected() -> void:
	var junk: int = World.spawn_item(Vector3(5, 1, 5), MaterialLibrary.MAT_BIOMASS, 10.0, 1)
	ECSManager.chemistries[ECSManager.resolve(junk)].add_tag(&"Filth")
	deaths._collect_junk()
	assert_false(ECSManager.is_alive(junk), "filth does not survive the year")


## Owned goods belong to somebody who would have picked them up.
func test_owned_items_survive_the_year() -> void:
	var kept: int = World.spawn_item(Vector3(5, 1, 5), MaterialLibrary.MAT_IRON, 10.0, 1)
	var row: int = ECSManager.resolve(kept)
	ECSManager.ownerships[row] = OwnershipComponent.new(7)
	ECSManager.add_component_bit(row, ComponentMask.OWNERSHIP)
	for _pass in 5:
		deaths._collect_junk()
	assert_true(ECSManager.is_alive(kept), "somebody owns it, so somebody kept it")


## ADR-20: random deletion must come from an RNG stream, or the soak harness cannot reproduce it.
func test_junk_collection_is_reproducible_from_the_seed() -> void:
	var first: int = _sweep_count_with_seed(1234)
	var second: int = _sweep_count_with_seed(1234)
	assert_eq(second, first, "the same seed sweeps the same items")


# --- The Lineage Journal --------------------------------------------------------------------

## Knowledge crosses. Possessions do not.
func test_insight_and_runes_carry_across_a_death() -> void:
	var row: int = EH.index_of(ECSManager.player_handle())
	var mind: MindComponent = ECSManager.minds[row]
	mind.insight = {&"MAT_IRON": 3}
	mind.known_runes.append(&"RUNE_EMBER")

	deaths.on_player_death(EH.INVALID, generator)
	deaths.spawn_successor(World.active_chunk, LineageJournal.load_journal())

	var successor: MindComponent = ECSManager.minds[EH.index_of(ECSManager.player_handle())]
	assert_eq(int(successor.insight.get("MAT_IRON", 0)), 3, "what was learned is remembered")
	assert_true(successor.known_runes.has(&"RUNE_EMBER"), "and so are the runes")


func test_possessions_do_not_carry_across_a_death() -> void:
	var row: int = EH.index_of(ECSManager.player_handle())
	var sword: int = World.spawn_item(
		ECSManager.position_of(row), MaterialLibrary.MAT_IRON, 900.0, 1
	)
	GameLoopManager.inventory.try_insert(row, sword)
	deaths.on_player_death(EH.INVALID, generator)
	deaths.spawn_successor(World.active_chunk, LineageJournal.load_journal())
	assert_eq(
		ECSManager.inventories[EH.index_of(ECSManager.player_handle())].held_items.size(),
		0,
		"the new adventurer starts empty-handed"
	)


## The journal is the LINEAGE's memory, not one life's. A later adventurer who learned less about
## a subject must not erase what an earlier one knew.
func test_a_later_death_never_lowers_recorded_insight() -> void:
	var row: int = EH.index_of(ECSManager.player_handle())
	ECSManager.minds[row].insight = {&"MAT_IRON": 9}
	LineageJournal.record_death(row)

	ECSManager.minds[row].insight = {&"MAT_IRON": 2}
	var journal: Dictionary = LineageJournal.record_death(row)
	assert_eq(int(journal["insight"]["MAT_IRON"]), 9, "the high-water mark is kept")
	assert_eq(int(journal["deaths"]), 2, "and both deaths are counted")


## Corrupt beats crashed. A damaged journal costs the player their notes; refusing to boot costs
## them the game.
func test_a_corrupt_journal_starts_fresh_rather_than_crashing() -> void:
	var file: FileAccess = FileAccess.open(LineageJournal.PATH, FileAccess.WRITE)
	file.store_string("this is not json {{{")
	file = null
	var journal: Dictionary = LineageJournal.load_journal()
	# Godot's JSON parser logs its own error for the deliberately-broken file. That log IS the
	# expected behaviour here, so it is acknowledged rather than suppressed globally — silencing
	# parse errors across the suite would hide real ones everywhere else.
	for tracked in gut.error_tracker.get_current_test_errors():
		tracked.handled = true

	assert_eq(int(journal["deaths"]), 0, "it read as empty")
	assert_eq(int(journal["schema_version"]), LineageJournal.SCHEMA_VERSION, "with a valid schema")


## Reading a NEWER schema with older code is how a save gets silently mangled.
func test_a_journal_from_a_newer_build_is_refused_not_guessed_at() -> void:
	LineageJournal.save_journal({
		"schema_version": LineageJournal.SCHEMA_VERSION + 5,
		"insight": {&"MAT_IRON": 99},
		"known_runes": [],
		"deaths": 7,
	})
	var journal: Dictionary = LineageJournal.load_journal()
	assert_eq(int(journal["deaths"]), 0, "the future file was ignored, not misread")


func test_a_missing_journal_is_a_first_run_not_an_error() -> void:
	LineageJournal.erase()
	var journal: Dictionary = LineageJournal.load_journal()
	assert_eq(int(journal["generation"]), 0, "generation zero")
	assert_eq(journal["insight"], {}, "and nothing known yet")


# --- fixtures ------------------------------------------------------------------------------------

func _make_core(iron: int) -> FactionCoreComponent:
	var handle: int = ECSManager.allocate_entity()
	var row: int = EH.index_of(handle)
	var core := FactionCoreComponent.new()
	core.faction_id = 4242
	core.abstract_wealth_ledger = {MaterialLibrary.MAT_IRON: iron}
	ECSManager.faction_cores[row] = core
	ECSManager.add_component_bit(row, ComponentMask.FACTION_CORE)
	return core


func _sweep_count_with_seed(seed_value: int) -> int:
	World.boot_scenario(World.SCENARIO_TEST_ARENA, SEED)
	RNGService.reseed_all(seed_value)
	for i in 30:
		World.spawn_item(Vector3(float(i), 1.0, 5.0), MaterialLibrary.MAT_IRON, 10.0, 1)
	var sweeper := DeathLoopSystem.new()
	sweeper._collect_junk()
	return sweeper.junk_collected


## THE DEATH LOOP MUST BE COMPLETABLE. Sprint 3's headline feature is that death is a loop rather
## than a screen, and until the debug keys existed there was no way to reach it in the generated
## world — no pit, no hazard, nothing hostile — and no way to leave it once reached, because the
## Interregnum had no trigger. A feature a play-tester cannot reach has not shipped.
func test_a_full_death_and_rebirth_cycle_completes() -> void:
	var body: BodyComponent = ECSManager.bodies[EH.index_of(ECSManager.player_handle())]
	body.health = 0.0
	var corpse: int = deaths.on_player_death(EH.INVALID, generator)
	assert_true(ECSManager.is_alive(corpse), "there is a body")

	deaths.run_interregnum(null, null)
	var successor: int = deaths.spawn_successor(World.active_chunk, LineageJournal.load_journal())

	assert_true(ECSManager.is_alive(successor), "and a new adventurer")
	assert_true(
		ECSManager.bodies[EH.index_of(successor)].is_alive(), "who is alive and at full health"
	)
	assert_true(
		ECSManager.player_inputs.has(EH.index_of(successor)), "and can be controlled again"
	)


## The arena has no bootstrapper and no grid. Dying there must still complete rather than crash
## on a null, or the fast iteration scenario cannot exercise the loop at all.
func test_the_interregnum_survives_a_world_with_no_history() -> void:
	deaths.run_interregnum(null, null)
	assert_eq(deaths.swarms_capped, 0, "no grid means no swarms to cap, and no crash")


# --- Remediation pass (2026-08-01): the spawn floor, the swarm tax's missing half, and the
# --- Residence ----------------------------------------------------------------------------------

## The death-loop doc marks this REQUIRED: the spawn faction is hard-clamped to a floor of
## NEUTRAL at re-entry. Before the clamp existed the rule held only because -100 x 0.30 lands at
## -30, one tuning nudge away from an unwinnable spawn.
func test_the_spawn_faction_cannot_stay_hostile_across_a_death() -> void:
	var village: FactionCoreComponent = _core_anchored_at_origin()
	ReputationSystem.adjust(village, WorldConstants.PLAYER_FACTION_ID, -100.0, &"MURDER")
	assert_eq(
		int(village.diplomacy[WorldConstants.PLAYER_FACTION_ID]["status"]),
		int(ECSEnums.RelationshipStatus.WAR),
		"they hate you when you die"
	)
	deaths.run_interregnum(null, null)
	assert_ne(
		int(village.diplomacy[WorldConstants.PLAYER_FACTION_ID]["status"]),
		int(ECSEnums.RelationshipStatus.WAR),
		"and the new adventurer is not born at war with their own doorstep"
	)


## A faction that is NOT the spawn faction keeps its decayed grudge — the floor is a spawn
## guarantee, not an amnesty.
func test_other_factions_keep_their_decayed_grudges() -> void:
	var rival: FactionCoreComponent = _core_anchored_at(Vector3i(3, 3, -1))
	ReputationSystem.adjust(rival, WorldConstants.PLAYER_FACTION_ID, -100.0, &"MURDER")
	deaths.run_interregnum(null, null)
	var score: float = ReputationSystem.relationship_score(
		rival, WorldConstants.PLAYER_FACTION_ID
	)
	assert_almost_eq(score, -100.0 * DeathLoopSystem.GRUDGE_RETAINED, 0.01)


## The swarm tax clamped a counter no production code ever raised, so `swarms_capped` was
## structurally zero in every session ever played. Breeding is the missing half.
func test_swarms_breed_geometrically_and_filth_feeds_them() -> void:
	var grid := WorldGrid.new(SEED)
	var dungeon: ChunkData = grid.chunk_at(Vector3i(0, 0, -1))
	dungeon.swarm_population = 3
	deaths._breed_swarms(grid)
	assert_eq(dungeon.swarm_population, 6, "a year of breeding doubles the swarm")


func test_the_swarm_cap_is_now_reachable_from_production_state() -> void:
	var grid := WorldGrid.new(SEED)
	var dungeon: ChunkData = grid.chunk_at(Vector3i(0, 0, -1))
	dungeon.swarm_population = 8
	deaths._breed_swarms(grid)
	deaths._cap_swarms(grid)
	assert_eq(
		dungeon.swarm_population, DeathLoopSystem.SWARM_CAP_PER_CHUNK,
		"breeding overflows the cap and the tax bites — with no test writing the counter"
	)
	assert_gt(deaths.swarms_capped, 0)


## Sprint 3 roadmap Step 6: the successor spawns at an Adventurer's Residence. It spawned at
## the previous body's start point, which reads as a reset rather than an arrival.
func test_worldgen_carves_the_residence_and_the_world_spawn_uses_it() -> void:
	var grid := WorldGrid.new(SEED)
	var home: ChunkData = grid.chunk_at(Vector3i.ZERO)
	var tile: Vector2i = FloorGenerator.RESIDENCE_TILE
	assert_false(home.is_solid(tile.x, tile.y), "the Residence interior is open ground")
	assert_true(
		home.is_solid(tile.x - FloorGenerator.RESIDENCE_HALF, tile.y),
		"inside a real building"
	)
	var spawn: Vector3 = World.residence_position(home)
	var expected: Vector3 = home.tile_to_world(tile.x, tile.y)
	assert_almost_eq(spawn.x, expected.x, 0.01, "and the world spawn is the Residence")
	assert_almost_eq(spawn.z, expected.z, 0.01)


func _core_anchored_at_origin() -> FactionCoreComponent:
	return _core_anchored_at(Vector3i.ZERO)


func _core_anchored_at(anchor: Vector3i) -> FactionCoreComponent:
	var row: int = EH.index_of(ECSManager.allocate_entity())
	var core := FactionCoreComponent.new()
	core.faction_id = 500 + row
	core.anchor_chunk_id = anchor
	ECSManager.faction_cores[row] = core
	ECSManager.add_component_bit(row, ComponentMask.FACTION_CORE)
	return core
