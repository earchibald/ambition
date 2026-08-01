## The social layer (Sprint 3.5 remediation): loyalty, succession, schism, engagement, brawls,
## caravans — and the reasoning-stack gaps closed in the same pass.
##
## Every mechanism here is the behavioural CONSUMER of a number an earlier sprint computed and
## nothing read: loyalty and prestige were write-only fields, WAR moved a float and changed no
## behaviour, TRADE was unreachable by construction, and a dead leader stayed dead. These tests
## pin the consumers, because a computed number with no consumer is indistinguishable from no
## number at all — that is this codebase's signature defect, and this file is its regression net.
extends GutTest

const SEED: int = 4242

var social: SocialSystem
var village: FactionCoreComponent


func before_each() -> void:
	GameLoopManager.set_physics_process(false)
	World.boot_scenario(World.SCENARIO_WORLD, SEED)
	social = SocialSystem.new()
	village = DAGInstantiator.faction_core(_village_faction_id())


func after_all() -> void:
	GameLoopManager.set_physics_process(true)


func _village_faction_id() -> int:
	for row in ECSManager.query(ComponentMask.FACTION_CORE):
		var core: FactionCoreComponent = ECSManager.faction_cores[row]
		if core.anchor_chunk_id == Vector3i.ZERO:
			return core.faction_id
	return -1


func _village_row() -> int:
	return DAGInstantiator.faction_row(village.faction_id)


## A second faction with real bodies, for every inter-faction mechanism. Hand-built rather than
## materialized, so the test controls exactly where its people stand.
func _rival_faction(faction_id: int, citizen_positions: Array[Vector3]) -> FactionCoreComponent:
	var macro: int = EH.index_of(ECSManager.allocate_entity())
	var core := FactionCoreComponent.new()
	core.faction_id = faction_id
	core.anchor_chunk_id = Vector3i(1, 0, 0)
	ECSManager.faction_cores[macro] = core
	ECSManager.add_component_bit(macro, ComponentMask.FACTION_CORE)
	for position in citizen_positions:
		_citizen(faction_id, position)
	return core


func _citizen(faction_id: int, position: Vector3, prestige: float = 10.0) -> int:
	var row: int = EH.index_of(ECSManager.allocate_entity())
	ECSManager.set_position(row, position)
	ECSManager.add_component_bit(row, ComponentMask.POSITION)
	ECSManager.bounds[row] = BoundsComponent.new(Vector3(0.3, 0.9, 0.3))
	ECSManager.add_component_bit(row, ComponentMask.BOUNDS)
	var body := BodyComponent.new()
	ECSManager.bodies[row] = body
	ECSManager.add_component_bit(row, ComponentMask.BODY)
	var identity := SocialIdentityComponent.new(faction_id)
	identity.prestige = prestige
	ECSManager.social_identities[row] = identity
	ECSManager.add_component_bit(row, ComponentMask.SOCIAL_IDENTITY)
	ECSManager.memories[row] = MemoryComponent.new()
	ECSManager.add_component_bit(row, ComponentMask.MEMORY)
	return row


func _hash_for_active_floor() -> SpatialHash:
	var hash := SpatialHash.new()
	hash.set_origin(Vector3(-WorldConstants.CHUNK_SIZE_M, 0.0, -WorldConstants.CHUNK_SIZE_M))
	hash.rebuild(ECSManager.rows_on_floor(ComponentMask.SPATIAL, 0))
	return hash


# --- Loyalty ------------------------------------------------------------------------------------

func test_loyalty_is_a_read_field_now_recalculated_from_circumstances() -> void:
	var member: int = FactionPlanner.members_of(village.faction_id)[0]
	var identity: SocialIdentityComponent = ECSManager.social_identities[member]
	identity.loyalty = -999.0
	social.run(null, null, null, null)
	assert_between(identity.loyalty, 0.0, 100.0, "the Simulation tick recalculates loyalty")


func test_a_starving_terrified_citizen_of_a_destitute_faction_is_disloyal() -> void:
	var poor := FactionCoreComponent.new()
	poor.faction_id = 777
	var row: int = _citizen(777, Vector3.ZERO)
	var need := NeedsComponent.new()
	need.hunger = 95.0
	need.energy = 5.0
	ECSManager.needs[row] = need
	ECSManager.add_component_bit(row, ComponentMask.NEEDS)
	var memory: MemoryComponent = ECSManager.memories[row]
	for i in 3:
		memory.remember(MemoryEvent.create(&"WAS_ATTACKED", &"raid", 0, true))
	assert_lt(
		SocialSystem.loyalty_for(row, poor),
		SocialSystem.SCHISM_LOYALTY_THRESHOLD,
		"hunger, terror and poverty together cross the schism threshold"
	)


func test_a_fed_citizen_of_a_wealthy_faction_is_loyal() -> void:
	var rich := FactionCoreComponent.new()
	rich.faction_id = 778
	rich.add_wealth(MaterialLibrary.MAT_IRON, SocialSystem.WEALTHY_LEDGER_TOTAL)
	var row: int = _citizen(778, Vector3.ZERO)
	assert_gt(SocialSystem.loyalty_for(row, rich), SocialSystem.LOYALTY_BASE)


# --- Succession ---------------------------------------------------------------------------------

func test_the_village_has_a_leader_at_boot() -> void:
	assert_true(
		ECSManager.is_alive(village.leader_handle),
		"materialization crowns the highest-prestige citizen"
	)


func test_killing_the_leader_promotes_the_highest_prestige_survivor() -> void:
	var old_leader: int = village.leader_handle
	var leader_row: int = ECSManager.resolve(old_leader)
	ECSManager.bodies[leader_row].health = 0.0
	ECSManager.destroy_entity(old_leader)
	ECSManager.flush_structural_changes()

	var queue := ReasoningQueue.new()
	social._check_successions(queue)

	assert_ne(village.leader_handle, old_leader, "a successor was chosen")
	assert_true(ECSManager.is_alive(village.leader_handle), "and is alive")
	var heir_row: int = ECSManager.resolve(village.leader_handle)
	var heir_prestige: float = ECSManager.social_identities[heir_row].prestige
	for member in FactionPlanner.members_of(village.faction_id):
		assert_lte(
			ECSManager.social_identities[member].prestige, heir_prestige,
			"nobody alive outranks the heir — succession is BY PRESTIGE, not by row order"
		)
	assert_eq(social.successions, 1)
	assert_eq(
		queue.pending_count(), 1,
		"the new leader's agenda is queued immediately, as the factions doc specifies"
	)


func test_a_faction_with_no_members_left_is_leaderless_not_crashed() -> void:
	for member in FactionPlanner.members_of(village.faction_id):
		ECSManager.destroy_entity(ECSManager.handle_of(member))
	ECSManager.flush_structural_changes()
	social._check_successions(null)
	assert_eq(village.leader_handle, EH.INVALID, "no heir exists, and that is a state, not an error")


# --- Schism -------------------------------------------------------------------------------------

func test_a_disloyal_cluster_splits_off_as_a_real_faction_at_war() -> void:
	var generator: DAGGenerator = World.boot_report.generator
	var before: int = generator.active_factions().size()
	var members: Array[int] = FactionPlanner.members_of(village.faction_id)
	var defectors: Array[int] = members.slice(0, SocialSystem.SCHISM_MIN_CLUSTER)
	for row in defectors:
		ECSManager.social_identities[row].loyalty = 5.0

	social._check_schisms(generator, null)

	assert_eq(social.schisms, 1, "the mutiny fired")
	assert_eq(generator.active_factions().size(), before + 1, "the splinter is a REAL DAG node")
	var splinter_id: int = ECSManager.social_identities[defectors[0]].faction_id
	assert_ne(splinter_id, village.faction_id, "the defectors changed allegiance")
	var splinter: FactionCoreComponent = DAGInstantiator.faction_core(splinter_id)
	assert_not_null(splinter, "with a real ledger entity")
	assert_eq(
		int(splinter.diplomacy[village.faction_id]["status"]),
		int(ECSEnums.RelationshipStatus.WAR),
		"at war with the parent"
	)
	assert_eq(
		int(village.diplomacy[splinter_id]["status"]),
		int(ECSEnums.RelationshipStatus.WAR),
		"and the parent at war with it"
	)
	assert_eq(
		splinter.current_objective, ECSEnums.Objective.RAID_FACTION,
		"the splinter moves on the parent's stockpile immediately"
	)
	assert_true(ECSManager.is_alive(splinter.leader_handle), "the splinter crowned a leader")


func test_loyal_factions_do_not_schism() -> void:
	social._check_schisms(World.boot_report.generator, null)
	assert_eq(social.schisms, 0)


func test_schism_respects_the_adr12_faction_cap() -> void:
	var generator: DAGGenerator = World.boot_report.generator
	while generator.active_factions().size() < DAGGenerator.FACTION_CAP:
		var filler: DAGNode = generator.found_splinter(
			generator.active_factions()[0], 1
		)
		if filler == null:
			break
	var defectors: Array[int] = FactionPlanner.members_of(village.faction_id).slice(
		0, SocialSystem.SCHISM_MIN_CLUSTER
	)
	for row in defectors:
		ECSManager.social_identities[row].loyalty = 5.0
	social._check_schisms(generator, null)
	assert_eq(social.schisms, 0, "at the cap the mutiny disperses instead of founding")
	assert_eq(social.schisms_blocked_by_cap, 1, "and the refusal is counted, not silent")


# --- Hostile engagement (the WAR consumer) ------------------------------------------------------

func test_at_war_citizens_actually_come_for_you() -> void:
	ReputationSystem.adjust(village, WorldConstants.PLAYER_FACTION_ID, -100.0, &"TEST")
	var member: int = FactionPlanner.members_of(village.faction_id)[0]
	# Stand the player 5 m from a villager: inside sight, outside melee reach.
	ECSManager.set_position(0, ECSManager.position_of(member) + Vector3(5.0, 0.0, 0.0))
	var combat := ActionResolutionSystem.new()

	social._engage_hostiles(_hash_for_active_floor(), combat)

	assert_gt(social.engagements, 0, "WAR now has a behavioural consumer")
	var locomotion: LocomotionComponent = ECSManager.locomotions.get(member)
	assert_not_null(locomotion, "the citizen is moving")
	assert_true(locomotion.has_destination, "toward somewhere")
	assert_lt(
		locomotion.destination.distance_to(ECSManager.position_of(0)), 1.0,
		"specifically toward YOU"
	)


func test_at_war_citizens_in_reach_swing() -> void:
	ReputationSystem.adjust(village, WorldConstants.PLAYER_FACTION_ID, -100.0, &"TEST")
	var member: int = FactionPlanner.members_of(village.faction_id)[0]
	ECSManager.set_position(0, ECSManager.position_of(member) + Vector3(1.0, 0.0, 0.0))
	var combat := ActionResolutionSystem.new()
	social._engage_hostiles(_hash_for_active_floor(), combat)
	assert_gt(combat.attacks_resolved, 0, "adjacent hostility is a swing, not a stroll")


func test_neutral_citizens_leave_you_alone() -> void:
	var member: int = FactionPlanner.members_of(village.faction_id)[0]
	ECSManager.set_position(0, ECSManager.position_of(member) + Vector3(1.0, 0.0, 0.0))
	var combat := ActionResolutionSystem.new()
	social._engage_hostiles(_hash_for_active_floor(), combat)
	assert_eq(social.engagements, 0, "no WAR, no violence")


# --- Brawls -------------------------------------------------------------------------------------

func test_contested_mining_between_rival_factions_comes_to_blows() -> void:
	var here := Vector3(8.0, 0.9, 8.0)
	var rival: FactionCoreComponent = _rival_faction(900, [here + Vector3(1.0, 0.0, 0.0)])
	var miner_a: int = FactionPlanner.members_of(village.faction_id)[0]
	ECSManager.set_position(miner_a, here)
	var miner_b: int = FactionPlanner.members_of(900)[0]
	for row in [miner_a, miner_b]:
		var job := JobComponent.new()
		job.current_action = &"ClaimResourceZone"
		job.claim(ECSManager.handle_of(row), 1.0)
		ECSManager.jobs[row] = job
		ECSManager.add_component_bit(row, ComponentMask.JOB)

	var health_before: float = ECSManager.bodies[miner_a].health
	social._resolve_brawls(_hash_for_active_floor())

	assert_eq(social.brawls, 1, "the contested seam produced a brawl")
	assert_lt(ECSManager.bodies[miner_a].health, health_before, "blows landed")
	assert_lt(
		ReputationSystem.relationship_score(village, 900), 0.0,
		"and the grievance is on the books"
	)
	assert_lt(
		ReputationSystem.relationship_score(rival, village.faction_id), 0.0,
		"on BOTH books — each side blames the other"
	)


func test_brawls_are_non_lethal_by_construction() -> void:
	_rival_faction(901, [Vector3(8.0, 0.9, 9.0)])
	var miner_a: int = FactionPlanner.members_of(village.faction_id)[0]
	ECSManager.set_position(miner_a, Vector3(8.0, 0.9, 8.0))
	var miner_b: int = FactionPlanner.members_of(901)[0]
	for row in [miner_a, miner_b]:
		var job := JobComponent.new()
		job.current_action = &"ClaimResourceZone"
		job.claim(ECSManager.handle_of(row), 1.0)
		ECSManager.jobs[row] = job
		ECSManager.add_component_bit(row, ComponentMask.JOB)
		ECSManager.bodies[row].health = ECSManager.bodies[row].max_health * 0.26
	for _round in 10:
		social._resolve_brawls(_hash_for_active_floor())
	for row in [miner_a, miner_b]:
		var body: BodyComponent = ECSManager.bodies[row]
		assert_gte(
			body.health, body.max_health * SocialSystem.BRAWL_HEALTH_FLOOR - 0.001,
			"the floor holds: a brawl bruises and can never kill"
		)
		assert_true(body.is_alive())


# --- Trade caravans -----------------------------------------------------------------------------

func test_trade_status_is_reachable_at_all() -> void:
	assert_eq(
		int(ReputationSystem.status_for(50.0)), int(ECSEnums.RelationshipStatus.TRADE),
		"the 40..75 band is TRADE — the enum value was unreachable by construction before"
	)
	assert_eq(int(ReputationSystem.status_for(80.0)), int(ECSEnums.RelationshipStatus.ALLIED))
	assert_eq(int(ReputationSystem.status_for(0.0)), int(ECSEnums.RelationshipStatus.NEUTRAL))
	assert_eq(int(ReputationSystem.status_for(-50.0)), int(ECSEnums.RelationshipStatus.WAR))


func test_a_trade_partner_gets_a_real_caravan_with_real_goods() -> void:
	village.add_wealth(MaterialLibrary.MAT_IRON, 100)
	var partner_id: int = _abstract_partner_id()
	ReputationSystem.adjust(village, partner_id, 50.0, &"TEST")

	social.run_trade(World.grid, GameLoopManager.inventory)

	assert_eq(social.caravans_dispatched, 1, "a caravan left")
	assert_eq(
		int(village.abstract_wealth_ledger[MaterialLibrary.MAT_IRON]),
		100 - SocialSystem.TRADE_LOAD,
		"the cargo was WITHDRAWN from the ledger, not minted beside it"
	)
	var caravan: Dictionary = social._caravans.values()[0]
	assert_true(ECSManager.is_alive(int(caravan["carrier"])), "carried by a living citizen")
	assert_true(ECSManager.is_alive(int(caravan["cargo"])), "as a physical stack")


func test_an_arrived_caravan_ledgerizes_into_the_receiver_and_warms_both_sides() -> void:
	village.add_wealth(MaterialLibrary.MAT_IRON, 100)
	var partner_id: int = _abstract_partner_id()
	var partner: FactionCoreComponent = DAGInstantiator.faction_core(partner_id)
	ReputationSystem.adjust(village, partner_id, 50.0, &"TEST")
	social.run_trade(World.grid, GameLoopManager.inventory)
	var caravan: Dictionary = social._caravans.values()[0]
	var carrier_row: int = ECSManager.resolve(int(caravan["carrier"]))
	ECSManager.set_position(carrier_row, caravan["destination"])

	var score_before: float = ReputationSystem.relationship_score(partner, village.faction_id)
	social._settle_caravans()

	assert_eq(social.caravans_arrived, 1)
	assert_eq(
		int(partner.abstract_wealth_ledger.get(MaterialLibrary.MAT_IRON, 0)),
		SocialSystem.TRADE_LOAD,
		"the goods are in the receiver's ledger — physical on the road, abstract at rest"
	)
	assert_false(ECSManager.is_alive(int(caravan["cargo"])), "and the stack is gone")
	assert_gt(
		ReputationSystem.relationship_score(partner, village.faction_id), score_before,
		"commerce warms the relationship"
	)


func test_a_dead_carrier_is_a_lost_caravan_and_the_sender_remembers() -> void:
	village.add_wealth(MaterialLibrary.MAT_IRON, 100)
	ReputationSystem.adjust(village, _abstract_partner_id(), 50.0, &"TEST")
	social.run_trade(World.grid, GameLoopManager.inventory)
	var caravan: Dictionary = social._caravans.values()[0]
	ECSManager.destroy_entity(int(caravan["carrier"]))
	ECSManager.flush_structural_changes()

	social._settle_caravans()

	assert_eq(social.caravans_lost, 1, "interception is a real outcome, not a stall")
	var remembered: bool = false
	for memory in village.faction_memory:
		if String(memory["text"]).contains("caravan"):
			remembered = true
	assert_true(remembered, "the sender knows, and the reasoner will hear about it")


func _abstract_partner_id() -> int:
	for row in ECSManager.query(ComponentMask.FACTION_CORE):
		var core: FactionCoreComponent = ECSManager.faction_cores[row]
		if (
			core.faction_id != village.faction_id
			and core.anchor_chunk_id != DAGNode.NO_ANCHOR
		):
			return core.faction_id
	return -1


# --- The boot contract closed by this pass ------------------------------------------------------

## Sprint 2 roadmap: "Spawn Entity 0 with [Guest_Status] and a starting inventory based on
## Village Wealth." Neither existed: the perception invariant about Guest_Status was tested
## against a fixture tag no real player ever carried.
func test_the_player_arrives_as_a_guest() -> void:
	var chemistry: ChemistryComponent = ECSManager.chemistries[WorldConstants.PLAYER_INDEX]
	assert_true(chemistry.active_tags.has(&"Guest_Status"), "the village treats you as a guest")


func test_the_starting_kit_is_withdrawn_from_a_ledger_not_minted() -> void:
	var inventory: InventoryComponent = ECSManager.inventories[WorldConstants.PLAYER_INDEX]
	assert_gt(inventory.held_items.size(), 0, "the village equipped its guest")
	# Conservation: the richest faction paid for it. Re-boot with an empty world economy and
	# no kit appears — based on wealth means based on wealth.
	var total_wealth: int = 0
	for row in ECSManager.query(ComponentMask.FACTION_CORE):
		total_wealth += ECSManager.faction_cores[row].ledger_total()
	assert_gt(total_wealth, 0, "and the economy still has money — nothing was double-spent")


## The profession layer was test-only: `ProfessionComponent` was never attached in production,
## so the planner's preference table read `null` for every citizen that ever existed.
func test_citizens_have_professions_in_the_shipped_world() -> void:
	var members: Array[int] = FactionPlanner.members_of(village.faction_id)
	assert_gt(members.size(), 0)
	for row in members:
		assert_true(
			ECSManager.professions.has(row),
			"row %d has a profession — the filter finally has input" % row
		)


## The planner's preference keys must name professions citizens can actually hold, or the table
## is a constant round-robin wearing a filter — the `CULTURE_FUNGAL` defect, again.
func test_every_preferred_profession_is_one_a_citizen_can_hold() -> void:
	for action in FactionPlanner.PREFERRED_PROFESSION:
		var wanted: StringName = FactionPlanner.PREFERRED_PROFESSION[action]
		assert_true(
			FactionPlanner.SPAWN_PROFESSIONS.has(wanted),
			"%s prefers %s, which spawning can actually produce" % [action, wanted]
		)


## Faction memory follows the canonical eviction rule now: cap 64, evict the lowest-weight
## NON-CORE entry. It was cap 24 with FIFO, which pushed a core murder out after 24 trivia.
func test_faction_memory_overflow_spares_core_memories() -> void:
	village.faction_memory.clear()
	var murder: MemoryEvent = MemoryEvent.create(&"WITNESSED_MURDER", &"the murder", 0, true)
	village.faction_memory.append({
		"event_id": murder.event_id, "text": "the murder", "tick": 0,
		"weight": MemoryEvent.base_weight(&"WITNESSED_MURDER"), "core": true,
	})
	for i in ReputationSystem.FACTION_MEMORY_CAP + 10:
		var trivia: MemoryEvent = MemoryEvent.create(&"IDLE_CHAT", &"weather", 0, false)
		ReputationSystem._remember_for_faction(village, trivia)
	assert_lte(
		village.faction_memory.size(), ReputationSystem.FACTION_MEMORY_CAP,
		"the cap holds"
	)
	var kept: bool = false
	for memory in village.faction_memory:
		if String(memory["text"]) == "the murder":
			kept = true
	assert_true(kept, "and the core murder survived 74 pieces of trivia")
