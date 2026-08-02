Game Vision: The Living Delve

Core Concept: A dungeon crawler where the dungeon is a living, breathing ecosystem and historical artifact. Floors are not just levels; they are distinct subterranean biomes, ruined cities, and sealed kingdoms. The player delves to interact with, exploit, and survive an emergent world.

1. World & History Generation (The "Pre-Game")

Before the player takes their first step, the world must exist. We will use a Directed Acyclic Graph (DAG) to generate and store history.

The World Gen Tick: By default we simulate 50 epochs (about 500 years; tunable per seed) of history in abstract chunks. Nodes represent entities (Kingdoms, Dungeon Floors, Notable Leaders, Artifacts).

Events as Edges: Events (Wars, Collapses, Artifact Forging, Migrations) connect these nodes.

The Result: When the player enters "Floor 4", the game queries the DAG. It knows Floor 4 was a Dwarven Foundry, conquered by a Goblin Warlord 200 years ago, which then collapsed due to a fungal infection. The engine uses this data to procedurally generate the physical layout: ruined anvils, fungal biomes, and scattered, rusted goblin armor.

2. Simulation Architecture (The Godot Approach)

Godot's standard Node/Scene tree is excellent for rendering and player logic, but it will choke if you try to use it to simulate 10,000 independent entities.

Decoupled ECS (Entity Component System): We will run the simulation in a pure data ECS (like GECS or a custom Godot-Rust module). The "Rat" doesn't have a 3D model or sprite until the player is on the same floor. In the ECS, the Rat is just a data row: [EntityID: 402, Type: Rat, Floor: 3, Hunger: 80].

The Simulation Tick: Separate the game frame rate from the simulation tick. The game runs at 60 FPS, but the world simulates at 2 Ticks Per Second.

Level of Detail (LoD) Simulation:

Active Chunk Neighborhood (Player Present): High-res simulation in the ADR-3 Active set
(3x3 same-floor chunks plus up/down landing chunks). Physics, pathfinding, animation, and
immediate combat run here.

Nearby Simulated Chunks/Routes: Medium-res. Movement is calculated node-to-node on the
AbstractGraph. Factions gather resources and fight abstract skirmishes.

Distant Floors/Factions: Low-res. Entire populations are treated as integer ledgers/counters.
"Goblin population grew by 5%."

3. The Dungeon Ecology

Creatures in the world are divided into tiers to save computation and define mechanics.

Tier 1: Swarms & Vermin (The Rats): Handled via abstract population pools. They don't have individual names or lineages. A floor has a "Rat Population" integer. As long as there is trash/food on the floor, the integer grows. When the player enters, the game spawns actual rat mobs based on that integer. If you kill them, the integer drops.

Tier 2: Citizens & Workers (The Goblins/Dwarves): Standard Utility AI. They have basic needs (Sleep, Eat, Work). They mine artifacts and forge weapons, putting them into faction stockpiles. If they die, they are dead, and the faction must reproduce or recruit to replace them.

Tier 3: Leaders & Unique Entities: This is where the LLM lives.

4. LLM Agent Integration (The "Reasoner/Planner" Architecture)

To make NPCs feel alive without breaking the bank or creating massive latency, we separate Decision Making from Execution.

The Reasoner (LLM): Runs asynchronously. Every in-game day (or when a major event occurs), the game packages the current state of a faction into a prompt.

Prompt Context: "You are Ug, Goblin King of Floor 3. Your population is 45. You are low on food. The player just killed your chief miner. You have a rivalry with the Fungal Spore-Lord on Floor 4."

LLM Output (Structured JSON): The LLM decides on a high-level goal and an emotional state. { "Goal": "RAID_FLOOR_4_FOR_FOOD", "Emotion": "VENGEFUL", "Target": "FUNGAL_LORD" }

The Planner (Engine AI): Godot takes this JSON and feeds it to the ECS JobTemplate planner.
The engine translates "RAID_FLOOR_4" into actual pathfinding, assigning squads, and moving
units. A more expensive search planner may replace the template planner later behind the same
interface, but it is not the current implementation target.

The Magic: The player intercepts a goblin raiding party on the stairs. They aren't there because of a random spawn trigger; they are there because Ug the LLM-Agent got mad and thirsty.

5. The Economy (Village and Depths)

Because items are physically simulated, the economy is real.

The village blacksmith doesn't have infinite gold. If you buy his sword, he uses that gold to buy bread from the baker.

If you wipe out the spiders on Floor 1, silk production drops. The village tailor runs out of silk, and the price of bandages skyrockets.

Dungeon factions compete for resources. A neutral faction of Deep Gnomes might be mining the same Mythril vein you want. You can trade with them, ally with them against the Goblins, or slaughter them for the ore.

6. The Open System (External Actors & Gray Boxes)

To keep the world plausible and prevent the economic/ecological simulations from spiraling into catastrophic failure (a common issue in perfectly closed loops), the game relies on abstracted "Outside Worlds" acting as sources and sinks.

The Surface Empire (Village Influx): The village is connected to a larger, unsimulated kingdom. Seasonal merchant caravans, wandering adventurers, and royal tax collectors arrive periodically. If you buy all the town's iron, a caravan will eventually replenish it. If a dragon wipes out half the village, gray-boxed immigrants will eventually arrive to repopulate, driven by broader "pull" mechanics.

The Deep Roads (Dungeon Influx): The dungeon isn't a sealed jar. Factions have connections to the deeper Under-realm. A goblin tribe doesn't just rely on biological reproduction; they can receive reinforcements via unexplored tunnels from a "Greater Horde." Neutral deep-merchants might traverse the lower floors, trading exotic goods to dungeon denizens.

The Vacuum Effect: These external gray boxes act as balancing levers. If the player completely eradicates a faction on Floor 3, nature abhors a vacuum. The empty, resource-rich floor will eventually attract a new faction from the Deep Roads to migrate in, ensuring the dungeon remains dynamic and ever-changing even in the late game.
