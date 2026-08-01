Implementation Roadmap: Sprint 3 (The Brains & The Bloodline)

Target Audience: Lead Coding Agent
Objective: Implement the asynchronous LLM Reasoner for Tier 3 entities and the Meta-Progression "Death Loop" (Interregnum) that persists world state and player knowledge across runs.

Step 1: The LLM API Bridge & Staggered Queue

The Objective: Safely connect the engine to an external LLM API without freezing the main thread, hitting rate limits, or suffering from "Stale Context."
Required Implementation:

Build the LLMBridge (Godot HTTPRequest node wrapper).

Implement the ReasoningQueue. Tier 3 entities must register their EntityHandle here. The queue dispatches a maximum of 1 request at a time.

CRITICAL - Lazy Prompt Generation: The queue MUST NOT store the prompt string. It only stores the ID. The prompt is built at the exact millisecond the request is fired to ensure the LLM receives real-time reality.
Scaffolding Validation: Reference sprint_3_technical_scaffolding.md (Section 1).
Success State: 5 faction leaders request a thought. They enter the queue. The engine fires them one by one. The game continues running at 60fps.

Step 2: Prompt Construction (The State Injector & Salience Filter)

The Objective: Give the LLM accurate, token-efficient context without bankrupting the API budget.
Required Implementation:

Build PromptBuilderSystem.

When a request is pulled from the queue, query FactionCoreComponent.diplomacy,
FactionCoreComponent.faction_memory, and any relevant active MemoryComponents.

CRITICAL - The Salience Filter: send only the top 3 memories by decayed weight plus the 3
most recent events. Do not send the entire history.

CLARIFIED 2026-08-01: the two sets overlap often, because a heavy memory is usually also a
recent one. Deduplicate the combined list by event_id. The filter therefore sends BETWEEN 3
AND 6 memories, not exactly 6. Sending a memory twice tells the reasoner it happened twice.

CRITICAL - Valid Target Enumeration: The context string MUST explicitly list integer IDs of known neighboring factions.
Success State: Dynamic output: "You are Ug. Pop: 45. Memory: [Player killed 2 guards]. Valid Targets: [12: Gnomes, Faction-0: Player]." (Player is Faction 0 per ADR-14.)

Step 3: Engine Translation & The Validation Gate

The Objective: Convert the LLM's JSON output back into physical ECS behaviors, safely ignoring invalid or hallucinated commands.
Required Implementation:

Build the LLMResolutionSystem.

CRITICAL - The Hallucination/Race Condition Fix: Implement the Validation Gate.

Check ECSManager.is_alive(LLM_Entity_ID).

If the LLM returned a target_faction_id, verify it exists in the active DAG list. If it hallucinates an invalid ID, override the objective to FORTIFY.

Map valid JSON Objective (e.g., RAID) through the JobTemplate planner to Job_Queue insertions for the faction's Tier 2 entities.
Success State: The LLM decides to attack the Spiders (Target 15). 10 seconds later, 5 Tier 2 Goblins equip swords and pathfind toward the spider cavern.

CORRECTED 2026-08-01: as written this is not testable within Sprint 3, because it depends on
equippable swords and a goblin faction that no Step in this sprint builds. The testable form,
and the one the acceptance tests use: the reasoner sets current_objective to RAID_FACTION with
a valid target_faction_id, the planner expands that objective into JobTemplate entries for the
faction's Tier 2 members, and those members path toward the target's anchor chunk. Equipment is
Sprint 4's.

Step 4: The Death Event & Corpse Generation

The Objective: Handle Player 0's HP hitting 0 without showing a "Game Over" screen or reloading a save.
Required Implementation:

When Entity 0 Health <= 0, instantly detach the PlayerInputComponent.

Create a separate [Corpse] / remains entity at Entity 0's final tile. Do not keep the corpse
on player index 0.

Spill InventoryComponent contents into a localized [Loot_Pile] or corpse/container manifest,
then atomically destroy/retire the old player handle and bump Entity 0's generation so stale
references fail.
Success State: The player dies, the camera detaches, and they watch their killer physically pick up their dropped Iron Sword.

Step 5: The Interregnum (1-Year Macro-Skip) & The Dual Taxes

The Objective: Fast-forward the world to prepare for the next adventurer, while preventing memory bloat from infinite items and biological swarms.
Required Implementation:

Suspend the Micro Tick and Simulation Tick.

Fire the dedicated Bootstrapper.execute_interregnum() loop (12 coarse monthly passes). Do not
run 12 ordinary hourly Macro ticks.

CRITICAL - The Entropy Tax: operate on ledgers and abstract populations during the
Interregnum (ADR-11). Apply the 40% wealth entropy tax to FactionCore ledgers, clear
insignificant residual physical entities such as [Filth] and expired [Ephemeral_Noise], and
use RNGService streams for any random deletion.

CRITICAL - The Swarm Tax (Carrying Capacity): Forcefully cap all Tier 1 Swarm populations (Rats, Spiders) to a maximum of 10 per chunk to prevent exponential biological crashes.

Add a Player Death Event Edge to the DAG History.
Success State: The screen fades to black. Text reads "One Year Passes." The console shows thousands of orphaned items and excess rats being deleted.

Step 6: The Lineage Journal & Re-Entry

The Objective: Persist discovered knowledge across runs safely.
Required Implementation:

Build the LineageJournal local JSON save system.

Before the Interregnum starts, serialize the player's MindComponent.insight and known_runes.

After Interregnum, reuse index 0 with generation + 1 for the new adventurer at the
Adventurer's Residence, and populate their MindComponent from the JSON.

ADDED 2026-08-01: Step 6 shipped without a Success State, so it had no acceptance criterion at
all. It is: the player dies with a known rune and non-zero insight, presses R, and the new
adventurer's MindComponent holds that same insight and rune while carrying none of the previous
body's possessions. A corrupt journal starts a fresh one instead of refusing to boot; a journal
written by a newer schema is refused instead of being misread.

Step 7: Rewrite RUNNING.md (required by scope_and_milestones.md R6)

The Objective: Someone who did not build this sprint can play it and know what they are
looking at.
Required Implementation:

Rewrite - never append to - the "What to test right now" and "deliberately NOT built yet"
sections of RUNNING.md, in the same commit as the code and before the PR opens. Every claim in
it must be something the player has an interface to check.
Success State: A reader who has not seen this roadmap can, from RUNNING.md alone, reach the
stairwell, descend a floor, kill a villager in front of a witness, die, and restart - and can
say what each of those proved.
