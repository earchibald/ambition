## The player dies, the world does not (Sprint 3 Steps 4-6).
##
## No Game Over screen and no save reload. The run ends, a year passes, and a new adventurer
## walks in to a world that changed while nobody was playing it.
##
## THE HANDLE DISCIPLINE (ADR-14, ADR-19). Row 0 is reserved for the player forever, so the
## corpse CANNOT be left there — a corpse on index 0 would be found by every system that asks
## "where is the player". Instead the corpse is a SEPARATE entity, and row 0's generation is
## bumped so every handle anyone still holds to the previous adventurer fails validation rather
## than silently resolving to their replacement.
##
## THE TAXES ARE LEVIED ON LEDGERS (ADR-11). During the Interregnum the world is Abstracted:
## wealth is integers on FactionCore and swarms are counters on ChunkData. Taxing physical
## entities instead would mean materializing the world in order to delete it, which is both
## enormously expensive and exactly backwards.
class_name DeathLoopSystem
extends RefCounted

## Fraction of ledger wealth that survives a year of nobody minding the store.
const WEALTH_RETAINED: float = 0.60

## Fraction of a grudge against the player that survives a year of their absence.
##
## `meta_progression_and_death_loop_architecture.md` says to decay diplomacy toward Faction 0 by
## "60-75% toward neutral" on each Interregnum pass, and ADR-9 makes the Interregnum 12 monthly
## passes. Those two sentences do not compose. Read per-pass, the retained fraction is
## 0.4^12 = 1.7e-5 at the gentle end — a faction that watched you murder its people forgets
## completely, and the whole consequence layer resets every death. Read across the year it is one
## application. This takes the annual reading, at the midpoint of the stated band, and the
## arithmetic above is why. Recorded as a resolved spec ambiguity, not a silent choice.
const GRUDGE_RETAINED: float = 0.30

## Carrying capacity per chunk. Rats and spiders breed geometrically in an abstract counter, and
## an unchecked exponential is a save-file-sized number by year two.
const SWARM_CAP_PER_CHUNK: int = 10

## Chance an unowned loose item is swept during the year. Owned goods belong to somebody who
## would have picked them up.
const UNOWNED_DECAY_CHANCE: float = 0.40

var deaths: int = 0
var corpses_created: int = 0
var items_spilled: int = 0
var wealth_taxed: int = 0
var swarms_capped: int = 0
var junk_collected: int = 0
var grudges_decayed: int = 0


## Entity 0's health reached zero. Returns the corpse handle.
##
## Order matters: the journal is captured BEFORE anything is destroyed, because it reads the mind
## of the entity this is about to retire.
func on_player_death(killer_handle: int, generator: DAGGenerator) -> int:
	deaths += 1
	var row: int = EH.index_of(ECSManager.player_handle())
	var journal: Dictionary = LineageJournal.record_death(row)

	# Control is severed FIRST. A dead player who can still walk is the worst possible frame.
	ECSManager.remove_component_bit(row, ComponentMask.PLAYER_INPUT)
	ECSManager.player_inputs.erase(row)
	ECSManager.set_velocity(row, Vector3.ZERO)

	var corpse: int = _create_corpse(row, killer_handle)
	_record_death_in_history(killer_handle, generator)
	ECSEvents.player_died.emit(corpse, killer_handle, int(journal.get("generation", 1)))
	return corpse


## A SEPARATE entity at the player's last position, holding everything they carried.
##
## The roadmap's success state is watching your killer pick up your sword, which requires the
## sword to be a real object in the world rather than a line in a save file.
func _create_corpse(player_row: int, _killer_handle: int) -> int:
	var handle: int = ECSManager.allocate_entity()
	var row: int = EH.index_of(handle)
	var resting: Vector3 = ECSManager.position_of(player_row)

	ECSManager.set_position(row, resting)
	ECSManager.col_chunk_x[row] = ECSManager.col_chunk_x[player_row]
	ECSManager.col_chunk_y[row] = ECSManager.col_chunk_y[player_row]
	ECSManager.col_floor[row] = ECSManager.col_floor[player_row]
	ECSManager.add_component_bit(row, ComponentMask.POSITION)
	ECSManager.bounds[row] = BoundsComponent.new(Vector3(0.35, 0.25, 0.35))
	ECSManager.add_component_bit(row, ComponentMask.BOUNDS)

	var physical := PhysicalPropertyComponent.new()
	physical.volume_cm3 = 66000.0
	ECSManager.physicals[row] = physical
	ECSManager.add_component_bit(row, ComponentMask.PHYSICAL)
	ECSManager.materials[row] = MaterialCompositionComponent.new(
		{MaterialLibrary.MAT_BIOMASS: 1.0}
	)
	ECSManager.add_component_bit(row, ComponentMask.MATERIAL)
	MaterialLibrary.recompute_mass(physical, ECSManager.materials[row])

	var chemistry := ChemistryComponent.new()
	chemistry.add_tag(&"Corpse")
	chemistry.add_tag(&"Adventurer_Remains")
	ECSManager.chemistries[row] = chemistry
	ECSManager.add_component_bit(row, ComponentMask.CHEMISTRY)

	# The corpse is a container, so the killer can loot it as a unit rather than the gear being
	# scattered as a pile of unrelated objects.
	var container := ContainerComponent.new()
	container.capacity_cm3 = 60000.0
	ECSManager.containers[row] = container
	ECSManager.add_component_bit(row, ComponentMask.CONTAINER)
	var inventory := InventoryComponent.new()
	ECSManager.inventories[row] = inventory
	ECSManager.add_component_bit(row, ComponentMask.INVENTORY)

	ECSManager.lods[row] = LoDComponent.new(ECSEnums.LoD.ACTIVE)
	ECSManager.add_component_bit(row, ComponentMask.LOD)
	ECSManager.loose_items[row] = LooseItemComponent.new()
	ECSManager.add_component_bit(row, ComponentMask.LOOSE_ITEM)

	_spill_inventory(player_row, row)
	corpses_created += 1
	ECSEvents.emit_entity_created(
		handle, [&"Item", &"Corpse"] as Array[StringName], resting
	)
	return handle


## Moves the dead adventurer's possessions into the corpse. Ownership transfers to nobody: the
## goods are loot now, and leaving them owned by the dead would make the LoD sweep bank them into
## a faction ledger the player was never part of.
func _spill_inventory(player_row: int, corpse_row: int) -> void:
	var carried: InventoryComponent = ECSManager.inventories.get(player_row)
	if carried == null:
		return
	var corpse_inventory: InventoryComponent = ECSManager.inventories[corpse_row]
	for held in carried.held_items:
		var item_row: int = ECSManager.resolve(held)
		if item_row < 0:
			continue
		ECSManager.ownerships.erase(item_row)
		ECSManager.remove_component_bit(item_row, ComponentMask.OWNERSHIP)
		corpse_inventory.add(held)
		items_spilled += 1
	carried.held_items.clear()
	InventorySystem.recompute_totals(player_row)
	InventorySystem.recompute_totals(corpse_row)


## A year passes. Ledgers and counters only.
func run_interregnum(bootstrapper: Bootstrapper, grid: WorldGrid) -> void:
	# The test arena has no bootstrapper and no grid — it is one hand-authored chunk with no
	# history to age. The taxes below still apply to whatever entities exist, so a death in the
	# arena completes its loop rather than crashing on a null.
	if bootstrapper != null:
		bootstrapper._run_interregnum()
	_levy_entropy_tax()
	# Breed BEFORE the junk sweep: the filth that feeds the rats is the same filth the sweep is
	# about to collect, and a year's vermin bloom is caused by the mess as it stood at death,
	# not by whatever survives the cleanup.
	_breed_swarms(grid)
	_cap_swarms(grid)
	_collect_junk()
	_decay_grudges()


## 40% of abstract wealth evaporates. Not punishment — it is what makes a year of absence cost
## something, and it is why returning to a hoard you remember is never quite what you left.
func _levy_entropy_tax() -> void:
	for row in ECSManager.query(ComponentMask.FACTION_CORE):
		var core: FactionCoreComponent = ECSManager.faction_cores[row]
		for material in core.abstract_wealth_ledger:
			var before: int = int(core.abstract_wealth_ledger[material])
			var after: int = int(float(before) * WEALTH_RETAINED)
			core.abstract_wealth_ledger[material] = after
			wealth_taxed += before - after


## A year of breeding, on the COUNTER (ecology: "Filth left by the player spawns massive rat
## populations"). Geometric doubling, plus two heads per piece of filth rotting in the chunk.
## This is the growth the swarm tax below exists to cap, and until 2026-08-01 it did not exist:
## the tax clamped a counter nothing ever raised, so `swarms_capped` was structurally zero in
## every session that was ever played.
func _breed_swarms(grid: WorldGrid) -> void:
	if grid == null:
		return
	var filth_by_chunk: Dictionary = {}
	for row in ECSManager.query(ComponentMask.LOOSE_ITEM):
		var chemistry: ChemistryComponent = ECSManager.chemistries.get(row)
		if chemistry == null or not chemistry.active_tags.has(&"Filth"):
			continue
		var chunk_id := Vector3i(
			ECSManager.col_chunk_x[row], ECSManager.col_chunk_y[row], ECSManager.col_floor[row]
		)
		filth_by_chunk[chunk_id] = int(filth_by_chunk.get(chunk_id, 0)) + 1
	for chunk_id in grid.chunks:
		var chunk: ChunkData = grid.chunks[chunk_id]
		var boost: int = 2 * int(filth_by_chunk.get(chunk_id, 0))
		if chunk.swarm_population > 0 or boost > 0:
			chunk.swarm_population = chunk.swarm_population * 2 + boost


## Carrying capacity, on the COUNTER. Rats breed geometrically; an unchecked exponential over
## twelve months is a number that overflows the save format before it overflows the dungeon.
func _cap_swarms(grid: WorldGrid) -> void:
	if grid == null:
		return
	for chunk_id in grid.chunks:
		var chunk: ChunkData = grid.chunks[chunk_id]
		if chunk.swarm_population > SWARM_CAP_PER_CHUNK:
			chunk.swarm_population = SWARM_CAP_PER_CHUNK
			swarms_capped += 1


## A year is long enough for the anger to cool, but not for the memory to go.
##
## This closes a gap nobody had implemented: reputation was permanent. Sprint 3.5 gave factions a
## reason to hate the player and Sprint 3D gave the player a way to die, and nothing connected
## them — so a village that turned hostile stayed hostile forever, across every future life,
## which makes the death loop a respawn rather than a fresh start.
##
## The SCORE decays toward neutral. The GRIEVANCE LIST does not. That asymmetry is the point:
## they no longer act on it, and they still remember what you did. It is also what lets a second
## offence land harder than the first without any special case for repeat offenders.
func _decay_grudges() -> void:
	for row in ECSManager.query(ComponentMask.FACTION_CORE):
		var core: FactionCoreComponent = ECSManager.faction_cores[row]
		if not core.diplomacy.has(WorldConstants.PLAYER_FACTION_ID):
			continue
		var state: Dictionary = core.diplomacy[WorldConstants.PLAYER_FACTION_ID]
		var before: float = float(state["score"])
		if is_zero_approx(before):
			continue
		state["score"] = before * GRUDGE_RETAINED
		# THE SPAWN-FACTION FLOOR (death-loop doc, REQUIRED): the faction whose chunk the new
		# adventurer wakes in is hard-clamped to NEUTRAL at re-entry. Before this clamp the rule
		# held only by arithmetic accident — score floor -100 x 0.30 = -30, just above the -40
		# hostility line — so anyone tuning GRUDGE_RETAINED past 0.4 would have silently restored
		# the unwinnable spawn the requirement exists to prevent. An invariant enforced by
		# coincidence is not enforced.
		if core.anchor_chunk_id == Vector3i.ZERO:
			state["score"] = maxf(
				float(state["score"]), ReputationSystem.HOSTILE_BELOW + 1.0
			)
		state["status"] = ReputationSystem.status_for(float(state["score"]))
		grudges_decayed += 1


## Residual physical sweep. Filth and scrap always go; unowned loose items go by chance, because
## an owned item belongs to somebody who would have collected it.
func _collect_junk() -> void:
	var doomed: Array[int] = []
	for row in ECSManager.query(ComponentMask.LOOSE_ITEM):
		var chemistry: ChemistryComponent = ECSManager.chemistries.get(row)
		if chemistry != null and (
			chemistry.active_tags.has(&"Filth") or chemistry.active_tags.has(&"Scrap")
		):
			doomed.append(row)
			continue
		if ECSManager.ownerships.has(row):
			continue
		# ADR-20: the RNG stream, never a bare randf, or the soak harness cannot reproduce a run.
		if RNGService.randf_in(&"economy") < UNOWNED_DECAY_CHANCE:
			doomed.append(row)
	for row in doomed:
		ECSManager.destroy_entity(ECSManager.handle_of(row))
		junk_collected += 1


## The next adventurer. Row 0 is reused with a bumped generation, so every handle to the previous
## one now fails validation instead of resolving to their replacement.
func spawn_successor(chunk: ChunkData, journal: Dictionary) -> int:
	var row: int = WorldConstants.PLAYER_INDEX
	ECSManager.bump_generation(row)
	World._spawn_player(chunk)
	LineageJournal.apply_to(row, journal)
	ECSEvents.player_reborn.emit(ECSManager.player_handle(), int(journal.get("generation", 1)))
	return ECSManager.player_handle()


## The death becomes history. Faction 0 is the player (ADR-14), so the edge hangs off a synthetic
## node rather than a real faction — the adventurer is not an organisation.
##
## DIRECTION MATTERS, and this was wrong until 2026-08-01. The edge was written as
## `DESTROYED(player, killer)`, which under this graph's own convention — `CONQUERED(aggressor,
## victim)` — reads as the player having wiped out the killer's faction. Every reader scanning
## for what happened to that faction would have found a destruction it never suffered. The type
## was also an overload: `DESTROYED` is written elsewhere as a self-loop meaning "this node
## ceased to exist", and a faction that kills the player has not ceased to exist.
##
## An unwitnessed death — a fall, starvation, drowning — has no killer, and is recorded as a
## self-loop rather than an edge to faction -1. There is no node -1, so an edge pointing at it is
## a dangling reference in the only record of why the world looks the way it does.
func _record_death_in_history(killer_handle: int, generator: DAGGenerator) -> void:
	if generator == null:
		return
	var killer_faction: int = WorldConstants.PLAYER_FACTION_ID
	var killer_row: int = ECSManager.resolve(killer_handle)
	if killer_row >= 0:
		var identity: SocialIdentityComponent = ECSManager.social_identities.get(killer_row)
		if identity != null:
			killer_faction = identity.faction_id
	generator.edges.append(
		DAGEdge.create(
			WorldConstants.PLAYER_FACTION_ID,
			killer_faction,
			ECSEnums.EdgeType.KILLED_BY,
			generator.current_epoch
		)
	)


func counters() -> Dictionary:
	return {
		"player_deaths": deaths,
		"corpses_created": corpses_created,
		"items_spilled": items_spilled,
		"interregnum_wealth_taxed": wealth_taxed,
		"interregnum_swarms_capped": swarms_capped,
		"interregnum_junk_collected": junk_collected,
		"interregnum_grudges_decayed": grudges_decayed,
	}
