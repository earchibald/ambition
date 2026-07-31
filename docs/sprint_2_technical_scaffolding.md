Sprint 2 Technical Scaffolding

Target Audience: Lead Coding Agent
Context: This document provides the concrete code structures and data types to implement sprint_2_implementation_roadmap.md. It includes specific, rigid remediations to prevent Infinite Gold exploits, LoD AI infinite loops, and projectile physics crashes on chunk borders.

AUTHORITATIVE CORRECTIONS (ADR / review): chunk_id is already Vector3i here (good). Two
fixes below: (1) wealth de/materialization must cover ALL faction-owned physical matter
(stockpile + NPC inventories + owned loose items), not just the stockpile zone, and must be
transactional/idempotent to close the boundary-oscillation duplication window (review D1).
(2) Ownership uses one representation: an OwnershipComponent{faction_id} (review C7/D1).

1. The DAG Data Structure (History Generation)

The history graph must be generated purely in memory.

# dag_structures.gd
class DAGNode extends RefCounted:
    var node_id: int
    var type: NodeType # enum, e.g., FACTION, LOCATION, ARTIFACT
    var status: NodeStatus = NodeStatus.ACTIVE
    var birth_epoch: int
    var tags: Array[String] = []
    
    # Spatial Anchor (GESTALT FIX)
    var anchor_chunk_id: Vector3i = Vector3i.ZERO # Exact chunk to spawn leaders/stockpiles
    
    # Faction Specific Data
    var population: int = 0
    var abstract_wealth_ledger: Dictionary = {} # { "MAT_IRON": 500, "MAT_GOLD": 100 }



The Generation Loop (Safety Constraints)

The DAGGenerator must be strictly bound.

# DAGGenerator.gd
const MAX_EPOCHS: int = 50
var current_epoch: int = 0
var nodes: Dictionary = {} 
var edges: Array[Dictionary] = [] # { source_id, target_id, event_type, epoch }

func run_history_generation():
    for i in range(MAX_EPOCHS):
        current_epoch = i
        _process_epoch()
    return _get_active_world_state() 



2. World Generation & The Synchronous Village Fix

Chunks must be mapped, but we cannot lazy-load the Village or the Pre-Warm AI will crash looking for paths.

# WorldGrid.gd
const CHUNK_SIZE: int = 64 

class ChunkData extends RefCounted:
    var chunk_id: Vector3i 
    var state: LoD = LoD.ABSTRACTED
    var biome_tag: StringName
    
    var tile_map: PackedInt32Array # The grid
    var height_map: PackedFloat32Array # 2.5D per-tile elevation (fluid flow, drops) — ADR-3
    var volume_pools: Dictionary = {} # Boundary flood buffer { MAT_ID: Total_Volume }
    var swarm_population: int = 0 # Tier-1 abstract count (capped during interregnum — ADR-11)
    var wealth_materialized: bool = false # LoD de/materialization idempotency guard (D1)
    var tile_map_dirty: bool = false
    var topology_dirty: bool = false
    var nav_region_dirty: bool = false

func initialize_world(dag_active_nodes: Array):
    # CRITICAL: Force synchronous generation of Village (Floor 0)
    for chunk in get_village_chunks():
        _generate_tile_map_and_navmesh(chunk)
        chunk.state = LoD.SIMULATED # Ready for Pre-Warm
        
    # Leave Dungeon chunks as ABSTRACTED (Lazy generation)



3. The DAG-to-ECS Translator (Spatial Binding)

Do not let abstract nodes wander into the simulation. They must be converted into Sprint 1 ECS structures at their specific anchors.

# DAGInstantiator.gd
func translate_faction_to_ecs(faction_node: DAGNode):
    # GESTALT FIX: Rely on the Anchor Chunk mapped during World Gen
    var spawn_chunk = faction_node.anchor_chunk_id
    
    # 1. Setup the abstract macro-entity for the GrayBox ledger
    var macro_entity = ECSManager.create_entity()
    ECSManager.add_component(macro_entity, FactionCoreComponent.new(faction_node))
    
    # 2. Spawn the Tier 2 physical workforce
    for i in range(faction_node.population):
        var citizen = ECSManager.create_entity()
        ECSManager.add_component(citizen, PositionComponent.new(spawn_chunk))
        ECSManager.add_component(citizen, NeedsComponent.new())
        ECSManager.add_component(citizen, ScheduleComponent.new())



4. The LoD Handshake (Anti-Exploit & Projectile Fixes)

When a chunk shifts state, data must perfectly sync without duplication, physics explosions, or AI loops.

# LoDSystem.gd (Runs on Simulation Tick)
func update_chunk_states(player_chunk_id: Vector3i):
    var active_chunks = _get_active_set_2_5d(player_chunk_id) # 3x3 same-floor + up/down landings (ADR-3)
    
    # 1. Downgrade chunks
    for chunk in previously_active_chunks:
        if not active_chunks.has(chunk):
            _shift_to_simulated(chunk)
            
    # 2. Upgrade chunks
    for chunk in active_chunks:
        if chunk.state != LoD.ACTIVE:
            _shift_to_active(chunk)

func _shift_to_simulated(chunk: ChunkData):
    chunk.state = LoD.SIMULATED
    var entities = ECSManager.get_entities_in_chunk(chunk.chunk_id)
    for e in entities:
        # COHESION FIX: Projectiles cannot sleep. Resolve them immediately.
        if ECSManager.has_tag(e, "Kinetic_Ephemeral"):
            _resolve_abstract_hit(e)
            ECSManager.destroy_entity(e)
            continue
            
        # AI FIX: Wipe action queues so the JobTemplate/Utility AI shifts to
        # "Simulated_Resolver" mode rather than re-triggering physical animations.
        if ECSManager.positions.has(e):
            ECSManager.positions[e].velocity = Vector3.ZERO
        if ECSManager.action_queues.has(e):
            ECSManager.action_queues[e].clear()
            
    # ANTI-EXPLOIT FIX: Physical Items -> Ledger Sync
    _dematerialize_faction_wealth(chunk)
            
func _shift_to_active(chunk: ChunkData):
    chunk.state = LoD.ACTIVE
    
    # COHESION FIX: The Boundary Flood Safe-Guard
    if chunk.volume_pools.has("MAT_WATER") and chunk.volume_pools["MAT_WATER"] > 0:
        var flood_source = ECSManager.create_entity()
        ECSManager.add_component(flood_source, FloodSourceComponent.new(chunk.volume_pools["MAT_WATER"])) 
        
    # ANTI-EXPLOIT FIX: Ledger -> Physical Items Sync
    _materialize_faction_wealth(chunk)

func _materialize_faction_wealth(chunk: ChunkData):
    # IDEMPOTENCY GUARD: never materialize a chunk already flagged materialized.
    if chunk.wealth_materialized:
        return
    chunk.wealth_materialized = true
    # 1. Find FactionCore anchored here.
    # 2. Instantiate fungible commodity stacks from ledger amounts with
    #    OwnershipComponent{faction_id} + MaterializationComponent{policy=LEDGERIZE}.
    # 3. Reconstruct preserved identity manifests for equipped/unique/container/caravan
    #    items whose policy is PRESERVE_ENTITY, CONTAINER_MANIFEST, or CARAVAN_MANIFEST.
    # 4. SET ledger abstract value to 0 to prevent double-spawning on LoD toggle.
    pass
    
func _dematerialize_faction_wealth(chunk: ChunkData):
    # IDEMPOTENCY GUARD.
    if not chunk.wealth_materialized:
        return
    chunk.wealth_materialized = false
    # D1 FIX: sum ALL faction-owned FUNGIBLE physical matter in the chunk, not just the
    # stockpile zone: (a) commodity stacks in [Zone_Stockpile], (b) fungible stacks in NPC
    # InventoryComponents, (c) owned loose commodity stacks dropped on the floor. Add those
    # back to the FactionCore ledger, then destroy those physical entities.
    #
    # Identity-bearing items are not ledgerized: equipped gear, named artifacts, quest items,
    # containers/stashes, and caravan cargo preserve entity/manifests according to
    # MaterializationComponent.policy. Player-held items stay with the (still-Active) player
    # and are never swept. This closes the boundary dupe window without erasing unique items;
    # add a property test: cross a boundary N times -> total faction value invariant.
    pass



5. The Off-Screen Economy (Memory Safe)

Abstract chunks do not have PhysicalPropertyComponent entities. Update ledgers only.

# GrayBoxSystem.gd (Runs on Macro Tick)
func process_macro_economy():
    for faction_id in DAG.get_active_factions():
        var faction_core = ECSManager.faction_cores[faction_id]
        
        if faction_core.culture_tags.has("[Mining]"):
            # DO NOT spawn physical gold items. Update the dictionary ledger.
            faction_core.abstract_wealth_ledger["MAT_GOLD"] += 50 



6. The Bootstrapper Sequence (Strict Priority & Physics Fix)

# Bootstrapper.gd
func execute_boot_sequence(is_player_death: bool):
    print("Initiating World Boot...")
    
    # 1. GENERATE GRID FIRST (Interregnum needs zones to exist)
    _generate_world_grid_and_anchors()
    
    # 2. Macro-Time Skip (If applicable)
    if is_player_death:
        print("Running 1-Year Interregnum...")
        for i in range(12): 
            ECSManager.process_interregnum_month() # coarse monthly pass, not the hourly Macro tick
            
    # 3. Physics Pre-Warm
    print("Running Day 0 Pre-Warm...")
    for i in range(100):
        # PHYSICS PATCH: Pre-warm items snap to tables, bypassing gravity collision.
        ECSManager.process_sim_tick(true) # True = PreWarm_Mode
        
    # 4. Player Control
    var player_id = _spawn_entity_0()
    ECSManager.add_component(player_id, ChemistryComponent.new(["Guest_Status"]))



7. Integrated Corrections (open review items landing in Sprint 2)

Boundary combat / cross-LoD interaction (review D2): actions resolve in the ATTACKER's LoD.
A hostile action from a Simulated chunk into an Active chunk (or exactly on a seam) either
(a) force-promotes the target chunk to Active if the target is player-adjacent, or
(b) resolves abstractly (math damage, no animation) if not. Kinetic_Ephemeral projectiles
never sleep at a boundary — resolve via abstract raycast and despawn (already in _shift_to_
simulated). State the chosen branch per action type in the ActionResolutionSystem.

Simulated mover progress (review G4): when downgrading to Simulated, DO NOT discard position.
Set velocity=0 for physics but record current_edge/edge_progress/edge_speed on the abstract
graph so a world coordinate can be reconstructed for interception and re-promotion to Active.

LoD materialization policy (review 2026-07-31 A3): only fungible commodity stacks with
MaterializationPolicy.LEDGERIZE become ledger entries. Equipped gear, artifacts, quest items,
containers/stashes, and caravan cargo preserve identity manifests and reconstruct on
promotion. This keeps the D1 anti-dupe transaction from destroying item identity.

Topology invalidation (review 2026-07-31 A4): mining, collapse, barricades, explosions, and
other tile changes mark ChunkData tile_map_dirty/topology_dirty/nav_region_dirty. Collision
uses the current tile map immediately; AbstractGraph and NavigationServer3D rebuild
asynchronously, with grid A* fallback while dirty.

Faction & DAG caps (ADR-12): the LoD/DAG bootstrap enforces the faction cap (default 24) and
FactionCoreComponent.diplomacy top-K (default 12); excess factions merge/abstract into gray-box pools.
Runtime DAG compaction runs on a slow cadence (see DAG doc §6).
