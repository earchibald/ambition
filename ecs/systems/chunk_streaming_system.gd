## Chunk LoD transitions and the two-way wealth sync (Sprint 2 Step 4).
##
## THE INVARIANT THIS EXISTS TO PROTECT: a unit of faction wealth is counted in EXACTLY ONE
## place at any moment — as an integer on the ledger while the chunk is not Active, or as
## `PhysicalPropertyComponent.quantity` on a stack while it is. Never both, never neither.
##
## Both halves of the dupe are easy to write by accident:
##   * Materialize without emptying the ledger, and every boundary crossing mints a fresh copy.
##   * Dematerialize without destroying the stacks, and the same goods are banked twice.
## `ChunkData.wealth_materialized` is the transaction flag that makes each direction happen at
## most once, so oscillating across a seam is a no-op rather than a printing press.
##
## IDENTITY IS NOT FUNGIBLE. Only `MaterializationPolicy.LEDGERIZE` items dissolve into integers.
## A named sword swept into "37 iron" is destroyed as surely as if it were deleted, which is why
## the sweep filters on policy rather than on material.
class_name ChunkStreamingSystem
extends RefCounted

## Stacks spawned by materialization are commodity piles. They sit on the floor of the anchor
## chunk near its centre, not at the world origin.
const STOCKPILE_TILE := Vector2i(32, 32)
const STOCKPILE_SPREAD: int = 6

var promotions: int = 0
var demotions: int = 0
var stacks_materialized: int = 0
var stacks_ledgerized: int = 0
var projectiles_resolved: int = 0
var movers_frozen: int = 0
var lecterns_spawned: int = 0
var abstract_wall_hits: int = 0
var abstract_flights: int = 0

var _active_ids: Dictionary = {}


## Forgets which chunks were Active. MUST be called when the world is rebuilt.
##
## The active set is remembered across calls so a steady player does not re-promote the same nine
## chunks every tick. That memory is wrong the instant a NEW grid replaces the old one: the fresh
## chunks have never been promoted, but their ids match, so `update_chunk_states` sees no
## transition and skips them — leaving every chunk in the reboot unpromoted and every faction's
## wealth unmaterialized. Found by an inspector test that booted the world twice.
func reset() -> void:
	_active_ids.clear()


## Drives every chunk into the state the player's position implies.
func update_chunk_states(player_chunk_id: Vector3i, grid: WorldGrid) -> void:
	promotions = 0
	demotions = 0
	stacks_materialized = 0
	stacks_ledgerized = 0
	projectiles_resolved = 0
	movers_frozen = 0

	var wanted: Dictionary = {}
	for chunk_id in LoDSystem.active_set(player_chunk_id):
		wanted[chunk_id] = true

	# Demote first. Promoting first would briefly have both the outgoing and incoming chunk
	# Active, and a mover on the seam could be swept by one and materialized by the other in the
	# same tick.
	for chunk_id in _active_ids.keys():
		if not wanted.has(chunk_id):
			shift_to_simulated(grid.chunk_at(chunk_id))
			_active_ids.erase(chunk_id)

	for chunk_id in wanted:
		if _active_ids.has(chunk_id):
			continue
		shift_to_active(grid.chunk_at(chunk_id))
		_active_ids[chunk_id] = true


func shift_to_active(chunk: ChunkData) -> void:
	chunk.state = ECSEnums.LoD.ACTIVE
	promotions += 1
	# Fluids arrive through the flood buffer at a bounded rate, so promoting a flooded chunk
	# cannot instantiate a tsunami in one frame.
	FluidDynamicsSystem.promote_from_pools(chunk, STOCKPILE_TILE)
	_materialize_faction_wealth(chunk)
	_spawn_ruin_props(chunk)


## Ruined libraries, made READABLE (declared gap G-3). Roughly a third of dungeon chunks hold a
## lectern inscribed with a few runes, placed deterministically from the chunk's own seed
## (ADR-1: the same world always holds the same knowledge in the same rooms). Spawned at first
## promotion because worldgen produces tiles, not entities, and props only matter when someone
## is there to read them.
func _spawn_ruin_props(chunk: ChunkData) -> void:
	if chunk.props_spawned or chunk.chunk_id.z >= 0:
		return
	chunk.props_spawned = true
	var rng: RandomNumberGenerator = FloorGenerator.chunk_rng(chunk.chunk_id, 777)
	if rng.randf() > 0.34:
		return
	var rune_ids: Array[StringName] = []
	for rune_id in RuneLibrary.RUNES:
		rune_ids.append(rune_id)
	var inscribed: Array[StringName] = []
	for _pick in 3:
		var candidate: StringName = rune_ids[rng.randi_range(0, rune_ids.size() - 1)]
		if not inscribed.has(candidate):
			inscribed.append(candidate)
	var ground: Vector3 = World.spawn_position_in(chunk)
	World.spawn_lectern(Vector3(ground.x, ground.y + 0.5, ground.z), inscribed)
	lecterns_spawned += 1


func shift_to_simulated(chunk: ChunkData) -> void:
	chunk.state = ECSEnums.LoD.SIMULATED
	demotions += 1
	for row in rows_in_chunk(chunk.chunk_id):
		if _is_kinetic_ephemeral(row):
			# Projectiles CANNOT sleep. A frozen arrow hanging in mid-air at a chunk seam is
			# both absurd and an exploit: walk away, walk back, and it resumes as if no time
			# passed. Resolve it against the abstract tiles and remove it.
			_resolve_abstract_hit(row, chunk)
			ECSManager.destroy_entity(ECSManager.handle_of(row))
			projectiles_resolved += 1
			continue
		_freeze_mover(row)
	_dematerialize_faction_wealth(chunk)
	FluidDynamicsSystem.demote_to_pools(chunk)


## Ledger -> physical. Empties the ledger as it spawns, so a second promotion has nothing to
## spend and cannot double the goods.
func _materialize_faction_wealth(chunk: ChunkData) -> void:
	if chunk.wealth_materialized:
		return
	chunk.wealth_materialized = true

	var core: FactionCoreComponent = _core_anchored_at(chunk.chunk_id)
	if core == null:
		return
	chunk.claim_faction_id = core.faction_id
	var taken: Dictionary = core.withdraw_all()
	var slot: int = 0
	for material in taken:
		var amount: int = int(taken[material])
		if amount <= 0:
			continue
		_spawn_stack(chunk, core.faction_id, material, amount, slot)
		slot += 1
		stacks_materialized += 1


## Physical -> ledger. Sweeps ALL faction-owned fungible matter in the chunk, not just a
## stockpile zone: commodity piles on the floor AND the contents of NPC inventories. Sweeping
## only the stockpile is the original D1 dupe — carry the goods two steps to one side, cross the
## boundary, and they are banked while still in a pocket.
func _dematerialize_faction_wealth(chunk: ChunkData) -> void:
	if not chunk.wealth_materialized:
		return
	chunk.wealth_materialized = false

	var core: FactionCoreComponent = _core_anchored_at(chunk.chunk_id)
	if core == null:
		return

	var doomed: Array[int] = []
	for row in rows_in_chunk(chunk.chunk_id):
		_sweep_row_into(core, row, doomed)
		# And anything those entities are carrying.
		var inventory: InventoryComponent = ECSManager.inventories.get(row)
		if inventory == null:
			continue
		for handle in inventory.held_items:
			var held_row: int = ECSManager.resolve(handle)
			if held_row >= 0:
				_sweep_row_into(core, held_row, doomed)

	for row in doomed:
		var inventory: InventoryComponent = ECSManager.inventories.get(row)
		if inventory != null:
			inventory.held_items.clear()
		ECSManager.destroy_entity(ECSManager.handle_of(row))
		stacks_ledgerized += 1


## Banks one row if — and only if — it is fungible matter owned by this faction.
func _sweep_row_into(core: FactionCoreComponent, row: int, doomed: Array[int]) -> void:
	if doomed.has(row):
		return
	# The PLAYER is still Active and never sweepable. Their pockets are not the faction's
	# treasury, and emptying them on a boundary crossing would be theft with extra steps.
	if row == 0:
		return
	var ownership: OwnershipComponent = ECSManager.ownerships.get(row)
	if ownership == null or ownership.faction_id != core.faction_id:
		return
	var policy: MaterializationComponent = ECSManager.materializations.get(row)
	if policy == null or not policy.can_ledgerize():
		# PRESERVE_ENTITY, CONTAINER_MANIFEST and CARAVAN_MANIFEST keep their identity. A named
		# sword banked as "37 iron" is destroyed exactly as thoroughly as if it were deleted.
		return
	var physical: PhysicalPropertyComponent = ECSManager.physicals.get(row)
	var composition: MaterialCompositionComponent = ECSManager.materials.get(row)
	if physical == null or composition == null:
		return
	var material: StringName = composition.dominant_material()
	if material == &"":
		return
	core.add_wealth(material, physical.quantity)
	doomed.append(row)


## Simulated movers keep their PLACE, only losing their momentum. Discarding position would
## teleport every NPC to its anchor the moment the player looked away, and re-promotion could
## not reconstruct where a traveller had got to (review G4).
func _freeze_mover(row: int) -> void:
	if not ECSManager.has_components(row, ComponentMask.POSITION):
		return
	if ECSManager.velocity_of(row).length_squared() > 0.0:
		movers_frozen += 1
	ECSManager.set_velocity(row, Vector3.ZERO)
	var queue: Array = ECSManager.action_queues.get(row, [])
	# Wiping the queue is what shifts the agent from playing physical animations to resolving
	# abstractly. Leaving it would re-trigger the same swing every tick with nobody watching.
	queue.clear()


func _is_kinetic_ephemeral(row: int) -> bool:
	var chemistry: ChemistryComponent = ECSManager.chemistries.get(row)
	if chemistry == null:
		return false
	return chemistry.active_tags.has(&"Kinetic_Ephemeral")


## An in-flight projectile leaving the Active set is resolved by maths rather than animation:
## the roadmap's "math-based raycast against abstract chunk data". A DDA march along the
## remaining flight path decides whether it strikes a wall in this chunk or flies its full
## range into the dark. The function claimed this for two sprints while doing neither — it set
## TTL to zero and returned. What it still cannot do is DAMAGE an abstract target: Simulated
## entities are not in a spatial hash, and per-entity ballistics against a frozen crowd is
## recorded as not built. The hit-or-flew fact is real, counted, and testable.
func _resolve_abstract_hit(row: int, chunk: ChunkData) -> void:
	var ephemeral: EphemeralComponent = ECSManager.ephemerals.get(row)
	if ephemeral == null:
		return
	var origin: Vector3 = ECSManager.position_of(row)
	var flight_m: float = ephemeral.speed_mps * maxf(ephemeral.time_to_live, 0.0)
	if chunk != null and flight_m > 0.01 and ephemeral.heading.length() > 0.01:
		var terminus: Vector3 = origin + ephemeral.heading.normalized() * flight_m
		if GridDDA.has_line_of_sight(origin, terminus, chunk):
			abstract_flights += 1
		else:
			abstract_wall_hits += 1
	ephemeral.time_to_live = 0.0


func _spawn_stack(
	chunk: ChunkData, faction_id: int, material: StringName, amount: int, slot: int
) -> int:
	var handle: int = ECSManager.allocate_entity()
	var row: int = EH.index_of(handle)
	var tile := Vector2i(
		STOCKPILE_TILE.x + (slot % STOCKPILE_SPREAD), STOCKPILE_TILE.y + (slot / STOCKPILE_SPREAD)
	)
	var ground: Vector3 = chunk.tile_to_world(tile.x, tile.y)

	ECSManager.set_position(row, Vector3(ground.x, ground.y + 0.1, ground.z))
	ECSManager.col_chunk_x[row] = chunk.chunk_id.x
	ECSManager.col_chunk_y[row] = chunk.chunk_id.y
	ECSManager.col_floor[row] = chunk.chunk_id.z
	ECSManager.add_component_bit(row, ComponentMask.POSITION)
	ECSManager.bounds[row] = BoundsComponent.new(Vector3(0.2, 0.2, 0.2))
	ECSManager.add_component_bit(row, ComponentMask.BOUNDS)

	var physical := PhysicalPropertyComponent.new()
	# ONE entity carrying the whole pile. One entity per unit is how an economy simulation runs
	# out of memory.
	physical.quantity = amount
	physical.volume_cm3 = 100.0
	ECSManager.physicals[row] = physical
	ECSManager.add_component_bit(row, ComponentMask.PHYSICAL)

	var composition := MaterialCompositionComponent.new({material: 1.0})
	ECSManager.materials[row] = composition
	ECSManager.add_component_bit(row, ComponentMask.MATERIAL)
	MaterialLibrary.recompute_mass(physical, composition)

	ECSManager.ownerships[row] = OwnershipComponent.new(faction_id)
	ECSManager.add_component_bit(row, ComponentMask.OWNERSHIP)

	var policy := MaterializationComponent.new()
	policy.policy = ECSEnums.MaterializationPolicy.LEDGERIZE
	policy.item_class = &"Commodity"
	ECSManager.materializations[row] = policy
	ECSManager.add_component_bit(row, ComponentMask.MATERIALIZATION)

	ECSManager.lods[row] = LoDComponent.new(ECSEnums.LoD.ACTIVE)
	ECSManager.add_component_bit(row, ComponentMask.LOD)

	ECSEvents.emit_entity_created(
		handle, [&"Item", &"Commodity"] as Array[StringName], ECSManager.position_of(row)
	)
	return handle


## Every living row whose recorded chunk matches. Linear over positioned entities, which is the
## same scan the LoD system already performs each Simulation tick.
static func rows_in_chunk(chunk_id: Vector3i) -> Array[int]:
	var out: Array[int] = []
	for row in ECSManager.query(ComponentMask.POSITION):
		if ECSManager.chunk_id_of(row) == chunk_id:
			out.append(row)
	return out


static func _core_anchored_at(chunk_id: Vector3i) -> FactionCoreComponent:
	for row in ECSManager.faction_cores:
		var core: FactionCoreComponent = ECSManager.faction_cores[row]
		if core.anchor_chunk_id == chunk_id:
			return core
	return null


## How much of ONE material a faction holds, wherever it currently lives.
##
## An Active faction's ledger is EMPTY, because promotion spends it into physical stacks. Any
## caller that reads the ledger alone therefore sees zero for every faction whose territory the
## player happens to be standing in — which had the reasoner concluding that every village it
## could see was starving, permanently, for a structural reason nothing to do with food.
static func owned_material_total(faction_id: int, material: StringName) -> int:
	var total: int = 0
	var core: FactionCoreComponent = DAGInstantiator.faction_core(faction_id)
	if core != null:
		total += int(core.abstract_wealth_ledger.get(material, 0))
	for row in ECSManager.query(ComponentMask.OWNERSHIP):
		var ownership: OwnershipComponent = ECSManager.ownerships[row]
		if ownership.faction_id != faction_id:
			continue
		var composition: MaterialCompositionComponent = ECSManager.materials.get(row)
		var physical: PhysicalPropertyComponent = ECSManager.physicals.get(row)
		if composition == null or physical == null:
			continue
		if composition.dominant_material() == material:
			total += physical.quantity
	return total


## Ledger plus every physical stack the faction owns. THE number the conservation property test
## asserts is invariant across boundary crossings.
static func total_faction_value(faction_id: int) -> int:
	var total: int = 0
	var core: FactionCoreComponent = DAGInstantiator.faction_core(faction_id)
	if core != null:
		total += core.ledger_total()
	for row in ECSManager.query(ComponentMask.OWNERSHIP):
		var ownership: OwnershipComponent = ECSManager.ownerships[row]
		if ownership.faction_id != faction_id:
			continue
		var policy: MaterializationComponent = ECSManager.materializations.get(row)
		if policy == null or not policy.can_ledgerize():
			continue
		var physical: PhysicalPropertyComponent = ECSManager.physicals.get(row)
		if physical != null:
			total += physical.quantity
	return total


func counters() -> Dictionary:
	return {
		"chunk_promotions": promotions,
		"chunk_demotions": demotions,
		"stacks_materialized": stacks_materialized,
		"stacks_ledgerized": stacks_ledgerized,
		"projectiles_resolved": projectiles_resolved,
		"movers_frozen": movers_frozen,
		"lecterns_spawned": lecterns_spawned,
		"projectile_abstract_wall_hits": abstract_wall_hits,
		"projectile_abstract_flights": abstract_flights,
	}
