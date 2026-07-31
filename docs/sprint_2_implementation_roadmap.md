Implementation Roadmap: Sprint 2 (The World Canvas & Macro-Simulation)

Target Audience: Lead Coding Agent
Objective: Transition from a hardcoded ECS testing room to a procedurally generated world driven by the DAG history. Implement the Macro-Tick, Level of Detail (LoD) chunk transitions, and the economic Pre-Warm sequence.

Step 1: The DAG History Generator (The Pre-Game)

The Objective: Generate a 500-year history graph in memory before the 3D world is ever rendered.
Required Implementation:

Build the DAGGenerator class (pure data/math).

Implement the Epoch Loop to generate Nodes (Factions, Locations) and Edges (Founded, Destroyed, Conquered).

Create the translation function: get_active_world_state() -> Array[DAGNode].
Scaffolding Validation:

Reference: sprint_2_technical_scaffolding.md (Section 1).
Success State: Running the game prints a text log proving a Dwarven faction was founded on Floor 1, conquered by Goblins in Epoch 40, and the Goblins are currently Active.

Step 2: Procedural Floor Generation & The Spatial Anchors

The Objective: Turn the abstract Active DAG nodes into a physical 3D grid layout that the ECS can populate.
Required Implementation:

Implement the WorldGenerator that maps physical coordinates to Chunk_IDs.

Gestalt Check: When generating a faction's territory, designate a specific Anchor_Chunk (e.g., a Plaza or Throne Room) and save its Vector3i to the DAGNode. Do not spawn entities at 0,0,0.

CRITICAL: Fully generate the tile_map and NavMesh for the entire Surface Village synchronously to prevent AI pathfinding crashes during Pre-Warm.

Implement lazy generation (Wave Function Collapse / Cellular Automata) strictly for Dungeon floors when their state shifts to SIMULATED or ACTIVE.
Success State: The Village exists in memory instantly, while Dungeon Floor 1 only calculates its rigid dwarven ruins when the player takes the elevator down.

Step 3: The DAG-to-ECS Translator (Fleshing the World)

The Objective: Convert abstract historical nodes into living ECS data entities.
Required Implementation:

Build the DAGInstantiator system.

When a chunk containing a Faction Node is initialized, read the DAG Node's population and generate Tier 2 ECS Entities at the Anchor_Chunk.

Cohesion Check: Instantiate wealth strictly using the quantity parameter in PhysicalPropertyComponent to prevent entity bloat.
Success State: The 45 abstract Goblins from the DAG history become 45 actual ECS entities ready for the Simulation Tick.

Step 4: The LoD Boundary System & The Two-Way Sync

The Objective: Implement the memory-saving core. Entities must safely freeze their physics when the player walks away, without creating exploits.
Required Implementation:

Build the LoDSystem in the ECS. Track Entity 0's current chunk and its Active set (3x3 same-floor neighborhood + up/down landing chunks per ADR-3) as Active.

Cohesion Check (The Arrow Fix): Projectiles with a [Kinetic_Ephemeral] tag CANNOT be downgraded to Simulated. If they hit a boundary, instantly run a math-based raycast against abstract chunk data and despawn them. Do not freeze them in mid-air.

Cohesion Check (The Wealth Exploit Fix): When materializing wealth from an abstract ledger to Active, you MUST subtract the value from the ledger. When a chunk downgrades to Simulated, the system MUST count physical items in the [Zone_Stockpile], add them back to the abstract ledger, and delete the physical entities.

Implement the Flood Buffer: When a chunk transitions to Active, read its abstract VolumePools (fluids) and spawn a [Flood_Source] to prevent Cellular Automata CPU spikes.
Success State: Walking away from a lake prevents water physics from calculating. Walking back and forth across a boundary syncs wealth flawlessly without duplicating a single gold coin.

Step 5: The Macro-Tick & The Ledger Economy

The Objective: Prove that the world continues to function when the player isn't looking, without breaking memory.
Required Implementation:

Hook up the Macro Tick (executing once every 60 real-world seconds).

Implement the GrayBoxSystem.

Cohesion Check: DO NOT spawn physical items in Abstracted chunks. Inject resources directly into the integer ledger of the FactionCoreComponent's abstract stockpile data.
Success State: A goblin faction on Floor 5 steadily increases its MAT_IRON count in its ledger every Macro Tick, without a single physical item entity being created.

Step 6: The Boot Sequence (The Corrected Timeline)

The Objective: Execute the procedural generation and time-skips in the exact correct order to prevent Simulation Paradoxes and Physics Explosions.
Required Implementation:

Build the Bootstrapper with this strict execution order:

History: Execute DAG Generator.

Grid: Execute World Gen (Grid mapping and Spatial Anchors).

Interregnum: (If Player Died): Execute 12-Macro-Tick Meta-Progression time-skip (Requires Grid).

Pre-Warm: Execute 100-Sim-Tick Pre-Warm. CRITICAL: Items crafted during this phase must skip gravity calculations and strictly snap to [Display_Table] coordinates to prevent Day 0 collision explosions.

Spawn: Spawn Entity 0 with [Guest_Status] and a starting inventory based on Village Wealth.
Success State: When the player gains camera control, NPCs are already working, physical [Cooked_Meal] entities are neatly stacked on tables (not exploding outward), and the time-skip properly aged the world.
