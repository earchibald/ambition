## Turns surviving DAG nodes into ECS data (Sprint 2 Step 3).
##
## TWO TIERS, AND THE DIFFERENCE IS THE WHOLE POINT.
##
## Every active faction gets exactly ONE macro-entity carrying its FactionCoreComponent. That
## entity has no position, no body, and no bounds — it is a ledger with an id. It costs the same
## whether the faction has nine members or nine hundred.
##
## Physical citizens are instantiated ONLY for factions whose anchor chunk is currently Active or
## Simulated. A history with fifteen surviving factions averaging forty people is six hundred
## agents; materializing all of them at boot would spend most of the ADR-12 entity budget on
## people the player will never travel to see. Abstracted factions exist purely as
## `abstract_population` on the ledger, and the LoD boundary (Step 4) is what promotes them.
##
## WEALTH IS QUANTITY, NEVER ENTITY COUNT. Five hundred iron goes into ONE stack with
## `PhysicalPropertyComponent.quantity = 500`. One entity per unit is how an economy simulation
## turns into an out-of-memory crash.
class_name DAGInstantiator
extends RefCounted

## Cap on citizens materialized per faction in one pass. A DAG node's population is abstract and
## can drift high across 500 years; the physical crowd it produces must stay bounded regardless.
const MAX_CITIZENS_PER_FACTION: int = 40

var factions_created: int = 0
var citizens_spawned: int = 0
var stacks_spawned: int = 0
var skipped_abstract: int = 0


## Creates the macro-entity for every active faction, and bodies only where they are needed.
func instantiate(nodes: Array[DAGNode], grid: WorldGrid) -> void:
	factions_created = 0
	citizens_spawned = 0
	stacks_spawned = 0
	skipped_abstract = 0

	for node in nodes:
		if node.type != ECSEnums.NodeType.FACTION:
			continue
		if not node.has_anchor():
			# World generation assigns anchors. Reaching here means the boot order was violated,
			# and spawning anyway would pile this faction on the world origin.
			push_error("faction %s has no anchor; world generation must run first" % node.name)
			continue
		_create_faction_core(node)
		# NOT `chunk_at`, which generates on demand. Asking it here would build a chunk for every
		# faction in the graph purely to read a flag, undoing the lazy generation that keeps cold
		# boot inside its budget. An unbuilt chunk is by definition abstract.
		if not grid.has_chunk(node.anchor_chunk_id):
			skipped_abstract += 1
			continue
		var chunk: ChunkData = grid.chunk_at(node.anchor_chunk_id)
		if chunk.state == ECSEnums.LoD.ABSTRACTED:
			skipped_abstract += 1
			continue
		_materialize_citizens(node, chunk)


## The ledger entity. No position, no bounds, no body — it is deliberately not a thing in the
## world, and giving it a position would put it in the spatial hash and the renderer.
func _create_faction_core(node: DAGNode) -> int:
	var handle: int = ECSManager.allocate_entity()
	var row: int = EH.index_of(handle)
	ECSManager.faction_cores[row] = FactionCoreComponent.from_dag_node(node)
	ECSManager.add_component_bit(row, ComponentMask.FACTION_CORE)
	factions_created += 1
	return handle


## Tier 2 citizens, at the faction's anchor. Population above the cap stays abstract rather than
## being silently dropped: `abstract_population` keeps the remainder, so the count is conserved.
func _materialize_citizens(node: DAGNode, chunk: ChunkData) -> void:
	var wanted: int = mini(node.population, MAX_CITIZENS_PER_FACTION)
	var rng: RandomNumberGenerator = FloorGenerator.chunk_rng(
		node.anchor_chunk_id, node.node_id
	)
	for i in wanted:
		var tile: Vector2i = _open_tile_near(chunk, rng)
		if tile.x < 0:
			break
		_spawn_citizen(node, chunk, tile)


## Citizens must stand on open ground. Bounded search with a give-up, because a chunk can be
## legitimately full and "roll until you find a gap" would hang the boot.
func _open_tile_near(chunk: ChunkData, rng: RandomNumberGenerator) -> Vector2i:
	for _attempt in 48:
		var candidate := Vector2i(rng.randi_range(2, 61), rng.randi_range(2, 61))
		if not chunk.is_solid(candidate.x, candidate.y):
			return candidate
	return Vector2i(-1, -1)


func _spawn_citizen(node: DAGNode, chunk: ChunkData, tile: Vector2i) -> int:
	var handle: int = ECSManager.allocate_entity()
	var row: int = EH.index_of(handle)
	var ground: Vector3 = chunk.tile_to_world(tile.x, tile.y)

	ECSManager.set_position(row, Vector3(ground.x, ground.y + 0.9, ground.z))
	ECSManager.set_velocity(row, Vector3.ZERO)
	ECSManager.col_chunk_x[row] = chunk.chunk_id.x
	ECSManager.col_chunk_y[row] = chunk.chunk_id.y
	ECSManager.col_floor[row] = chunk.chunk_id.z
	ECSManager.add_component_bit(row, ComponentMask.POSITION)

	ECSManager.bounds[row] = BoundsComponent.new(Vector3(0.3, 0.9, 0.3))
	ECSManager.add_component_bit(row, ComponentMask.BOUNDS)

	var body := BodyComponent.new()
	body.strength = 8.0
	body.structural_toughness = 1.0
	ECSManager.bodies[row] = body
	ECSManager.add_component_bit(row, ComponentMask.BODY)

	var physical := PhysicalPropertyComponent.new()
	physical.volume_cm3 = 66000.0
	ECSManager.physicals[row] = physical
	ECSManager.add_component_bit(row, ComponentMask.PHYSICAL)

	var composition := MaterialCompositionComponent.new({MaterialLibrary.MAT_BIOMASS: 1.0})
	ECSManager.materials[row] = composition
	ECSManager.add_component_bit(row, ComponentMask.MATERIAL)
	MaterialLibrary.recompute_mass(physical, composition)
	physical.set_temperature_c(37.0)

	ECSManager.needs[row] = NeedsComponent.new()
	ECSManager.add_component_bit(row, ComponentMask.NEEDS)
	ECSManager.schedules[row] = ScheduleComponent.new()
	ECSManager.add_component_bit(row, ComponentMask.SCHEDULE)
	ECSManager.perceptions[row] = PerceptionComponent.new()
	ECSManager.add_component_bit(row, ComponentMask.PERCEPTION)
	ECSManager.memories[row] = MemoryComponent.new()
	ECSManager.add_component_bit(row, ComponentMask.MEMORY)
	ECSManager.chemistries[row] = ChemistryComponent.new()
	ECSManager.add_component_bit(row, ComponentMask.CHEMISTRY)

	ECSManager.social_identities[row] = SocialIdentityComponent.new(node.node_id)
	ECSManager.add_component_bit(row, ComponentMask.SOCIAL_IDENTITY)
	ECSManager.ownerships[row] = OwnershipComponent.new(node.node_id)
	ECSManager.add_component_bit(row, ComponentMask.OWNERSHIP)

	# Citizens are PRESERVE_ENTITY: a person is not a commodity and must never be swept into a
	# ledger when their chunk downgrades.
	var materialization := MaterializationComponent.new()
	materialization.policy = ECSEnums.MaterializationPolicy.PRESERVE_ENTITY
	materialization.item_class = &"Citizen"
	ECSManager.materializations[row] = materialization
	ECSManager.add_component_bit(row, ComponentMask.MATERIALIZATION)

	ECSManager.lods[row] = LoDComponent.new(
		ECSEnums.LoD.ACTIVE if chunk.state == ECSEnums.LoD.ACTIVE else ECSEnums.LoD.SIMULATED
	)
	ECSManager.add_component_bit(row, ComponentMask.LOD)

	ECSEvents.emit_entity_created(
		handle, [&"Creature", &"Citizen"] as Array[StringName], ECSManager.position_of(row)
	)
	citizens_spawned += 1
	return handle


## Finds a faction's macro-entity row by faction id. Linear over faction cores, which is capped
## at 24 by ADR-12, so this never becomes a scan worth indexing.
static func faction_row(faction_id: int) -> int:
	for row in ECSManager.faction_cores:
		var core: FactionCoreComponent = ECSManager.faction_cores[row]
		if core.faction_id == faction_id:
			return row
	return -1


static func faction_core(faction_id: int) -> FactionCoreComponent:
	var row: int = faction_row(faction_id)
	return null if row < 0 else ECSManager.faction_cores[row]


func counters() -> Dictionary:
	return {
		"factions_created": factions_created,
		"citizens_spawned": citizens_spawned,
		"faction_stacks_spawned": stacks_spawned,
		"factions_left_abstract": skipped_abstract,
	}
