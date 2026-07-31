Meta-Progression & Death Loop Architecture

Target Audience: Lead Coding Agent / Systems Architect
Context: This document defines the game's state management regarding player death. We explicitly reject save-scumming and temporal rollbacks. The world is persistent. Player death is simply an event that triggers a temporal fast-forward, ensuring the player's actions (and failures) leave a permanent scar on the simulation.

AUTHORITATIVE NOTE (ADR-1 / ADR-6): "Persistent world" means state is SERIALIZED, not
re-simulated — the world is NOT deterministically reproducible (LLM inputs alone make it
non-reproducible). Continuity across a suspend/resume and across the Interregnum comes from
the versioned save payload (see ecs_architecture spec Section 8). "Seed continuity" means the
generation seed is stored so UNVISITED floors regenerate identically; VISITED/mutated state
(e.g., a mined-out wall) is saved explicitly, not recomputed. Note the game supports BOTH
full mid-run "Save & Quit" AND between-run persistence (runs may be very long — ADR-6);
"reject save-scumming" refers to the death loop, not to suspend/resume of an in-progress run.

1. Core Philosophy: Diegetic Permadeath

When Entity 0 (The Player) reaches 0 Health, the game does not end, and it does not reload a previous save.

The player's PlayerInputComponent is detached.

Death creates a separate Corpse/remains entity at the player's final tile. The old Entity 0
handle is then atomically destroyed/retired, its generation is bumped, and index 0 is reserved
for the next adventurer. Its InventoryComponent spills into a localized [Loot_Pile] entity or
corpse/container manifest before the old handle is invalidated.

The game enters the Interregnum State.

2. The Interregnum State (The 1-Year Time Skip)

To signify the arrival of a new adventurer on the annual cadence, the engine must simulate the passage of one year.

The Coarse Interregnum Burst: The ECS engine suspends the Micro and Simulation ticks, and
rapidly executes 12 monthly coarse interregnum passes. These are not ordinary hourly Macro
Ticks; they operate on ledgers, abstract populations, DAG edges, and manifests.

World Evolution: During this burst:

Ecology: Filth left by the player spawns massive rat populations. Puddles of water evaporate or freeze.

Economy: Leftover dropped items might degrade into Scrap. If the player left a valuable weapon, a Tier 2 NPC with a Scavenge job might pathfind to it and equip it.

Factions: Wars triggered by the previous player resolve. Faction borders shift.

The DAG Logging: The previous player's death is recorded as an Event Edge in the DAG history (e.g., [Adventurer 04] --(Killed By)--> [Cave Spider Swarm] --(Location)--> [Floor 2]).

3. The Adventurer's Residence (Anchored Persistence)

To provide a sense of progression and soften the blow of permadeath, the player has access to a persistent anchor in the Surface Village.

The Estate Entity: A specific ZoneID in the village designated as the Adventurer's Residence.

Physical Stash: Contains a Container entity with massive volume_cm3 capacity. Any items, base materials, or translated spell runes placed in this chest survive the 1-year time skip untouched (unless a DAG event triggers a massive village raid, which adds risk to hoarding).

4. The Lineage Journal (The Persistent Codex)

The true meta-progression lies in a permanent, indestructible UI/Item located on a desk in the Residence: The Lineage Journal. This object bridges the gap between adventurers, saving the player from the tedium of re-discovering the seed's unique rules.

The Journal is a localized JSON save-state that auto-populates the new player's UI with the previous players' discoveries.

A. Auto-Recorded Mechanics (The World Codex)

Because material properties and rune syntax may be randomized per world seed, the Journal automatically records physical discoveries. When read by a new adventurer, it unlocks these in their UI:

Chemistry & Crafting: If a previous adventurer successfully combined Fungal_Wood and Venom_Gland, the resulting recipe and chemical reaction are permanently unlocked in the CraftingUI for all future characters.

Spell Schematics: Successfully compiled and cast spell graphs (e.g., standardizing a "Fireball" layout in the GrimoireUI) are saved as templates.

Biological Insight: The highest MindComponent.insight data achieved for monster weaknesses
and species tags is carried over.

B. Auto-Recorded History (The DAG Chronicle)

The Journal acts as a localized DAG viewer. It automatically generates prose entries based on major DAG events the player participated in.

Example: "In the Winter of Epoch 42, Adventurer #3 assassinated the Goblin King Ug on Floor 2, fracturing the horde."

C. Manual Player Annotations (The Warning System)

Players can manually write entries to warn their future selves.

Free-form Text: The player can type a physical note before leaving the village (or via a portable "Field Notes" item that uploads to the main journal if they die). Example: "Do not trust the Deep Gnomes on Floor 4, they overcharge for sulfur."

Suggested / Pinned Notes: By shift-clicking an entity or zone in the Tactical Lens, the UI prompts an auto-formatted note: "Pin: High concentration of [Acid] in Sector 4-B."

5. Re-Entry (The Next Generation)

After the Interregnum State completes, the engine finalizes the spawn process for the new
Entity 0 by reusing index 0 with generation + 1. Stale references to the previous adventurer
must fail handle validation; the corpse/remains entity has its own non-player handle.

Character Generation: The new Entity 0 spawns in the Residence with baseline BodyComponent and MindComponent stats. Muscle memory (e.g., Blade_Familiarity) is reset to zero. They are physically a novice.

Inheritance: They physically pick up whatever the previous player left in the stash and read the Lineage Journal to synchronize their MindComponent with the saved UI knowledge.

World Impact: They walk out into a village that has organically reacted to the past year. If the previous player spent massive amounts of gold at the blacksmith, the blacksmith's shop might have organically upgraded to a higher tier during the time skip due to the ECS EconomySystem.

6. Technical Implementation constraints

Garbage Collection During Time Skip: The coder must ensure the coarse interregnum pass
aggressively deletes insignificant entities (like singular dropped arrows or minor blood
splatters) to prevent the ECS memory footprint from bloating infinitely over multiple deaths.
Identity-bearing items follow MaterializationComponent policy and persistence manifests.

Seed Continuity: The procedural noise seeds for the dungeon floors must not change. Floor 3 is still Floor 3. If a wall was mined out by the previous player, that wall remains missing (or is perhaps shored up with wooden scaffolding by a newly moved-in Goblin faction).
