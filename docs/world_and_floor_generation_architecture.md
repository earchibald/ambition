World & Floor Generation Architecture

Target Audience: Lead Coding Agent / AI Systems Architect
Context: This document outlines the procedural generation pipeline for creating massive, heterogeneous dungeon floors. Floors are not standard BSP (rooms-and-corridors); they are composite landscapes shaped by geology, historical colonization (driven by the DAG), resource extraction, and eventual ruin. Crucially, this document provides the concrete data seeds, tables, and archetypes the coder must implement to populate the generation algorithms.

1. Core Philosophy: Composite Generation

A single floor is too large and complex for one algorithm. The generator uses a Composite Multi-Pass Pipeline:

Macro-Zoning: Voronoi mapping for geology.

DAG Overlay: Assigning historical cultures to zones.

Micro-Generation: Applying specific algorithms (WFC, Cellular Automata) based on the zone tag.

Erosion & Integration: Aging the map and connecting zones via A* pathing.

ECS Instantiation: Converting the visual grid to pure data.

2. Phase 1: The Canvas (Geology & Biome Seeds)

Before history occurs, the terrain exists. The Voronoi diagram assigns each region one of these base geological seeds. The coder should implement these as data dictionaries.

Biome ID

Tags

Visual/Tile Base

Common Resources (70%)

Rare Resources (10%)

Generation Algorithm

GEO_BASALT

[Hot, Volatile, Dense]

Dark Grey Stone, Magma pools

Basalt, Sulfur, Iron

Obsidian, Fire-Gems

Cellular Automata (chunky, wide open caverns)

GEO_AQUIFER

[Wet, Porous, Cold]

Smooth Limestone, Water

Limestone, Clay, Algae

Subterranean Pearls

Drunkard's Walk (winding, river-like tubes)

GEO_GRANITE

[Solid, Stable, Dry]

Light Grey Stone, Dirt

Granite, Coal, Copper

Gold, Mythril

Voronoi Sub-fractal (dense rock with small pockets)

GEO_FUNGAL

[Organic, Humid, Toxic]

Mycelium-coated dirt

Biomass, Basic Spores

Hallucinogens, Acid

Game of Life (spreading, creeping borders)

Balancing Rule: A floor generation script must enforce ratios. E.g., Max 20% GEO_BASALT per floor to prevent the map from becoming an unplayable lava lake, unless overridden by a specific DAG event.

3. Phase 2 & 3: Cultural Overlays & Micro-Generation (The DAG Impact)

When the DAG places a Faction on a Biome, it uses specific Generation Algorithms and applies Cultural Archetypes.

Archetype A: The Dwarven / Methodical

Trigger: DAG indicates a structured, mining-focused or high-wealth civilization.

Algorithm: Wave Function Collapse (WFC). Strictly grid-based. Plazas, 3x3 hallways, right angles.

Tags Applied: [Stonework, Trapped, Structural_Support].

Naming Convention (JSON Rule): Prefix + Suffix.

Prefixes: Iron, Deep, Stone, Bronze, Hammer.

Suffixes: Forge, Hall, Guard, Beard, Anvil. (e.g., "Ironforge", "Deephall").

Social Hierarchy (Tier 2/3):

Leader (LLM): The Thane. High priority on [Hoard_Wealth] and [Defend_Territory].

Classes: Miners (seek ore), Smiths (refine), Guards (patrol borders).

Erosion Logic: When aging, WFC tiles do not bend. They break. 30% of walls become [Rubble] (difficult terrain, provides cover).

Archetype B: The Goblinoid / Exploitative

Trigger: DAG indicates a chaotic, scavenging, or rapidly expanding horde.

Algorithm: Agent-based tunneling. Spawn "miner agents" that randomly walk toward the nearest resource veins, destroying tiles and leaving chaotic 1x1 or 2x2 winding paths.

Tags Applied: [Filth_Heavy, Scavenged, Unstable_Ceiling].

Naming Convention (JSON Rule): Guttural Syllable + Descriptive Noun.

Syllables: Ug, Snar, Kruk, Vrag.

Nouns: Biter, Gouge, Shank, Rot. (e.g., "Ug-Biter", "Kruk-Rot").

Social Hierarchy:

Leader (LLM): The Boss. High priority on [Raid], [Consume], and internal [Suppress_Mutiny].

Classes: Scrappers (scavenge loose items), Brutes (combat), Breeders (passive in camp).

Erosion Logic: Wooden supports rot (turning into Filth). Unstable ceilings collapse, creating natural hazards that can crush entities during gameplay.

Archetype C: The Hive / Infested

Trigger: DAG indicates an outbreak, magical corruption, or insectoid/fungal colony.

Algorithm: Cellular Automata (Growth). It finds an existing structure (Dwarven or Goblin) and overwrites the tiles radially outward, ignoring walls.

Tags Applied: [Hivemind, Corrosive, Biomass].

Naming Convention: Non-verbal. The UI displays them as generic identifiers (e.g., "Spore-Drone 104") or chemical pheromone IDs until the player studies them.

Social Hierarchy:

Leader (LLM): The Queen / Spore-Lord. Priority on [Expand_Territory] and [Assimilate_Biomass]. Shares vision with all Tier 2 units.

Classes: Drones (gather corpses/biomass), Warriors (defend drones).

4. Creature Archetypes & Ecology Data (Tier 1 Swarms)

To populate the ecosystem, the coder must implement these baseline Tier 1 entities. They operate purely on ECS tags and do not have AI, only biological imperatives.

Species Base

Spawns In

Consumes (Needs)

Produces (Waste)

Overpopulation Buffer

Combat Tag

Corpse-Rats

[Filth_Heavy]

[Meat, Biomass]

[Filth_Minor]

Starves rapidly if Biomass = 0. Eaten by Spiders.

[Swarm, Flee_Light]

Cave-Spiders

[Dark, Solid]

[Swarms]

[Webbing_Resource]

Territorial: Spiders will kill each other if density > 5 per room.

[Venom, Ambush]

Rust-Mites

[Stonework]

[Metals, Weapons]

[Scrap_Dust]

Go dormant (turn into harmless rocks) if no metal is present.

[Corrode_Armor]

Slimes

[Wet, Porous]

[Filth_Minor]

[Acid_Pools]

Evaporates in [Hot] environments.

[Divide_On_Hit]

5. Implementation Rules: Connecting the World

A floor is useless if the player cannot navigate it. The coder must enforce the following integration rules during Phase 4 (Erosion & Integration):

The Spine Pathing: The generator must run an A* pathfinding algorithm from the Entry_Stairs to the Exit_Stairs before finalizing the map. If the path is blocked by solid rock, the algorithm must carve a "Natural Faultline" or "Ancient Highway" (a 3-tile wide path) connecting the disparate biomes.

Biome Bleed: Biomes do not have hard square edges. Apply a Gaussian blur/dithering algorithm at the borders. A Dwarven Forge bordering a Fungal Cavern should have 10-20 tiles of [Rubble] mixed with [Spores] before fully transitioning.

The Chunking Grid: The map must be divided into chunks (e.g., 64x64 tiles). The ECS LoDSystem evaluates proximity chunk-by-chunk. Only the chunk the player is in, and its 8 immediate neighbors, are set to Active (rendering graphics and real-time physics).
