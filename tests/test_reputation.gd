## The consequence layer (Sprint 3.5).
##
## The reported symptom was "I killed some of them, oops — but I guess it doesn't matter much".
## It did not matter, and the reason was not missing machinery: `PerceptionSystem.report_crime`
## had been written and tested with NO CALLER, and nothing consumed the witnesses it produced.
## These tests pin every link of the chain, because a chain with one link missing behaves exactly
## like no chain at all.
extends GutTest

const SEED: int = 3535

var reputation: ReputationSystem
var village: FactionCoreComponent


func before_each() -> void:
	GameLoopManager.set_physics_process(false)
	World.boot_scenario(World.SCENARIO_WORLD, SEED)
	reputation = ReputationSystem.new()
	village = DAGInstantiator.faction_core(_village_faction_id())


func after_all() -> void:
	GameLoopManager.set_physics_process(true)


func _village_faction_id() -> int:
	for row in ECSManager.query(ComponentMask.FACTION_CORE):
		var core: FactionCoreComponent = ECSManager.faction_cores[row]
		if core.anchor_chunk_id == Vector3i.ZERO:
			return core.faction_id
	return -1


func _witness(action: StringName, confidence: float = 1.0) -> WitnessEvent:
	var villagers: Array[int] = FactionPlanner.members_of(village.faction_id)
	return WitnessEvent.create(
		ECSManager.handle_of(villagers[0]),
		ECSManager.player_handle(),
		action,
		ECSManager.position_of(0),
		GameClock.total_hours(),
		confidence
	)


# --- Grievances ---------------------------------------------------------------------------------

## THE HEADLINE. Killing someone in front of their neighbours has to cost you something.
func test_a_witnessed_murder_turns_a_faction_against_you() -> void:
	assert_almost_eq(
		ReputationSystem.relationship_score(village, WorldConstants.PLAYER_FACTION_ID),
		0.0, 0.01, "they start with no opinion of you"
	)
	reputation._record(_witness(&"MURDER"))
	assert_lt(
		ReputationSystem.relationship_score(village, WorldConstants.PLAYER_FACTION_ID),
		0.0,
		"and think considerably less of you afterwards"
	)
	assert_eq(reputation.grievances_recorded, 1, "the grievance was recorded")


## Severity has to be a scale, not a flag. A scale where everything is -10 cannot express
## escalation, and theft and murder stop being different decisions.
func test_murder_costs_far_more_than_theft() -> void:
	reputation._record(_witness(&"THEFT"))
	var after_theft: float = ReputationSystem.relationship_score(
		village, WorldConstants.PLAYER_FACTION_ID
	)
	reputation._record(_witness(&"MURDER"))
	var after_murder: float = ReputationSystem.relationship_score(
		village, WorldConstants.PLAYER_FACTION_ID
	)
	assert_lt(after_murder - after_theft, after_theft, "murder is the larger drop by far")


## A crime half-glimpsed at the edge of vision must not weigh the same as one in your face, or
## stealth stops meaning anything.
func test_confidence_scales_the_damage() -> void:
	reputation._record(_witness(&"MURDER", 0.1))
	var glimpsed: float = ReputationSystem.relationship_score(
		village, WorldConstants.PLAYER_FACTION_ID
	)
	assert_gt(glimpsed, ReputationSystem.SEVERITY[&"MURDER"] * 0.5, "a glimpse costs less")


func test_the_grievance_records_what_you_actually_did() -> void:
	reputation._record(_witness(&"MURDER"))
	var state: Dictionary = village.diplomacy[WorldConstants.PLAYER_FACTION_ID]
	assert_true(state["grievances"].has(&"MURDER"), "they remember it was murder")


## A grudge list that grows forever is a memory leak with a narrative excuse.
func test_the_grievance_list_is_bounded() -> void:
	for _crime in 40:
		reputation._record(_witness(&"THEFT"))
	var state: Dictionary = village.diplomacy[WorldConstants.PLAYER_FACTION_ID]
	assert_lte(state["grievances"].size(), 8, "old grudges fall off the end")


## Scores are clamped to the registry's -100..100 range, so no amount of murder can produce a
## number the rest of the system was not written to handle.
func test_the_score_cannot_run_past_its_bounds() -> void:
	for _crime in 20:
		reputation._record(_witness(&"MURDER"))
	assert_gte(
		ReputationSystem.relationship_score(village, WorldConstants.PLAYER_FACTION_ID),
		ReputationSystem.SCORE_MIN,
		"it bottoms out rather than running away"
	)


## Reputation is per faction PAIR. "The world hates you" is duller than "the village hates you
## and the goblins are delighted".
func test_one_factions_grudge_is_not_anothers() -> void:
	reputation._record(_witness(&"MURDER"))
	for row in ECSManager.query(ComponentMask.FACTION_CORE):
		var other: FactionCoreComponent = ECSManager.faction_cores[row]
		if other.faction_id == village.faction_id:
			continue
		assert_almost_eq(
			ReputationSystem.relationship_score(other, WorldConstants.PLAYER_FACTION_ID),
			0.0, 0.01, "faction %d neither saw nor cares" % other.faction_id
		)


## Internal crime is a schism problem, not a diplomacy one. A faction filing grievances against
## itself would turn every brawl into a war with nobody.
func test_a_faction_does_not_file_grievances_against_itself() -> void:
	var villagers: Array[int] = FactionPlanner.members_of(village.faction_id)
	var event: WitnessEvent = WitnessEvent.create(
		ECSManager.handle_of(villagers[0]),
		ECSManager.handle_of(villagers[1]),
		&"MURDER",
		Vector3.ZERO,
		GameClock.total_hours(),
		1.0
	)
	reputation._record(event)
	assert_eq(reputation.grievances_recorded, 0, "no grievance against your own people")


# --- Crossing into hostility ---------------------------------------------------------------------

func test_enough_crimes_make_a_faction_hostile() -> void:
	assert_false(
		ReputationSystem.is_hostile_to(village.faction_id, WorldConstants.PLAYER_FACTION_ID),
		"they start neutral"
	)
	for _crime in 3:
		reputation._record(_witness(&"MURDER"))
	assert_true(
		ReputationSystem.is_hostile_to(village.faction_id, WorldConstants.PLAYER_FACTION_ID),
		"three murders is enough"
	)
	assert_eq(reputation.factions_turned_hostile, 1, "and the crossing was reported ONCE")


## The threshold must fire on the crossing, not on every subsequent crime, or the feed fills with
## "now hostile" for a faction that has hated you for an hour.
func test_the_hostility_announcement_fires_once() -> void:
	for _crime in 10:
		reputation._record(_witness(&"MURDER"))
	assert_eq(reputation.factions_turned_hostile, 1, "announced when it changed, and not after")


## The reasoner has to ACT on it, or the whole chain ends in a number nobody reads.
func test_a_wronged_faction_fortifies() -> void:
	reputation._record(_witness(&"MURDER"))
	var context: Dictionary = PromptBuilder.build_context(village, null)
	assert_true(context["recently_attacked"], "the prompt knows something just happened")

	var answer: Dictionary = HeuristicProvider.new().decide(context)
	assert_eq(answer["objective"], "FORTIFY", "and the faction reacts by defending itself")


# --- Gossip ---------------------------------------------------------------------------------------

## Not a broadcast and not instant: a murder in a back alley should take time to reach the
## guards, and one in the square should not.
func test_gossip_reaches_someone_who_was_not_there() -> void:
	var villagers: Array[int] = FactionPlanner.members_of(village.faction_id)
	var teller: int = villagers[0]
	var listener: int = villagers[1]
	ECSManager.set_position(listener, ECSManager.position_of(teller) + Vector3(2.0, 0.0, 0.0))

	var record: MemoryEvent = MemoryEvent.create(&"WITNESSED_MURDER", &"MURDER", 0, true)
	ECSManager.memories[teller].remember(record)
	var before: int = ECSManager.memories[listener].events.size()

	var hash: SpatialHash = GameLoopManager.spatial_hash
	hash.rebuild(ECSManager.query(ComponentMask.SPATIAL))
	reputation.spread_gossip(hash)

	assert_gt(ECSManager.memories[listener].events.size(), before, "the neighbour heard about it")


## DEDUP BY event_id. Without it two neighbours re-tell each other the same story forever and
## every memory list grows without bound — which is why MemoryEvent carries a unique id at all.
func test_the_same_story_is_not_retold_forever() -> void:
	var villagers: Array[int] = FactionPlanner.members_of(village.faction_id)
	ECSManager.set_position(
		villagers[1], ECSManager.position_of(villagers[0]) + Vector3(2.0, 0.0, 0.0)
	)
	ECSManager.memories[villagers[0]].remember(
		MemoryEvent.create(&"WITNESSED_MURDER", &"MURDER", 0, true)
	)

	var hash: SpatialHash = GameLoopManager.spatial_hash
	for _tick in 12:
		hash.rebuild(ECSManager.query(ComponentMask.SPATIAL))
		reputation.spread_gossip(hash)

	var seen: Dictionary = {}
	for event in ECSManager.memories[villagers[1]].events:
		assert_false(seen.has(event.event_id), "no memory is stored twice")
		seen[event.event_id] = true


## Idle chat staying local is why memory lists across a village do not converge on identical
## contents. Only things that matter travel.
func test_only_core_memories_travel() -> void:
	var villagers: Array[int] = FactionPlanner.members_of(village.faction_id)
	ECSManager.set_position(
		villagers[1], ECSManager.position_of(villagers[0]) + Vector3(2.0, 0.0, 0.0)
	)
	ECSManager.memories[villagers[1]].events.clear()
	ECSManager.memories[villagers[0]].remember(
		MemoryEvent.create(&"IDLE_CHAT", &"weather", 0, false)
	)

	var hash: SpatialHash = GameLoopManager.spatial_hash
	hash.rebuild(ECSManager.query(ComponentMask.SPATIAL))
	reputation.spread_gossip(hash)
	assert_eq(
		ECSManager.memories[villagers[1]].events.size(), 0, "nobody repeats small talk"
	)


## Bounded per tick. A crowded village must not turn one murder into thousands of writes in a
## single Simulation tick.
func test_gossip_is_rate_limited() -> void:
	for row in FactionPlanner.members_of(village.faction_id):
		ECSManager.memories[row].remember(
			MemoryEvent.create(&"WITNESSED_MURDER", &"MURDER", 0, true)
		)
	var hash: SpatialHash = GameLoopManager.spatial_hash
	hash.rebuild(ECSManager.query(ComponentMask.SPATIAL))
	reputation.spread_gossip(hash)
	assert_lte(
		reputation.gossip_spread,
		ReputationSystem.MAX_GOSSIP_PER_TICK,
		"the per-tick budget holds"
	)


# --- The chain, joined up ---------------------------------------------------------------------

## `report_crime` was written, tested, and never called. A chain with one link missing behaves
## exactly like no chain at all, so this asserts combat actually reports.
func test_combat_reports_the_act_for_witnesses() -> void:
	var here: Vector3 = ECSManager.position_of(0)
	var rat: int = World.spawn_creature(here + Vector3(1.0, 0.0, 0.0))
	var rat_row: int = ECSManager.resolve(rat)
	GameLoopManager.combat.witnessed_actions.clear()

	GameLoopManager.combat.resolve_melee(0, rat_row, Vector3.RIGHT, 1.5)
	assert_gt(
		GameLoopManager.combat.witnessed_actions.size(),
		0,
		"the attack was reported as something that could be seen"
	)
	assert_eq(
		int(GameLoopManager.combat.witnessed_actions[0]["subject"]),
		0,
		"and names the attacker"
	)


func test_a_fatal_blow_is_reported_as_murder() -> void:
	var here: Vector3 = ECSManager.position_of(0)
	var rat: int = World.spawn_creature(here + Vector3(1.0, 0.0, 0.0))
	var rat_row: int = ECSManager.resolve(rat)
	ECSManager.bodies[rat_row].health = 0.5
	GameLoopManager.combat.witnessed_actions.clear()

	GameLoopManager.combat.resolve_melee(0, rat_row, Vector3.RIGHT, 1.5)
	assert_eq(
		GameLoopManager.combat.witnessed_actions[0]["action"],
		&"MURDER",
		"killing is murder; merely hitting is assault"
	)
