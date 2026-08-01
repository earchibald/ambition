## Intra- and inter-faction dynamics (Sprint 3.5, factions doc §3-§4): loyalty, succession,
## schism, hostile engagement, brawls, and trade caravans.
##
## This system is why the consequence layer has CONSEQUENCES. Before it existed the build could
## move a relationship score and could do nothing about it: WAR was a word on the F1 page, a
## dead leader stayed dead with no successor, loyalty and prestige were fields nothing read, and
## the TRADE status was unreachable by construction. Every mechanism here is the behavioural
## consumer of a number some earlier sprint already computed.
##
## Runs on the Simulation tick (people-scale decisions), except trade, which runs on the Macro
## tick (an hour-scale economy does not need 2 Hz caravan dispatch).
class_name SocialSystem
extends RefCounted

# --- Loyalty (factions doc §3: needs, memory, faction wealth). The doc names the inputs and
# no numbers; these are the recorded choices. Base 50, clamped 0..100.
const LOYALTY_BASE: float = 50.0
const LOYALTY_STARVING: float = -20.0
const LOYALTY_EXHAUSTED: float = -10.0
## Per violent memory, and the cap. "Constantly fleeing in terror" is the doc's phrase; three
## remembered horrors is constant enough.
const LOYALTY_PER_TERROR: float = -8.0
const LOYALTY_TERROR_FLOOR: float = -24.0
const LOYALTY_WEALTHY: float = 10.0
const LOYALTY_DESTITUTE: float = -10.0
const WEALTHY_LEDGER_TOTAL: int = 500

# --- Schism (factions doc §3: "a large cluster of Tier 2 entities drops below a Loyalty
# Threshold (e.g., 20/100)").
const SCHISM_LOYALTY_THRESHOLD: float = 20.0
const SCHISM_MIN_CLUSTER: int = 4

# --- Hostile engagement (factions doc §4: WAR-status entities engage on sight).
const ENGAGE_SIGHT_M: float = 10.0
const MELEE_REACH_M: float = 1.5
## Engagements started per Simulation tick, across the world. Bounded so a two-village war is a
## running skirmish rather than a single-tick bloodbath the player never sees develop.
const ENGAGEMENTS_PER_TICK: int = 8

# --- Brawls (factions doc §4: contested resources between non-allied factions; "non-lethal or
# low-lethal"). The health floor is what makes them non-lethal BY CONSTRUCTION rather than by
# damage tuning: a brawl can beat someone to a quarter of their health and never further.
const BRAWL_RADIUS_M: float = 3.0
const BRAWL_DAMAGE: float = 4.0
const BRAWL_HEALTH_FLOOR: float = 0.25
const BRAWL_SEVERITY: float = -6.0
const BRAWLS_PER_TICK: int = 4

# --- Trade caravans (factions doc §4). One caravan per directed faction pair at a time.
const TRADE_LOAD: int = 20
const TRADE_GOODWILL: float = 4.0
const CARAVAN_ARRIVE_M: float = 3.0

var loyalty_updates: int = 0
var successions: int = 0
var schisms: int = 0
var schisms_blocked_by_cap: int = 0
var engagements: int = 0
var brawls: int = 0
var caravans_dispatched: int = 0
var caravans_arrived: int = 0
var caravans_lost: int = 0
var trespasses: int = 0

## "from:to" -> {carrier, cargo, material, quantity, from_faction, to_faction, destination}.
var _caravans: Dictionary = {}
## The trespass drip throttle: last in-game hour a grievance was filed.
var _last_trespass_hour: int = -1


## The Simulation-tick pass. Order matters: loyalty first (schism reads it), succession before
## schism (a splinter needs a crowned parent to hate), engagement last (it acts on WAR states
## the earlier steps may have just created).
func run(
	hash: SpatialHash,
	generator: DAGGenerator,
	reasoning: ReasoningQueue,
	combat: ActionResolutionSystem
) -> void:
	_recalculate_loyalty()
	_check_successions(reasoning)
	_check_schisms(generator, reasoning)
	_engage_hostiles(hash, combat)
	_resolve_brawls(hash)
	_check_trespass()


## THE CLAIMTAG CONSUMER (factions doc §4: "factions exert influence over zones via ClaimTags").
## Standing on claimed ground WITHOUT Guest_Status files a slow drip of TRESPASS grievances —
## which is what makes a claim a fact with consequences rather than a field nothing reads. The
## drip is throttled to one grievance per in-game hour: territory is a pressure, not a mugging.
## Guests are welcome, and a guest stays a guest until someone SEES them commit a crime
## (`ReputationSystem` revokes the tag on a witnessed offence).
func _check_trespass() -> void:
	var chunk: ChunkData = World.active_chunk
	if chunk == null or chunk.claim_faction_id < 0:
		return
	var owner: FactionCoreComponent = DAGInstantiator.faction_core(chunk.claim_faction_id)
	if owner == null:
		return
	var chemistry: ChemistryComponent = ECSManager.chemistries.get(WorldConstants.PLAYER_INDEX)
	if chemistry != null and chemistry.has_tag(&"Guest_Status"):
		return
	if _at_war(owner, WorldConstants.PLAYER_FACTION_ID):
		# Already shooting; a trespass complaint on top is bookkeeping nobody needs.
		return
	var now: int = GameClock.total_hours()
	if now - _last_trespass_hour < 1:
		return
	_last_trespass_hour = now
	ReputationSystem.adjust(
		owner, WorldConstants.PLAYER_FACTION_ID,
		ReputationSystem.SEVERITY[&"TRESPASS"], &"TRESPASS"
	)
	trespasses += 1


## Loyalty is RECALCULATED, not accumulated (factions doc §3): it is a statement about the
## citizen's present circumstances, so it must be able to recover the moment the famine ends.
func _recalculate_loyalty() -> void:
	for row in ECSManager.query(ComponentMask.SOCIAL_IDENTITY):
		if row == WorldConstants.PLAYER_INDEX:
			continue
		var identity: SocialIdentityComponent = ECSManager.social_identities[row]
		var core: FactionCoreComponent = DAGInstantiator.faction_core(identity.faction_id)
		if core == null:
			continue
		identity.loyalty = loyalty_for(row, core)
		loyalty_updates += 1


## Pure and public, so a test can assert the arithmetic without running the world.
static func loyalty_for(row: int, core: FactionCoreComponent) -> float:
	var value: float = LOYALTY_BASE
	var need: NeedsComponent = ECSManager.needs.get(row)
	if need != null:
		if need.hunger > 80.0:
			value += LOYALTY_STARVING
		if need.energy < 20.0:
			value += LOYALTY_EXHAUSTED
	var memory: MemoryComponent = ECSManager.memories.get(row)
	if memory != null:
		var terror: float = 0.0
		for event in memory.events:
			if event.kind == &"WAS_ATTACKED" or event.kind == &"WITNESSED_MURDER":
				terror += LOYALTY_PER_TERROR
		value += maxf(LOYALTY_TERROR_FLOOR, terror)
	var total: int = core.ledger_total()
	if total >= WEALTHY_LEDGER_TOTAL:
		value += LOYALTY_WEALTHY
	elif total == 0:
		value += LOYALTY_DESTITUTE
	return clampf(value, 0.0, 100.0)


## Succession (factions doc §3, the row the Sprint 3.5 audit called "the most damning"): when a
## leader dies, the highest-prestige member is promoted and a Reasoning Tick is queued
## IMMEDIATELY at crisis priority, so the new agenda ("avenge" or "sue for peace") is the next
## thought the queue serves. A leaderless faction WITH members is also crowned — that is how a
## fresh splinter, or a faction whose citizens materialized after boot, gets its first leader.
func _check_successions(reasoning: ReasoningQueue) -> void:
	for row in ECSManager.query(ComponentMask.FACTION_CORE):
		var core: FactionCoreComponent = ECSManager.faction_cores[row]
		var had_leader: bool = core.leader_handle != EH.INVALID
		if had_leader and ECSManager.is_alive(core.leader_handle):
			continue
		var heir: int = _highest_prestige_member(core.faction_id)
		if heir < 0:
			core.leader_handle = EH.INVALID
			continue
		core.leader_handle = ECSManager.handle_of(heir)
		var identity: SocialIdentityComponent = ECSManager.social_identities[heir]
		# Only a DEATH is a succession. First crownings are quiet: forty villages announcing
		# their day-one leaders is noise wearing a mechanic's name.
		if had_leader:
			successions += 1
			_remember_for_faction(core, &"SUCCESSION", "A new leader rose by prestige")
			if reasoning != null:
				reasoning.submit(ECSManager.handle_of(row), ReasoningQueue.PRIORITY_CRISIS)
			ECSEvents.faction_leader_succeeded.emit(
				core.faction_id, core.leader_handle, identity.prestige
			)


## Highest prestige wins; the tie-break is the lowest row, so identical prestige cannot pick
## different leaders run to run (ADR-20).
static func _highest_prestige_member(faction_id: int) -> int:
	var best: int = -1
	var best_prestige: float = -1.0
	for row in FactionPlanner.members_of(faction_id):
		var identity: SocialIdentityComponent = ECSManager.social_identities[row]
		if identity.prestige > best_prestige:
			best_prestige = identity.prestige
			best = row
	return best


## The Schism Mechanic (factions doc §3). A cluster of members below the loyalty threshold
## breaks away as a REAL faction: a DAG node with a FOUNDED edge, a macro-entity ledger, WAR in
## both directions, and an immediate objective against the parent — "attempt to seize the
## nearest stockpile" is expressed as RAID_FACTION targeted at the faction that owns it.
func _check_schisms(generator: DAGGenerator, reasoning: ReasoningQueue) -> void:
	if generator == null:
		return
	# Snapshot: a schism allocates a new faction core mid-iteration.
	var core_rows: Array[int] = []
	for row in ECSManager.query(ComponentMask.FACTION_CORE):
		core_rows.append(row)
	for row in core_rows:
		var core: FactionCoreComponent = ECSManager.faction_cores[row]
		var defectors: Array[int] = []
		for member in FactionPlanner.members_of(core.faction_id):
			if ECSManager.social_identities[member].loyalty < SCHISM_LOYALTY_THRESHOLD:
				defectors.append(member)
		if defectors.size() < SCHISM_MIN_CLUSTER:
			continue
		var parent_node: DAGNode = generator.node_by_id(core.faction_id)
		if parent_node == null:
			continue
		var splinter_node: DAGNode = generator.found_splinter(parent_node, defectors.size())
		if splinter_node == null:
			# ADR-12: at the faction cap the mutiny disperses instead of founding. Counted,
			# because "the cap held" and "schism is broken" look identical from outside.
			schisms_blocked_by_cap += 1
			continue
		_found_splinter_core(splinter_node, core, defectors, reasoning)


func _found_splinter_core(
	splinter_node: DAGNode,
	parent: FactionCoreComponent,
	defectors: Array[int],
	reasoning: ReasoningQueue
) -> void:
	var handle: int = ECSManager.allocate_entity()
	var macro_row: int = EH.index_of(handle)
	var splinter: FactionCoreComponent = FactionCoreComponent.from_dag_node(splinter_node)
	ECSManager.faction_cores[macro_row] = splinter
	ECSManager.add_component_bit(macro_row, ComponentMask.FACTION_CORE)

	for member in defectors:
		var identity: SocialIdentityComponent = ECSManager.social_identities[member]
		identity.faction_id = splinter_node.node_id
		# Mutiny is a fresh start: the grievance was against the OLD faction, and carrying the
		# disloyalty over would make the splinter schism from itself four ticks later.
		identity.loyalty = 60.0

	# "They immediately gain a status: War with their former faction." Both directions, at the
	# score floor — this is not a disagreement, it is a mutiny.
	ReputationSystem.adjust(parent, splinter_node.node_id, ReputationSystem.SCORE_MIN, &"SCHISM")
	ReputationSystem.adjust(splinter, parent.faction_id, ReputationSystem.SCORE_MIN, &"SCHISM")
	splinter.current_objective = ECSEnums.Objective.RAID_FACTION
	splinter.objective_target = parent.faction_id
	_remember_for_faction(parent, &"SCHISM", "Our own people rose against us")

	var heir: int = _highest_prestige_member(splinter_node.node_id)
	if heir >= 0:
		splinter.leader_handle = ECSManager.handle_of(heir)
	if reasoning != null:
		reasoning.submit(handle, ReasoningQueue.PRIORITY_CRISIS)

	schisms += 1
	ECSEvents.faction_schism.emit(parent.faction_id, splinter_node.node_id, defectors.size())


## THE WAR CONSUMER (factions doc §4: "At War status, Tier 2 guards will attack the player on
## sight"; engagement rules doc: shift to combat when a WAR entity enters vision). Before this
## pass existed, WAR moved a float and printed a feed line, and the village never turned on
## anyone — `is_hostile_to` had no production caller.
func _engage_hostiles(hash: SpatialHash, combat: ActionResolutionSystem) -> void:
	if hash == null or combat == null:
		return
	var budget: int = ENGAGEMENTS_PER_TICK
	for row in ECSManager.query(ComponentMask.SOCIAL_IDENTITY):
		if budget <= 0:
			return
		if row == WorldConstants.PLAYER_INDEX:
			continue
		var identity: SocialIdentityComponent = ECSManager.social_identities[row]
		var core: FactionCoreComponent = DAGInstantiator.faction_core(identity.faction_id)
		if core == null:
			continue
		var body: BodyComponent = ECSManager.bodies.get(row)
		if body == null or not body.is_alive():
			continue
		var position: Vector3 = ECSManager.position_of(row)
		var neighbours: PackedInt32Array = hash.query_radius(position, ENGAGE_SIGHT_M)
		for i in neighbours.size():
			var other: int = neighbours[i]
			if other == row:
				continue
			var other_faction: int = _faction_of(other)
			if other_faction < 0 or other_faction == identity.faction_id:
				continue
			if not _at_war(core, other_faction):
				continue
			var target_body: BodyComponent = ECSManager.bodies.get(other)
			if target_body == null or not target_body.is_alive():
				continue
			var target_position: Vector3 = ECSManager.position_of(other)
			if position.distance_to(target_position) <= MELEE_REACH_M:
				combat.resolve_melee(row, other, target_position - position, MELEE_REACH_M)
			else:
				LocomotionSystem.send_to(row, target_position)
			engagements += 1
			budget -= 1
			break


## Brawls (factions doc §4): workers of different, non-allied factions contesting the same
## ground trade non-lethal blows and both sides file grievances. This is the mechanism that
## lets two neutral factions drift toward war through friction rather than through a decree.
func _resolve_brawls(hash: SpatialHash) -> void:
	if hash == null:
		return
	var miners: Array[int] = []
	for row in ECSManager.query(ComponentMask.JOB):
		var job: JobComponent = ECSManager.jobs[row]
		if job.current_action == &"ClaimResourceZone" and job.is_latched():
			miners.append(row)
	var budget: int = BRAWLS_PER_TICK
	for i in miners.size():
		if budget <= 0:
			return
		for j in range(i + 1, miners.size()):
			var a: int = miners[i]
			var b: int = miners[j]
			var faction_a: int = _faction_of(a)
			var faction_b: int = _faction_of(b)
			if faction_a < 0 or faction_b < 0 or faction_a == faction_b:
				continue
			var core_a: FactionCoreComponent = DAGInstantiator.faction_core(faction_a)
			var core_b: FactionCoreComponent = DAGInstantiator.faction_core(faction_b)
			if core_a == null or core_b == null:
				continue
			if _allied(core_a, faction_b) or _allied(core_b, faction_a):
				continue
			var gap: float = ECSManager.position_of(a).distance_to(ECSManager.position_of(b))
			if gap > BRAWL_RADIUS_M:
				continue
			_brawl(a, b)
			ReputationSystem.adjust(core_a, faction_b, BRAWL_SEVERITY, &"BRAWL")
			ReputationSystem.adjust(core_b, faction_a, BRAWL_SEVERITY, &"BRAWL")
			brawls += 1
			budget -= 1
			break


## Bruises, never corpses. The floor is the non-lethality guarantee: whatever the damage
## constant is tuned to, a brawl cannot take the last three-quarters of anyone's health.
func _brawl(a: int, b: int) -> void:
	for row in [a, b]:
		var body: BodyComponent = ECSManager.bodies.get(row)
		if body == null:
			continue
		body.health = maxf(body.max_health * BRAWL_HEALTH_FLOOR, body.health - BRAWL_DAMAGE)


## The Macro-tick trade pass (factions doc §4): factions at TRADE or ALLIED status send real
## caravans — a living hauler, carrying a real stack withdrawn from the home ledger, walking to
## the ally's chunk. The walk is the mechanic: between departure and arrival the cargo exists
## physically, which is what makes it interceptable by the player or a hostile faction.
func run_trade(grid: WorldGrid, inventory: InventorySystem) -> void:
	if grid == null:
		return
	_settle_caravans()
	for row in ECSManager.query(ComponentMask.FACTION_CORE):
		var core: FactionCoreComponent = ECSManager.faction_cores[row]
		for other_id in core.diplomacy:
			var status: ECSEnums.RelationshipStatus = core.diplomacy[other_id]["status"]
			if (
				status != ECSEnums.RelationshipStatus.TRADE
				and status != ECSEnums.RelationshipStatus.ALLIED
			):
				continue
			_dispatch_caravan(core, int(other_id), grid, inventory)


func _dispatch_caravan(
	core: FactionCoreComponent, to_faction: int, grid: WorldGrid, inventory: InventorySystem
) -> void:
	var key: String = "%d:%d" % [core.faction_id, to_faction]
	if _caravans.has(key):
		return
	var ally: FactionCoreComponent = DAGInstantiator.faction_core(to_faction)
	if ally == null or ally.anchor_chunk_id == DAGNode.NO_ANCHOR:
		return
	var carrier: int = _idle_hauler(core.faction_id)
	if carrier < 0:
		return
	var material: StringName = _richest_material(core)
	if material == &"":
		return
	var quantity: int = core.withdraw(material, TRADE_LOAD)
	if quantity <= 0:
		return

	# The cargo is a real stack in the carrier's pack, not a note on a ledger — killing the
	# carrier drops it, which is the entire "physically interceptable" requirement.
	_ensure_pack(carrier)
	var cargo: int = World.spawn_item(
		ECSManager.position_of(carrier), material, 112.0, quantity
	)
	if not inventory.try_insert(carrier, cargo):
		# Cargo would not fit: put the wealth back and try again next hour. Withdraw-then-refund
		# keeps the ledger conserved on every path out of this function.
		core.add_wealth(material, quantity)
		ECSManager.destroy_entity(cargo)
		return

	var landing: ChunkData = grid.chunk_at(ally.anchor_chunk_id)
	var destination: Vector3 = World.spawn_position_in(landing)
	var job: JobComponent = ECSManager.jobs.get(carrier)
	if job == null:
		job = JobComponent.new()
		ECSManager.jobs[carrier] = job
		ECSManager.add_component_bit(carrier, ComponentMask.JOB)
	job.release()
	job.current_action = &"TradeMission"
	job.target_location = destination
	job.claim(ECSManager.handle_of(carrier), FactionPlanner.PLANNER_CLAIM_SCORE)
	LocomotionSystem.send_to(carrier, destination)

	_caravans[key] = {
		"carrier": ECSManager.handle_of(carrier),
		"cargo": cargo,
		"material": material,
		"quantity": quantity,
		"from_faction": core.faction_id,
		"to_faction": to_faction,
		"destination": destination,
	}
	caravans_dispatched += 1
	ECSEvents.caravan_departed.emit(core.faction_id, to_faction, ECSManager.handle_of(carrier))


## Arrivals and losses, checked once per Macro tick. A dead carrier is a LOST caravan — the
## cargo is wherever the corpse is, which is the point — and the sender remembers it.
func _settle_caravans() -> void:
	for key in _caravans.keys().duplicate():
		var caravan: Dictionary = _caravans[key]
		var sender: FactionCoreComponent = DAGInstantiator.faction_core(
			int(caravan["from_faction"])
		)
		if not ECSManager.is_alive(int(caravan["carrier"])):
			caravans_lost += 1
			if sender != null:
				_remember_for_faction(sender, &"CARAVAN_LOST", "Our caravan never arrived")
			ECSEvents.caravan_lost.emit(
				int(caravan["from_faction"]), int(caravan["to_faction"])
			)
			_caravans.erase(key)
			continue
		var row: int = ECSManager.resolve(int(caravan["carrier"]))
		var gap: float = ECSManager.position_of(row).distance_to(caravan["destination"])
		if gap > CARAVAN_ARRIVE_M:
			continue
		_deliver(caravan, row)
		_caravans.erase(key)


func _deliver(caravan: Dictionary, carrier_row: int) -> void:
	var receiver: FactionCoreComponent = DAGInstantiator.faction_core(int(caravan["to_faction"]))
	var sender: FactionCoreComponent = DAGInstantiator.faction_core(int(caravan["from_faction"]))
	var material: StringName = caravan["material"]
	var quantity: int = int(caravan["quantity"])

	# The stack ledgerizes into the receiver's wealth: physical on the road, abstract at rest,
	# never both — the same boundary rule the LoD system enforces (review D1).
	var cargo: int = int(caravan["cargo"])
	var carried: InventoryComponent = ECSManager.inventories.get(carrier_row)
	if carried != null:
		carried.held_items.erase(cargo)
		InventorySystem.recompute_totals(carrier_row)
	if ECSManager.is_alive(cargo):
		ECSManager.destroy_entity(cargo)
	if receiver != null:
		receiver.add_wealth(material, quantity)

	# Commerce warms both parties. Symmetric on purpose: a one-way goodwill flow would let one
	# faction farm alliance by shipping pebbles.
	if sender != null and receiver != null:
		ReputationSystem.adjust(sender, receiver.faction_id, TRADE_GOODWILL, &"TRADE")
		ReputationSystem.adjust(receiver, sender.faction_id, TRADE_GOODWILL, &"TRADE")

	var job: JobComponent = ECSManager.jobs.get(carrier_row)
	if job != null and job.current_action == &"TradeMission":
		job.complete()
	caravans_arrived += 1
	ECSEvents.caravan_arrived.emit(
		int(caravan["from_faction"]), int(caravan["to_faction"]), material, quantity
	)


## A courier: a hauler by preference, anyone by necessity. Routine WORK is interruptible — in a
## pre-warmed world EVERY citizen is latched onto some personal routine at all times, so a rule
## that only conscripts the completely idle dispatches nothing, ever (found the moment the
## Pre-Warm actually ran at boot). Meals and sleep are not interruptible: a courier who starved
## on the road is a worse outcome than a caravan that leaves at dawn.
func _idle_hauler(faction_id: int) -> int:
	var fallback: int = -1
	for row in FactionPlanner.members_of(faction_id):
		var job: JobComponent = ECSManager.jobs.get(row)
		if job != null and job.current_action == &"TradeMission" and job.is_latched():
			continue
		var conscriptable: bool = (
			job == null
			or not job.is_latched()
			or job.current_action == ActionIntent.WORK
		)
		if not conscriptable:
			continue
		var profession: ProfessionComponent = ECSManager.professions.get(row)
		if profession != null and profession.profession == &"Prof_Hauler":
			return row
		if fallback < 0:
			fallback = row
	return fallback


static func _richest_material(core: FactionCoreComponent) -> StringName:
	var best: StringName = &""
	var best_amount: int = 0
	for material in core.abstract_wealth_ledger:
		var amount: int = int(core.abstract_wealth_ledger[material])
		if amount > best_amount:
			best_amount = amount
			best = material
	return best


## Citizens spawn without packs; a courier needs one. Idempotent.
static func _ensure_pack(row: int) -> void:
	if not ECSManager.inventories.has(row):
		ECSManager.inventories[row] = InventoryComponent.new()
		ECSManager.add_component_bit(row, ComponentMask.INVENTORY)
	if not ECSManager.containers.has(row):
		var pack := ContainerComponent.new()
		pack.capacity_cm3 = 40000.0
		ECSManager.containers[row] = pack
		ECSManager.add_component_bit(row, ComponentMask.CONTAINER)


static func _at_war(core: FactionCoreComponent, other_faction: int) -> bool:
	var state: Dictionary = core.diplomacy.get(other_faction, {})
	return (
		not state.is_empty()
		and state["status"] == ECSEnums.RelationshipStatus.WAR
	)


static func _allied(core: FactionCoreComponent, other_faction: int) -> bool:
	var state: Dictionary = core.diplomacy.get(other_faction, {})
	return (
		not state.is_empty()
		and state["status"] == ECSEnums.RelationshipStatus.ALLIED
	)


static func _faction_of(row: int) -> int:
	if row == WorldConstants.PLAYER_INDEX:
		return WorldConstants.PLAYER_FACTION_ID
	var identity: SocialIdentityComponent = ECSManager.social_identities.get(row)
	return -1 if identity == null else identity.faction_id


## Same record shape `ReputationSystem` writes, so one prompt-side reader serves both writers.
static func _remember_for_faction(
	core: FactionCoreComponent, kind: StringName, text: String
) -> void:
	var record: MemoryEvent = MemoryEvent.create(
		kind, StringName(text), GameClock.total_hours(), true
	)
	core.faction_memory.append({
		"event_id": record.event_id,
		"text": text,
		"tick": record.tick_hours,
		"weight": MemoryEvent.base_weight(kind),
		"core": true,
	})


func counters() -> Dictionary:
	return {
		"loyalty_updates": loyalty_updates,
		"successions": successions,
		"schisms": schisms,
		"schisms_blocked_by_cap": schisms_blocked_by_cap,
		"engagements": engagements,
		"brawls": brawls,
		"caravans_dispatched": caravans_dispatched,
		"caravans_arrived": caravans_arrived,
		"caravans_lost": caravans_lost,
		"trespasses": trespasses,
	}
