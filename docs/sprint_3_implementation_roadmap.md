Implementation Roadmap: Sprint 3 (The Brains & The Bloodline)

Target Audience: Lead Coding Agent
Objective: Implement the asynchronous LLM Reasoner for Tier 3 entities and the Meta-Progression "Death Loop" (Interregnum) that persists world state and player knowledge across runs.

Step 1: The LLM API Bridge & Staggered Queue

The Objective: Safely connect the engine to an external LLM API without freezing the main thread, hitting rate limits, or suffering from "Stale Context."
Required Implementation:

Build the LLMBridge (Godot HTTPRequest node wrapper).

Implement the ReasoningQueue. Tier 3 entities must register their entity_id here. The queue dispatches a maximum of 1 request at a time.

CRITICAL - Lazy Prompt Generation: The queue MUST NOT store the prompt string. It only stores the ID. The prompt is built at the exact millisecond the request is fired to ensure the LLM receives real-time reality.
Scaffolding Validation: Reference sprint_3_technical_scaffolding.md (Section 1).
Success State: 5 faction leaders request a thought. They enter the queue. The engine fires them one by one. The game continues running at 60fps.

Step 2: Prompt Construction (The State Injector & Salience Filter)

The Objective: Give the LLM accurate, token-efficient context without bankrupting the API budget.
Required Implementation:

Build PromptBuilderSystem.

When a request is pulled from the queue, query FactionCoreComponent, DiplomacyComponent, and MemoryComponent.

CRITICAL - The Salience Filter: Truncate the MemoryComponent to the 5 most recent events and 3 highest-weight "Core Memories". Do not send the entire history.

CRITICAL - Valid Target Enumeration: The context string MUST explicitly list integer IDs of known neighboring factions.
Success State: Dynamic output: "You are Ug. Pop: 45. Memory: [Player killed 2 guards]. Valid Targets: [12: Gnomes, Faction-0: Player]." (Player is Faction 0 per ADR-14.)

Step 3: Engine Translation & The Validation Gate

The Objective: Convert the LLM's JSON output back into physical ECS behaviors, safely ignoring invalid or hallucinated commands.
Required Implementation:

Build the LLMResolutionSystem.

CRITICAL - The Hallucination/Race Condition Fix: Implement the Validation Gate.

Check ECSManager.is_alive(LLM_Entity_ID).

If the LLM returned a target_faction_id, verify it exists in the active DAG list. If it hallucinates an invalid ID, override the objective to FORTIFY.

Map valid JSON Objective (e.g., RAID) to GOAP Job_Queue insertions for the faction's Tier 2 entities.
Success State: The LLM decides to attack the Spiders (Target 15). 10 seconds later, 5 Tier 2 Goblins equip swords and pathfind toward the spider cavern.

Step 4: The Death Event & Corpse Generation

The Objective: Handle Player 0's HP hitting 0 without showing a "Game Over" screen or reloading a save.
Required Implementation:

When Entity 0 Health <= 0, instantly detach the PlayerInputComponent.

Convert Entity 0 to a [Corpse] item.

Spill InventoryComponent contents into a localized [Loot_Pile].
Success State: The player dies, the camera detaches, and they watch their killer physically pick up their dropped Iron Sword.

Step 5: The Interregnum (1-Year Macro-Skip) & The Dual Taxes

The Objective: Fast-forward the world to prepare for the next adventurer, while preventing memory bloat from infinite items and biological swarms.
Required Implementation:

Suspend the Micro Tick and Simulation Tick.

Fire the Bootstrapper.execute_interregnum() loop (12 Macro-Ticks).

CRITICAL - The Entropy Tax: Run garbage collection. Destroy 100% of [Filth], 100% of [Ephemeral_Noise], and randomly delete 40% of standard faction wealth.

CRITICAL - The Swarm Tax (Carrying Capacity): Forcefully cap all Tier 1 Swarm populations (Rats, Spiders) to a maximum of 10 per chunk to prevent exponential biological crashes.

Add a Player Death Event Edge to the DAG History.
Success State: The screen fades to black. Text reads "One Year Passes." The console shows thousands of orphaned items and excess rats being deleted.

Step 6: The Lineage Journal & Re-Entry

The Objective: Persist discovered knowledge across runs safely.
Required Implementation:

Build the LineageJournal local JSON save system.

Before the Interregnum starts, serialize the player's MindComponent.insight and known_runes.

After Interregnum, spawn a new Entity 0 at the Adventurer's Residence, and populate their MindComponent from the JSON.
