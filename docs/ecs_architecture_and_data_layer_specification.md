ECS Architecture & Data Layer Specification

Target Audience: Lead Coding Agent / Systems Architect
Context: This document outlines the core data layer for "The Living Delve." The ECS (Entity Component System) is the absolute ground truth of the game world, strictly decoupled from the rendering engine.

AUTHORITATIVE NOTE: docs/architecture_decisions.md (the ADR) governs all cross-cutting
decisions and overrides this document where they disagree. This spec has been updated to
match the ADR; the ADR remains the source of truth. Key ADRs referenced below: ADR-2
(physics/spatial/pathfinding), ADR-3 (2.5D world, chunk_id), ADR-7 (entity lifecycle),
ADR-8 (RNG), ADR-9 (ticks), ADR-10 (performance), ADR-13 (query cache), ADR-14 (player
identity). Note per ADR-1: the world is NOT deterministically re-simulatable; continuity
comes from serialization (ADR-6), not seed replay.

1. Core Philosophy: The Engine is Just a Viewer

The Godot engine (or any rendering engine used) must be treated purely as a "Viewer" for the ECS.

The ECS runs independently in pure data (e.g., a Rust module, C# pure classes, or heavily optimized GDScript/GECS).

Visuals (3D models, sprites, Godot physics nodes) are only instantiated when an entity's physical presence is required by the player's proximity.

If the Viewer crashes or is detached, the ECS simulation must be able to continue running in the background, simulating economies, wars, and migrations.

2. The Tick Hierarchy

To manage computation, the ECS does not run on the rendering framerate (_process). It relies on a decoupled, tiered tick system:

Micro Tick (60Hz - Engine Driven): Strictly for player-adjacent actions. Physics, collision, Cellular Automata fluid dynamics, and real-time combat animations. The ECS only reads/writes to this for entities in the Active LoD state.

Simulation Tick (2Hz - ECS Driven): The heartbeat of the dungeon. This is when Tier 2 entities (citizens) update their pathfinding (node-to-node), process their jobs, consume food, and trade. Also drives LoD state updates. (ADR-9: fixed at 2Hz — earlier "1Hz-2Hz" language is superseded.)

Macro Tick (ECS Driven): Fires every 10 real seconds and advances 1 in-game hour (ADR-9). Drives economy/gray-box, climate/weather, LLM reasoning triggers, and schedules' day-night cycle. Game calendar (24 hours/day, 360 days/year) derives from hour counts. NOTE: the 1-year Interregnum does NOT run thousands of hourly ticks; it uses a dedicated coarse pass of 12 monthly ticks operating on ledgers/abstract data (ADR-9/ADR-11).

3. Level of Detail (LoD) States & The Boundary Problem

Every entity has an LoDComponent that dictates how deeply it is simulated based on the player's proximity. The map is divided into Chunks. Per ADR-3, the world is 2.5D: floors are discrete planes and chunk_id is Vector3i(x, y, floor). The Active set is the 3x3 same-floor neighborhood around the player's chunk (9 chunks) PLUS the single entry/landing chunk of the floor directly above and below (for stair/elevator transitions) — NOT a full 3x3x3 cube. (This supersedes the older "8 immediate neighbors" phrasing.)

State 0: Active (Player is in chunk):

Spawns a linked Engine Node.

System uses exact Vector3 coordinates.

Fluids flow via Cellular Automata grids.

State 1: Simulated (Adjacent zone/floor):

Engine Node is pooled/destroyed.

Abstract Movement: Entities do not walk. They traverse a node-based pathfinding graph. Their position is interpolated mathematically. If the player rapidly enters this chunk, the ECS calculates their interpolated coordinate and instantly spawns the physical Active node there (allowing the player to intercept caravans).

State 2: Abstracted (Far away):

Individual AI is suspended. Entities are grouped into "Faction Pools".

Only Macro Ticks apply (e.g., "Goblin Faction mined 50 ore").

The Fluid Boundary (Handling Edge-Cases & The Flood Buffer)

When a spreading liquid (e.g., a flood of MAT_WATER) in an Active chunk reaches the border of a Simulated chunk, it does not keep calculating individual grid cells.

The excess fluid volume is transferred into a VolumePool integer on the Simulated chunk's abstract data.

The Flood Buffer Rule: If the player walks toward that chunk, turning it Active, the system CANNOT instantly instantiate the VolumePool. It must spawn a [Flood_Source] invisible entity on the boundary that "pumps" a maximum safe volume (e.g., 50 units) per Micro Tick into the CA grid. This creates a computationally safe flooding effect and prevents a 10,000-unit tsunami from freezing the CPU.

4. Entity Tiers & Data Representation

Not everything needs an Entity ID. We use a tiered approach to save memory.

Tier 1: Swarms & Environment (The Abstractions)

Implementation: Not individual entities. The Chunk or Zone entity holds integer population
data (`ChunkData.swarm_population` or `ZonePopulationComponent`, per the registry).

System: A SwarmGrowthSystem runs on the Macro Tick. If LoD shifts to Active, the system consumes RatCount to spawn physical mobs.

Tier 2: Citizens & Workers (The Core Simulation)

Implementation: Unique entities (ID: 4092, Name: "Snarl").

Components: Needs, JobQueue, Inventory, SocialIdentityComponent, ProfessionComponent.

System: Schedule-aware Utility AI plus faction JobTemplate assignments. Driven by the
Simulation Tick. A true search planner is a possible future implementation behind the same
planner interface, not the current backbone.

Tier 3: Leaders & Unique NPCs (The LLM Puppets)

Implementation: Unique entities with an LLMPromptComponent.

System: Driven by the Macro Tick. Sets high-level objectives.

5. Core Components Spec

The coding agent should implement these as pure, memory-contiguous structs or lightweight classes where possible.

Physical & Chemical State

PositionComponent -> floor_id: int, chunk_id: Vector3i (x, y, floor per ADR-3), exact_pos: Vector3, velocity: Vector3, current_node_id: int (for abstract pathing). NOTE: chunk_id is Vector3i everywhere (supersedes any `int` usage in older scaffolding).

PhysicalPropertyComponent -> quantity: int, mass_kg: float, volume_cm3: float, temperature: float, heat_capacity: float, phase: enum (Solid, Liquid, Gas — use a GDScript enum, not a string). (Note: Quantity is mandatory for item stacking to prevent memory fragmentation. Per ADR/C5, mass_kg is a derived cache: authoritative mass = volume_cm3 * sum(composition_pct * material_density); recompute on composition/volume change.)

MaterialCompositionComponent -> materials: Dict[MaterialID, float] (e.g., {MAT_IRON: 0.9, MAT_WATER: 0.1}).

ChemistryComponent -> active_tags: Array[StringName] (e.g., [&"Burning", &"Toxic"]).

QualityComponent -> condition: enum (Pristine, Chipped, Ruined, Scrap).

MaterializationComponent -> policy: enum (MaterializationPolicy.LEDGERIZE,
MaterializationPolicy.PRESERVE_ENTITY, MaterializationPolicy.CONTAINER_MANIFEST,
MaterializationPolicy.CARAVAN_MANIFEST, MaterializationPolicy.GC_ELIGIBLE), item_class:
StringName, manifest_id: int. This controls LoD
dematerialization so fungible commodity stacks can become ledgers while equipped, unique,
container, stash, and caravan items keep identity.

Biology & Cognition

NeedsComponent -> hunger: float, energy: float, morale: float.

BodyComponent -> max_health: float, health: float, stamina: float, strength: float,
mutations: Array[StringName], skills: Dict[StringName, float] (e.g., Blade_Familiarity: 15.5),
exposure: Dictionary[StringName, float].

MindComponent -> known_runes: Array[RuneID], insight: Dict[StringName, int] (for the Tactical Lens), faction_reputations: Dict[FactionID, float], language_fluency: Dict[StringName, int].

PerceptionComponent -> sight_range_m: float, fov_degrees: float, hearing_sensitivity: float,
awareness_state: enum (Unaware, Suspicious, Investigating, Combat), last_known_targets:
Dict[EntityHandle, Vector3].

SensoryEmitterComponent -> noise_radius_m: float, visibility_modifier: float, scent_tags:
Array[StringName]. Transient impacts/noises may instead be EphemeralComponent payloads with
the same fields.

AI & Logistics

LoDComponent -> current_state: Enum (Active, Simulated, Abstracted).

InventoryComponent -> held_items: List[EntityHandle], total_volume_used: float, sub_containers: List[EntityHandle].

ContainerComponent -> capacity_cm3: float, accepts_tags: Array[StringName], rejects_tags:
Array[StringName], allow_nested_container: bool.

JobComponent -> current_action: StringName, target_entity: EntityHandle, target_location:
Vector3, claimed_by: EntityHandle, status: JobStatus enum.

ProfessionComponent -> profession: StringName (legacy prose like `[Prof_Hauler]` is shorthand
for this value).

SocialIdentityComponent -> faction_id: int, loyalty: float, prestige: float.

OwnershipComponent -> faction_id: int (the only item ownership representation).

HeatSourceComponent -> stored_energy: float, max_temperature: float, fuel_materials:
Array[MaterialID]. Stations/forges use this with the material heat model; there is no
separate ad-hoc station-energy component.

FactionCoreComponent (For abstract Faction Entities) -> faction_id: int, culture_tags: List[StringName], diplomacy: Dict[FactionID, RelationshipState] (top-K only), abstract_wealth_ledger: Dictionary, abstract_population: int, faction_memory: Array[MemoryEvent].

6. Core Systems (Logic Loops)

The coding agent should implement these as isolated processors that iterate over entities with specific component masks.

FluidDynamicsSystem (Micro Tick): Processes Cellular Automata for spreading liquids in Active chunks and handles boundary transfers via the Flood Buffer.

MetabolismSystem (Simulation Tick): Iterates NeedsComponent and BodyComponent. Hunger RISES
toward 100; energy and morale FALL toward 0 (see sprint_1_technical_scaffolding §7 for rates
and sign conventions). Also owns BodyComponent.stamina drain, including environmental exposure
terms such as cold.

JobResolutionSystem (Simulation Tick): Evaluates JobComponent.

If Active: Pushes physical ActionIntents to the entity's queue. Targeting comes from
PickSystem / SpatialHash overlap, not physics raycasts.

If Simulated (The Resolver Fix): Aborts all physical ActionIntents. Calculates pure math (e.g., reducing MAT_COPPER from the chunk and adding it to the entity's inventory after N ticks without physics checks).

EconomySystem (Macro Tick): Calculates Scarcity_Index for zones.

GrayBoxSystem (Crucial): Runs on Macro Tick. Monitors the total wealth/resources of edge nodes (Village, Deepest Floor). Spawns new entities (immigrants/traders) or deletes resources (taxes/spoilage) to prevent infinite loops and death spirals. Updates abstract_wealth_ledger directly for non-Active chunks.

PerceptionSystem (Simulation Tick, with Micro queries for Active combat): Resolves sight,
hearing, stealth, and witness events without omniscience. Sight uses a cone plus DDA line of
sight through `tile_map` and temporary blockers such as steam/smoke. Hearing consumes
SensoryEmitter / Ephemeral noise payloads, applies wall/material attenuation, and creates
`Investigating` awareness with a last-known location. A crime only becomes reputation data
when a WitnessEvent is generated by a perceiving guard/victim and then propagated through the
memory/gossip pipeline.

7. Physics, Spatial, & Pathfinding Systems (ADR-2)

"Godot is a dumb viewer" stands. The following ECS-owned systems replace the banned
CharacterBody3D / RigidBody3D / Area3D / move_and_slide / physics-raycast stack. The ONE
sanctioned engine exception is NavigationServer3D, used only as a stateless local-steering
accelerator inside Active chunks (see below).

SpatialHashSystem (Micro Tick): Maintains a uniform spatial hash per Active chunk,
{ cell -> [entity_id] }, updated each Micro tick. This is the substrate for all overlap /
proximity / picking queries. No Godot colliders are used.

CollisionResolveSystem (Micro Tick): After velocity is integrated into exact_pos, sweeps
the entity's AABB via grid-DDA against the chunk tile_map solid cells and slides/stops it.
This replaces move_and_slide for walls, floors, and drops (2.5D: elevation from the
heightmap). Loose-item motion (thrown/scattered/dropped solids) uses the same integrator +
grid collision with a sleep-on-rest rule (resolves review B4/D7).

PickSystem (query, not a tick): Crosshair and mouse picking cast a camera ray and march it
(DDA) through the spatial hash + tile_map in pure math to find the targeted entity/tile.
Melee/AoE overlap tests query the spatial hash directly. No physics raycasts.

Pathfinding (two tiers):
  - AbstractGraph (ECS-owned, source of truth): a topological graph built from each
    floor's tile_map at generation time (nodes = room centroids / portals / stairs; edges
    weighted by distance + hazard). Drives Simulated/Abstracted movers and high-level
    Active routing. Simulated movers store current_edge, edge_progress (0..1), and
    edge_speed so a world coordinate can be reconstructed on demand for interception and
    promotion to Active (resolves review G4).
  - NavigationServer3D (SANCTIONED EXCEPTION, Active only): local steering / path
    smoothing inside Active chunks, baked per Active chunk, owning no game state. Fall back
    to grid A* on the tile_map if a region is not yet baked. Boundary hand-off: crossing
    into a Simulated chunk converts the remaining route to AbstractGraph edges (and back on
    promotion).

Topology invalidation (mutable world): Any system that changes tile solidity, elevation, or
traversal hazard (mining, collapse, barricade, explosion, flood damage) must mark the owning
ChunkData `tile_map_dirty`, `topology_dirty`, and, if Active, `nav_region_dirty`. Collision
uses the current tile_map immediately. AbstractGraph edges crossing dirty tiles are rejected
or hazard-penalized until rebuilt. Active NavigationServer3D regions are rebaked
asynchronously; while dirty or unavailable, local steering falls back to grid A* on tile_map.

LoD materialization policy: Dematerialization ledgerizes only fungible commodity stacks with
MaterializationPolicy.LEDGERIZE. Equipped gear, named artifacts, quest items, containers,
Residence stash contents, and caravan cargo preserve identity as serialized manifests and are
reconstructed on promotion. Unowned junk/filth follows entropy/GC policy. This prevents the
D1 anti-dupe fix from erasing identity-bearing items.

8. Entity Lifecycle, Registries, RNG & Serialization (ADR-7 / ADR-8 / ADR-6)

Canonical Registries & Atomic Destroy: ECSManager maintains a single canonical list of all
component registries (positions, physicals, needs, action_queues, spatial hash membership,
...). destroy_entity(handle) MUST remove the entity from EVERY registry and queue in one
operation. (Prefer a columnar/archetype store so destroy is a single op.)

Generational Handles: Entity references are { index, generation }. Reusing an index bumps
its generation, invalidating stale references so dangling reads are detectable. This
replaces any monotonic-id-counter scheme and prevents id exhaustion across death loops.

Archetype / Query Cache (ADR-13): Systems iterate an archetype index (entities grouped by
component mask), NOT linear get_all_entities_with_component scans.

RNGService (ADR-8): One service with named, independently-seeded streams (worldgen, dag,
combat, mutation, economy, loot), seeded from a master world seed. Stream states are
serialized in saves. No cross-platform determinism is promised (ADR-1) — only that a loaded
save continues from the saved stream state.

Serialization (ADR-6): The game supports full mid-run "Save & Quit" AND between-run
persistence. Design every component to serialize cleanly. The versioned save payload is
authoritative and captures: all component registries; the DAG (incl. runtime edges); the
WorldGrid (chunk states, tile_maps, ledgers, volume_pools, per-floor lazy-gen status);
master seed + RNG stream states; and the Lineage Journal. Unvisited lazy floors save only
their seed + gen-status (regenerated on load); visited/mutated state is saved explicitly.
A schema_version field enables forward migration. The concrete save schema and workstream
are defined in `docs/persistence_and_save_architecture.md`.

9. Canonical Player Identity (ADR-14)

Player = Entity 0 = Faction 0. A synthetic Faction-0 DAG node is registered at world gen so
LLM targeting and the Validation Gate resolve when a leader targets the player. Provide
is_player(faction_id). (The "Faction 14: The Player" example in older LLM text is void.)

10. Performance Budgets (ADR-10)

Reference hardware ~ M1 / Ryzen 5. Targets: 60 FPS / 16.6 ms; combined ECS Micro-tick
systems <= 8 ms/frame; Active (physical) entities target <= 1,500, hard cap 3,000 before
forced abstraction; total individual entities <= ~10,000 (Tier 1 swarms are integers, not
entities); CA fluids simulate only active (dirty) cells via a sparse set, budget <= 20,000
cell-updates / Micro tick, overflow -> VolumePool/flood buffer. A Rust/GDExtension escape
hatch is APPROVED behind stable interfaces for CA, spatial hash/grid raycast, and
serialization; hot data uses Packed*Array to ease porting.
