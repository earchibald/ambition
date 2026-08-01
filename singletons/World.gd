## World state: chunks, the player spawn, and the debug scenario boot path.
##
## MUST `extends Node` to be autoloadable. Owns no simulation logic — that lives in `ecs/systems`.
##
## Sprint 1 hosts a single hand-authored TestArena chunk. Sprint 2's WorldGrid generator replaces
## the producer without changing anything that consumes ChunkData.
extends Node

signal world_ready(chunk_id: Vector3i)

## Debug scenario boot path (scope doc §7). Budget: under 2 seconds to controllable, because this
## is the loop paid ~50 times a day. It skips DAG generation, world generation, and pre-warm.
const SCENARIO_TEST_ARENA: StringName = &"test_arena"

## The real thing: 500 years of history, a generated village, factions at their anchors. Slower
## than the arena by design — it is what Sprint 2 exists to produce.
const SCENARIO_WORLD: StringName = &"world"

var chunks: Dictionary = {}
var active_chunk: ChunkData = null
var player_chunk_id: Vector3i = Vector3i.ZERO
var scenario: StringName = SCENARIO_TEST_ARENA
var booted: bool = false

## Present only in the generated-world scenario. The debug arena is deliberately a single chunk
## with no grid, because that is what keeps it under the 2-second budget it exists to hold.
var grid: WorldGrid = null
var boot_report: Bootstrapper = null


func boot_scenario(name: StringName = SCENARIO_TEST_ARENA, seed_value: int = 1) -> void:
	scenario = name
	RNGService.reseed_all(seed_value)
	_clear_previous_world()
	chunks.clear()
	grid = null
	boot_report = null
	# The streaming system remembers which chunk ids were Active. Those ids are meaningless
	# against a grid that is about to be replaced, and keeping them makes the new world's chunks
	# look already-promoted.
	GameLoopManager.streaming.reset()

	var chunk: ChunkData
	if name == SCENARIO_WORLD:
		chunk = _boot_generated_world(seed_value)
	else:
		chunk = TestArena.build(Vector3i.ZERO)
		chunks[chunk.chunk_id] = chunk

	active_chunk = chunk
	player_chunk_id = chunk.chunk_id
	_spawn_player(chunk)
	booted = true
	world_ready.emit(chunk.chunk_id)


## Runs the full Sprint 2 boot: history, grid, populate, optional interregnum, Pre-Warm.
##
## The player is spawned by the caller AFTER this returns, which is the roadmap's order: Entity 0
## arrives last, into a world that is already running.
func _boot_generated_world(seed_value: int) -> ChunkData:
	boot_report = Bootstrapper.new()
	# Per-phase timing, printed every boot (scope doc §7: "Print a per-phase breakdown so a
	# regression is actionable"). The stopwatch lives HERE because ADR-20 bans wall-clock reads
	# inside `ecs/`; the bootstrapper reports phase completions and this closure times the gaps.
	var phase_started: Array[int] = [Time.get_ticks_usec()]
	boot_report.on_phase = func(phase: StringName) -> void:
		var now: int = Time.get_ticks_usec()
		print("boot phase %-12s %6.1f ms" % [phase, float(now - phase_started[0]) / 1000.0])
		phase_started[0] = now
	# THE PRE-WARM RUNS REAL SIMULATION TICKS. The injection point existed so a test could drive
	# it — and the shipped boot passed NOTHING, so `pre_warm_ticks_run` counted to 100 while zero
	# ticks ran and the roadmap's success state ("NPCs are already working when the player gains
	# control") was false every boot. The test proved the injection point; nothing proved the
	# production wiring, which is this codebase's signature defect at boot scale.
	boot_report.execute_boot_sequence(seed_value, false, func(_gravity_suppressed: bool) -> void:
		var home: ChunkData = boot_report.grid.chunk_at(Vector3i.ZERO)
		GameLoopManager._run_sim_tick(home)
	)
	grid = boot_report.grid
	chunks = grid.chunks
	# The village centre is the player's chunk, and it is Active from the first frame.
	var home: ChunkData = grid.chunk_at(Vector3i.ZERO)
	GameLoopManager.streaming.update_chunk_states(Vector3i.ZERO, grid)
	# Plan once at boot. Objectives are re-decided on the Macro tick, which is every ten real
	# seconds — so without this the village stands perfectly still for the first ten seconds a
	# player is looking at it, which is exactly the impression the Pre-Warm exists to avoid.
	for row in ECSManager.query(ComponentMask.FACTION_CORE):
		var core: FactionCoreComponent = ECSManager.faction_cores[row]
		GameLoopManager.planner.assign(
			GameLoopManager.planner.plan(core.current_objective, core.faction_id, grid)
		)
	return home


## Which way the stairs under `row` lead: -1 down, +1 up, 0 for "not on a stairwell".
##
## Identified by TILE POSITION rather than by a per-tile flag, because both directions share the
## `TILE_STAIRS` kind and the landing chunk places them at known coordinates.
func stairs_under(row: int) -> int:
	if grid == null:
		return 0
	var position: Vector3 = ECSManager.position_of(row)
	var chunk: ChunkData = chunk_containing(position)
	if chunk == null or chunk.chunk_id.x != 0 or chunk.chunk_id.y != 0:
		return 0
	var tile: Vector2i = chunk.world_to_tile(position)
	if tile == FloorGenerator.STAIR_DOWN_TILE:
		return -1
	if tile == FloorGenerator.STAIR_UP_TILE:
		return 1
	return 0


## Takes the player one floor down (-1) or up (+1).
##
## The destination floor's landing chunk is generated on demand, and the player arrives at the
## OPPOSITE stair — descend and you appear at the new floor's up-stair, which is where you would
## be if you had walked down. Arriving on the stair you left by would put you on a tile that
## sends you straight back.
func change_floor(direction: int) -> bool:
	if grid == null or direction == 0:
		return false
	var target: int = player_chunk_id.z + direction
	if target > WorldGrid.VILLAGE_FLOOR or target < FloorGenerator.DEEPEST_FLOOR:
		return false

	# The SAMPLER must move first. Collision and picking resolve terrain through it, and a frame
	# spent sampling the old floor while standing on the new one is a frame inside a wall.
	grid.current_floor = target
	player_chunk_id = Vector3i(0, 0, target)
	var landing: ChunkData = grid.chunk_at(player_chunk_id)
	active_chunk = landing

	var arrival: Vector2i = (
		FloorGenerator.STAIR_UP_TILE if direction < 0 else FloorGenerator.STAIR_DOWN_TILE
	)
	var ground: Vector3 = landing.tile_to_world(arrival.x, arrival.y)
	var row: int = EH.index_of(ECSManager.player_handle())
	ECSManager.set_position(row, Vector3(ground.x, ground.y + 0.9, ground.z))
	ECSManager.set_velocity(row, Vector3.ZERO)
	ECSManager.col_chunk_x[row] = 0
	ECSManager.col_chunk_y[row] = 0
	ECSManager.col_floor[row] = target

	# Re-stream around the new position, then tell the viewer to rebuild — the terrain it is
	# drawing belongs to a floor nobody is standing on any more.
	GameLoopManager.streaming.reset()
	GameLoopManager.streaming.update_chunk_states(player_chunk_id, grid)
	world_ready.emit(player_chunk_id)
	ECSEvents.player_changed_floor.emit(target - direction, target)
	return true


## Chunk that owns a world position, for callers that genuinely need tile coordinates.
func chunk_containing(world: Vector3) -> ChunkData:
	if grid == null:
		return active_chunk
	return grid.chunk_at(grid.chunk_id_for(world, player_chunk_id.z))


## Somewhere solid ground with headroom, near the middle of a chunk.
##
## The Sprint 1 arena hard-codes its spawn tile; a GENERATED chunk has no such guarantee, and
## spawning inside a wall reads as "the controls are broken" rather than as a spawn bug.
static func spawn_position_in(chunk: ChunkData) -> Vector3:
	var centre: int = WorldConstants.CHUNK_TILES / 2
	for radius in range(0, centre):
		for offset in range(-radius, radius + 1):
			for candidate in [
				Vector2i(centre + offset, centre - radius),
				Vector2i(centre + offset, centre + radius),
				Vector2i(centre - radius, centre + offset),
				Vector2i(centre + radius, centre + offset),
			]:
				if not chunk.is_solid(candidate.x, candidate.y):
					var ground: Vector3 = chunk.tile_to_world(candidate.x, candidate.y)
					return Vector3(ground.x, ground.y + 0.9, ground.z)
	# A chunk with no open tile at all is a generation failure, not a spawn failure.
	push_error("chunk %s has no open tile to spawn in" % chunk.chunk_id)
	return chunk.tile_to_world(centre, centre) + Vector3(0.0, 0.9, 0.0)


## The Residence interior when this is the generated origin village chunk; the centre-search
## fallback otherwise (a chunk handed in by a test, or a future scenario with no residence).
## The fallback matters: a residence tile that happened to be solid in some other chunk would
## spawn the player inside a wall, which reads as broken controls rather than a spawn bug.
static func residence_position(chunk: ChunkData) -> Vector3:
	var tile: Vector2i = FloorGenerator.RESIDENCE_TILE
	if (
		chunk.chunk_id == Vector3i.ZERO
		and not chunk.is_solid(tile.x, tile.y)
	):
		var ground: Vector3 = chunk.tile_to_world(tile.x, tile.y)
		return Vector3(ground.x, ground.y + 0.9, ground.z)
	return spawn_position_in(chunk)


## What collision and picking resolve terrain against. The grid when the world is streamed, the
## single chunk when it is the debug arena — both satisfy the same TileSampler contract, so the
## systems never branch on which one they have.
func sampler() -> TileSampler:
	return grid if grid != null else active_chunk


## Destroys everything the previous scenario left behind.
##
## Booting a scenario used to rebuild the chunk and re-dress the player while leaving every
## entity from the previous boot alive at its old position. So a second boot left the corpses,
## dropped items and creatures of the first one standing invisibly in the new arena — which is
## exactly how a "reload the level" button turns into a duplication bug.
##
## The player at row 0 is deliberately kept: it is the reserved handle (ADR-14) and `_spawn_player`
## re-dresses it in place.
func _clear_previous_world() -> void:
	# Mask 0 matches EVERY living row, positioned or not. Sweeping only POSITION missed the
	# entities that have no place in the world by design — faction ledgers above all — so each
	# boot stacked another set of faction cores on the last, and a lookup by faction id found a
	# stale one from a previous world.
	for row in ECSManager.query(0):
		if row == 0:
			continue
		ECSManager.destroy_entity(ECSManager.handle_of(row))
	ECSManager.flush_structural_changes()


func chunk_at(chunk_id: Vector3i) -> ChunkData:
	return chunks.get(chunk_id)


## Dresses row 0 as a living adventurer. Called by boot AND by the death loop's successor spawn,
## which is why it re-dresses the reserved row in place rather than allocating a new entity.
func _spawn_player(chunk: ChunkData) -> void:
	var handle: int = ECSManager.player_handle()
	var row: int = EH.index_of(handle)

	# The arena AUTHORS its spawn — west of the interior wall, so walking east exercises the
	# doorway, the ledge and the pit in order. The generated world spawns at the Adventurer's
	# Residence (Sprint 3 roadmap Step 6): every generation of adventurer wakes in the same house,
	# which is what makes a respawn read as an arrival rather than a reset.
	var spawn: Vector3 = (
		TestArena.spawn_position(chunk)
		if scenario == SCENARIO_TEST_ARENA
		else residence_position(chunk)
	)
	ECSManager.set_position(row, spawn)
	ECSManager.set_velocity(row, Vector3.ZERO)
	ECSManager.col_chunk_x[row] = chunk.chunk_id.x
	ECSManager.col_chunk_y[row] = chunk.chunk_id.y
	ECSManager.col_floor[row] = chunk.chunk_id.z
	ECSManager.add_component_bit(row, ComponentMask.POSITION)

	ECSManager.bounds[row] = BoundsComponent.new(Vector3(0.3, 0.9, 0.3))
	ECSManager.add_component_bit(row, ComponentMask.BOUNDS)

	var body := BodyComponent.new()
	body.strength = 10.0
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

	var perception := PerceptionComponent.new()
	ECSManager.perceptions[row] = perception
	ECSManager.add_component_bit(row, ComponentMask.PERCEPTION)

	var inventory := InventoryComponent.new()
	ECSManager.inventories[row] = inventory
	ECSManager.add_component_bit(row, ComponentMask.INVENTORY)

	var container := ContainerComponent.new()
	container.capacity_cm3 = 50000.0
	ECSManager.containers[row] = container
	ECSManager.add_component_bit(row, ComponentMask.CONTAINER)

	# Guest_Status is the Sprint 2 roadmap's explicit spawn requirement, and it was never granted:
	# the perception invariant "an unseen crime does not revoke Guest_Status" was tested against a
	# fixture tag no real player ever carried. The tag means the village treats the newcomer as a
	# guest until they are seen doing something that forfeits it.
	var player_chemistry := ChemistryComponent.new()
	player_chemistry.add_tag(&"Guest_Status")
	ECSManager.chemistries[row] = player_chemistry
	ECSManager.add_component_bit(row, ComponentMask.CHEMISTRY)

	var mind := MindComponent.new()
	# The Lens gates DETAIL, never PRESENCE, so run 1 is not blind.
	mind.seed_field_primer()
	ECSManager.minds[row] = mind
	ECSManager.add_component_bit(row, ComponentMask.MIND)

	ECSManager.lods[row] = LoDComponent.new(ECSEnums.LoD.ACTIVE)
	ECSManager.add_component_bit(row, ComponentMask.LOD)

	ECSManager.player_inputs[row] = PlayerInputComponent.new()
	ECSManager.add_component_bit(row, ComponentMask.PLAYER_INPUT)

	var identity := SocialIdentityComponent.new(WorldConstants.PLAYER_FACTION_ID)
	ECSManager.social_identities[row] = identity
	ECSManager.add_component_bit(row, ComponentMask.SOCIAL_IDENTITY)

	_grant_starting_kit(row)

	# ViewManager spawns visuals ONLY in response to this signal. Without it the player had no
	# body at all: the camera tracked an invisible point, and every movement bug looked instead
	# like a camera bug. Emitted last, so the entity is fully assembled before anyone sees it.
	ECSEvents.emit_entity_created(
		handle, [&"Player"] as Array[StringName], ECSManager.position_of(row)
	)


## "A starting inventory based on Village Wealth" (Sprint 2 roadmap spawn step). WITHDRAWN from
## the richest faction's ledger, never minted: the village equips its guest, so a starting kit
## that appeared from nowhere would break the economy conservation invariant on the first frame.
## A poor village hands over less; a village with no copper at all hands over nothing, and both
## are the correct reading of "based on wealth".
func _grant_starting_kit(row: int) -> void:
	var richest: FactionCoreComponent = null
	for core_row in ECSManager.query(ComponentMask.FACTION_CORE):
		var core: FactionCoreComponent = ECSManager.faction_cores[core_row]
		if richest == null or core.ledger_total() > richest.ledger_total():
			richest = core
	if richest == null:
		return
	var granted: int = richest.withdraw(
		MaterialLibrary.MAT_COPPER, clampi(richest.ledger_total() / 200, 1, 8)
	)
	if granted <= 0:
		return
	var kit: int = spawn_item(
		ECSManager.position_of(row), MaterialLibrary.MAT_COPPER, 112.0, granted
	)
	if not GameLoopManager.inventory.try_insert(row, kit):
		# A full pack cannot happen at spawn; if it ever does, the coins stay on the floor of the
		# Residence rather than vanishing — conservation again.
		push_warning("starting kit did not fit the player's pack; left at the Residence")


## Spawns a simple creature for testing and for the perception/combat gates.
func spawn_creature(position: Vector3, species: StringName = &"SPC_CORPSE_RAT") -> int:
	var handle: int = ECSManager.allocate_entity()
	var row: int = EH.index_of(handle)
	var is_rat: bool = species == &"SPC_CORPSE_RAT"

	ECSManager.set_position(row, position)
	ECSManager.add_component_bit(row, ComponentMask.POSITION)
	ECSManager.col_chunk_x[row] = player_chunk_id.x
	ECSManager.col_chunk_y[row] = player_chunk_id.y
	ECSManager.col_floor[row] = player_chunk_id.z

	var extents: Vector3 = (
		Vector3(0.125, 0.125, 0.25) if is_rat else Vector3(0.3, 0.9, 0.3)
	)
	ECSManager.bounds[row] = BoundsComponent.new(extents)
	ECSManager.add_component_bit(row, ComponentMask.BOUNDS)

	var body := BodyComponent.new()
	body.max_health = 8.0 if is_rat else 100.0
	body.health = body.max_health
	body.strength = 2.0 if is_rat else 10.0
	body.structural_toughness = 1.0
	ECSManager.bodies[row] = body
	ECSManager.add_component_bit(row, ComponentMask.BODY)

	var physical := PhysicalPropertyComponent.new()
	physical.volume_cm3 = 377.0 if is_rat else 66000.0
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
	ECSManager.lods[row] = LoDComponent.new(ECSEnums.LoD.ACTIVE)
	ECSManager.add_component_bit(row, ComponentMask.LOD)

	ECSEvents.emit_entity_created(
		handle, [&"Creature"] as Array[StringName], position
	)
	return handle


## Spawns a dropped item that falls and comes to rest via the loose-item integrator.
## A tagged lump of matter with the components a reaction needs: chemistry to react, physical and
## material to carry energy, bounds so the SpatialHash can find it.
func spawn_reactant(
	at: Vector3, material_id: StringName, volume_cm3: float, tag: StringName
) -> int:
	var handle: int = ECSManager.allocate_entity()
	var row: int = EH.index_of(handle)
	ECSManager.set_position(row, at)
	ECSManager.add_component_bit(row, ComponentMask.POSITION)
	ECSManager.bounds[row] = BoundsComponent.new(Vector3(0.5, 0.5, 0.5))
	ECSManager.add_component_bit(row, ComponentMask.BOUNDS)

	var physical := PhysicalPropertyComponent.new()
	physical.volume_cm3 = volume_cm3
	var composition := MaterialCompositionComponent.new({material_id: 1.0})
	MaterialLibrary.recompute_mass(physical, composition)
	physical.set_temperature_c(20.0)
	ECSManager.physicals[row] = physical
	ECSManager.materials[row] = composition
	ECSManager.add_component_bit(row, ComponentMask.PHYSICAL | ComponentMask.MATERIAL)

	var chemistry := ChemistryComponent.new()
	chemistry.add_tag(tag)
	ECSManager.chemistries[row] = chemistry
	ECSManager.add_component_bit(row, ComponentMask.CHEMISTRY)

	var tags: Array[StringName] = [tag]
	ECSEvents.emit_entity_created(handle, tags, at)
	return handle


## A readable stand: interact (`E`) to learn what is inscribed on it. Too heavy to pick up —
## `capacity` refusal is not how it works; the `Inscribed` tag reroutes the TAKE intent into a
## read before the inventory is ever consulted.
func spawn_lectern(at: Vector3, runes: Array[StringName]) -> int:
	var handle: int = spawn_item(at, MaterialLibrary.MAT_STONE, 40000.0, 1)
	var row: int = EH.index_of(handle)
	ECSManager.chemistries[row].add_tag(&"Inscribed")
	ECSManager.loose_items[row].inscribed_runes = runes.duplicate()
	return handle


## Something already alight, so the `Absorb_Heat` rune has an environmental resource to consume
## and the quench rule has a fire to put out.
func spawn_brazier(at: Vector3) -> int:
	var handle: int = spawn_reactant(at, MaterialLibrary.MAT_STONE, 4000.0, &"Burning")
	var row: int = EH.index_of(handle)
	var source := HeatSourceComponent.new()
	source.stored_energy = 5000000.0
	ECSManager.heat_sources[row] = source
	ECSManager.add_component_bit(row, ComponentMask.HEAT_SOURCE)
	return handle


func spawn_item(
	position: Vector3, material_id: StringName, volume_cm3: float, quantity: int = 1
) -> int:
	var handle: int = ECSManager.allocate_entity()
	var row: int = EH.index_of(handle)

	ECSManager.set_position(row, position)
	ECSManager.add_component_bit(row, ComponentMask.POSITION)
	ECSManager.bounds[row] = BoundsComponent.new(Vector3(0.1, 0.1, 0.1))
	ECSManager.add_component_bit(row, ComponentMask.BOUNDS)

	var physical := PhysicalPropertyComponent.new()
	physical.volume_cm3 = volume_cm3
	physical.quantity = quantity
	ECSManager.physicals[row] = physical
	ECSManager.add_component_bit(row, ComponentMask.PHYSICAL)

	var composition := MaterialCompositionComponent.new({material_id: 1.0})
	ECSManager.materials[row] = composition
	ECSManager.add_component_bit(row, ComponentMask.MATERIAL)
	MaterialLibrary.recompute_mass(physical, composition)
	physical.set_temperature_c(20.0)

	var chemistry := ChemistryComponent.new()
	for tag in MaterialLibrary.innate_tags(material_id):
		chemistry.add_tag(tag)
	ECSManager.chemistries[row] = chemistry
	ECSManager.add_component_bit(row, ComponentMask.CHEMISTRY)

	ECSManager.qualities[row] = QualityComponent.new()
	ECSManager.add_component_bit(row, ComponentMask.QUALITY)
	ECSManager.loose_items[row] = LooseItemComponent.new()
	ECSManager.add_component_bit(row, ComponentMask.LOOSE_ITEM)
	ECSManager.lods[row] = LoDComponent.new(ECSEnums.LoD.ACTIVE)
	ECSManager.add_component_bit(row, ComponentMask.LOD)

	ECSEvents.emit_entity_created(handle, [&"Item"] as Array[StringName], position)
	return handle
