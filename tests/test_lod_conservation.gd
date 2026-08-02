## The LoD boundary two-way sync (Sprint 2 Step 4).
##
## The headline is `test_crossing_a_boundary_n_times_conserves_faction_value` — the property test
## the scaffolding asks for by name. Everything else here exists because it is one of the ways
## that property can be violated while still looking correct in a single crossing.
extends GutTest

const SEED: int = 31
const ANCHOR := Vector3i(0, 0, 0)
const FAR_AWAY := Vector3i(9, 9, 0)

var grid: WorldGrid
var streaming: ChunkStreamingSystem
var core: FactionCoreComponent


func before_each() -> void:
	GameLoopManager.set_physics_process(false)
	World.boot_scenario(World.SCENARIO_TEST_ARENA, SEED)
	RNGService.reseed_all(SEED)
	grid = WorldGrid.new(SEED)
	grid.generate_village()
	streaming = ChunkStreamingSystem.new()
	core = _make_faction(500, 120)


func after_all() -> void:
	GameLoopManager.set_physics_process(true)


## A faction anchored at the origin holding a known ledger.
func _make_faction(iron: int, gold: int) -> FactionCoreComponent:
	var handle: int = ECSManager.allocate_entity()
	var row: int = EH.index_of(handle)
	var made := FactionCoreComponent.new()
	made.faction_id = 4242
	made.anchor_chunk_id = ANCHOR
	made.abstract_wealth_ledger = {&"MAT_IRON": iron, &"MAT_GOLD": gold}
	ECSManager.faction_cores[row] = made
	ECSManager.add_component_bit(row, ComponentMask.FACTION_CORE)
	return made


# --- THE PROPERTY TEST -----------------------------------------------------------------------

## Walk across the seam twenty times. Total faction value must be bit-identical at the end.
##
## This is the test the whole system is built around. A single crossing looks right under almost
## any implementation; it is the twentieth that exposes a materialize that forgot to empty the
## ledger, or a sweep that forgot to destroy the stacks.
func test_crossing_a_boundary_n_times_conserves_faction_value() -> void:
	var before: int = ChunkStreamingSystem.total_faction_value(core.faction_id)
	assert_eq(before, 620, "the faction starts with a known 620 units")

	var materializations: int = 0
	var sweeps: int = 0
	for _crossing in 20:
		streaming.update_chunk_states(ANCHOR, grid)
		materializations += streaming.stacks_materialized
		streaming.update_chunk_states(FAR_AWAY, grid)
		sweeps += streaming.stacks_ledgerized

	assert_eq(
		ChunkStreamingSystem.total_faction_value(core.faction_id),
		before,
		"twenty boundary crossings neither minted nor burned a single unit"
	)
	# NON-VACUITY. A system that simply never transitioned would also conserve value perfectly,
	# and would pass every assertion above while doing nothing at all.
	assert_gte(materializations, 40, "the ledger really was spawned each crossing (2 materials)")
	assert_gte(sweeps, 40, "and really was swept back each time")


## And the same starting from the other side, in case the first transition direction is the one
## that happens to be safe.
func test_conservation_holds_starting_from_the_far_side() -> void:
	streaming.update_chunk_states(FAR_AWAY, grid)
	var before: int = ChunkStreamingSystem.total_faction_value(core.faction_id)
	for _crossing in 20:
		streaming.update_chunk_states(ANCHOR, grid)
		streaming.update_chunk_states(FAR_AWAY, grid)
	assert_eq(
		ChunkStreamingSystem.total_faction_value(core.faction_id), before, "still conserved"
	)


# --- The individual failure modes -------------------------------------------------------------

## Promotion must EMPTY the ledger as it spawns. Leaving it full is the infinite-gold exploit in
## its simplest form: every promotion mints another copy of the same goods.
func test_materializing_empties_the_ledger() -> void:
	streaming.update_chunk_states(ANCHOR, grid)
	assert_eq(core.ledger_total(), 0, "the ledger is spent, not copied")
	assert_gt(streaming.stacks_materialized, 0, "and the goods exist as physical stacks")
	assert_eq(
		ChunkStreamingSystem.total_faction_value(core.faction_id), 620, "with no change in total"
	)


## Demotion must DESTROY the stacks it banks. Leaving them is the same dupe from the other side.
func test_dematerializing_destroys_the_stacks_it_banks() -> void:
	streaming.update_chunk_states(ANCHOR, grid)
	var physical_rows: int = _owned_commodity_rows().size()
	assert_gt(physical_rows, 0, "stacks exist while Active")

	streaming.update_chunk_states(FAR_AWAY, grid)
	assert_eq(_owned_commodity_rows().size(), 0, "and are gone once banked")
	assert_eq(core.ledger_total(), 620, "with the full value back on the ledger")


## The idempotency guard. Promoting an already-materialized chunk must be a no-op.
func test_a_second_promotion_does_nothing() -> void:
	var chunk: ChunkData = grid.chunk_at(ANCHOR)
	streaming.shift_to_active(chunk)
	var after_first: int = _owned_commodity_rows().size()
	streaming.shift_to_active(chunk)
	assert_eq(_owned_commodity_rows().size(), after_first, "no second helping of stacks")


func test_a_second_demotion_does_nothing() -> void:
	var chunk: ChunkData = grid.chunk_at(ANCHOR)
	streaming.shift_to_active(chunk)
	streaming.shift_to_simulated(chunk)
	var banked: int = core.ledger_total()
	streaming.shift_to_simulated(chunk)
	assert_eq(core.ledger_total(), banked, "the ledger is not credited twice")


## THE D1 FIX. Sweeping only a stockpile zone means carrying the goods two steps into a pocket
## and crossing the boundary banks them while they are still held — the value then exists both
## on the ledger and in the inventory.
func test_goods_inside_an_npc_inventory_are_swept_too() -> void:
	streaming.update_chunk_states(ANCHOR, grid)
	var carrier: int = _spawn_carrier()
	var stack: int = _owned_commodity_rows()[0]
	# Move a stack into the carrier's pockets without changing its ownership.
	ECSManager.inventories[carrier].add(ECSManager.handle_of(stack))

	var before: int = ChunkStreamingSystem.total_faction_value(core.faction_id)
	streaming.update_chunk_states(FAR_AWAY, grid)
	assert_eq(
		ChunkStreamingSystem.total_faction_value(core.faction_id),
		before,
		"carried goods are banked exactly once, not left behind AND credited"
	)
	assert_false(ECSManager.is_alive(ECSManager.handle_of(stack)), "the carried stack was banked")


## IDENTITY IS NOT FUNGIBLE. A named sword swept into "37 iron" is destroyed as surely as if it
## had been deleted.
func test_identity_bearing_items_are_never_ledgerized() -> void:
	streaming.update_chunk_states(ANCHOR, grid)
	var relic: int = _spawn_relic()
	var relic_row: int = ECSManager.resolve(relic)

	streaming.update_chunk_states(FAR_AWAY, grid)
	assert_true(ECSManager.is_alive(relic), "the relic survives the sweep")
	assert_eq(
		ECSManager.physicals[relic_row].quantity, 1, "and is still itself, not a pile of units"
	)


## The player's pockets are not the faction's treasury.
func test_the_player_is_never_swept() -> void:
	streaming.update_chunk_states(ANCHOR, grid)
	var player_row: int = EH.index_of(ECSManager.player_handle())
	ECSManager.ownerships[player_row] = OwnershipComponent.new(core.faction_id)
	ECSManager.add_component_bit(player_row, ComponentMask.OWNERSHIP)

	streaming.update_chunk_states(FAR_AWAY, grid)
	assert_true(ECSManager.is_alive(ECSManager.player_handle()), "the player still exists")


## Projectiles CANNOT sleep. A frozen arrow at a seam resumes as if no time passed when you walk
## back — absurd, and an exploit.
func test_projectiles_are_resolved_rather_than_frozen() -> void:
	streaming.update_chunk_states(ANCHOR, grid)
	var arrow: int = _spawn_projectile()

	streaming.update_chunk_states(FAR_AWAY, grid)
	assert_false(ECSManager.is_alive(arrow), "the projectile was resolved and removed")
	assert_gt(streaming.projectiles_resolved, 0, "and reported as such")


## Simulated movers keep their PLACE. Discarding position teleports every NPC to its anchor the
## moment the player looks away (review G4).
func test_demotion_keeps_position_and_only_drops_momentum() -> void:
	streaming.update_chunk_states(ANCHOR, grid)
	var walker: int = _spawn_carrier()
	var where: Vector3 = ECSManager.position_of(walker)
	ECSManager.set_velocity(walker, Vector3(3.0, 0.0, 1.0))

	streaming.update_chunk_states(FAR_AWAY, grid)
	assert_eq(ECSManager.position_of(walker), where, "the NPC is still where it was")
	assert_eq(ECSManager.velocity_of(walker), Vector3.ZERO, "but is no longer moving")


func test_chunk_states_follow_the_player() -> void:
	streaming.update_chunk_states(ANCHOR, grid)
	assert_eq(grid.chunk_at(ANCHOR).state, ECSEnums.LoD.ACTIVE, "the player's chunk is Active")
	streaming.update_chunk_states(FAR_AWAY, grid)
	assert_eq(
		grid.chunk_at(ANCHOR).state, ECSEnums.LoD.SIMULATED, "and is demoted once left behind"
	)


# --- fixtures ---------------------------------------------------------------------------------

func _owned_commodity_rows() -> Array[int]:
	var out: Array[int] = []
	for row in ECSManager.query(ComponentMask.OWNERSHIP):
		var ownership: OwnershipComponent = ECSManager.ownerships[row]
		if ownership.faction_id != core.faction_id:
			continue
		var policy: MaterializationComponent = ECSManager.materializations.get(row)
		if policy != null and policy.can_ledgerize():
			out.append(row)
	return out


func _spawn_in_anchor(policy_kind: ECSEnums.MaterializationPolicy) -> int:
	var handle: int = ECSManager.allocate_entity()
	var row: int = EH.index_of(handle)
	ECSManager.set_position(row, grid.chunk_at(ANCHOR).tile_to_world(20, 20))
	ECSManager.col_chunk_x[row] = ANCHOR.x
	ECSManager.col_chunk_y[row] = ANCHOR.y
	ECSManager.col_floor[row] = ANCHOR.z
	ECSManager.add_component_bit(row, ComponentMask.POSITION)

	var physical := PhysicalPropertyComponent.new()
	physical.quantity = 1
	physical.volume_cm3 = 100.0
	ECSManager.physicals[row] = physical
	ECSManager.add_component_bit(row, ComponentMask.PHYSICAL)
	ECSManager.materials[row] = MaterialCompositionComponent.new({MaterialLibrary.MAT_IRON: 1.0})
	ECSManager.add_component_bit(row, ComponentMask.MATERIAL)
	ECSManager.ownerships[row] = OwnershipComponent.new(core.faction_id)
	ECSManager.add_component_bit(row, ComponentMask.OWNERSHIP)

	var policy := MaterializationComponent.new()
	policy.policy = policy_kind
	ECSManager.materializations[row] = policy
	ECSManager.add_component_bit(row, ComponentMask.MATERIALIZATION)
	return handle


func _spawn_relic() -> int:
	return _spawn_in_anchor(ECSEnums.MaterializationPolicy.PRESERVE_ENTITY)


func _spawn_carrier() -> int:
	var handle: int = _spawn_in_anchor(ECSEnums.MaterializationPolicy.PRESERVE_ENTITY)
	var row: int = EH.index_of(handle)
	ECSManager.inventories[row] = InventoryComponent.new()
	ECSManager.add_component_bit(row, ComponentMask.INVENTORY)
	return row


func _spawn_projectile() -> int:
	var handle: int = _spawn_in_anchor(ECSEnums.MaterializationPolicy.GC_ELIGIBLE)
	var row: int = EH.index_of(handle)
	var chemistry := ChemistryComponent.new()
	chemistry.add_tag(&"Kinetic_Ephemeral")
	ECSManager.chemistries[row] = chemistry
	ECSManager.add_component_bit(row, ComponentMask.CHEMISTRY)
	ECSManager.ephemerals[row] = EphemeralComponent.new()
	ECSManager.add_component_bit(row, ComponentMask.EPHEMERAL)
	return handle
