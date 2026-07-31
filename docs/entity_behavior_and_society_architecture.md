Entity Behavior & Society Architecture

Target Audience: Lead Coding Agent / AI Systems Architect
Context: This document defines the behavioral simulation for Tier 2 entities (Citizens/NPCs). It bridges the gap between the macro-faction goals (set by the LLM) and the micro-physics engine. It outlines how entities manage their daily lives, take on professions, run economies at the street level, and maintain societal morale.

1. Core Philosophy: The Routine is King

Entities do not work 24/7. They are biological and psychological agents. Their behavior is governed by a Daily Routine. The ECS Simulation Tick constantly evaluates an entity's current schedule block to determine which branch of their Utility AI to execute.

No "Spawn-and-Stand" NPCs: A shopkeeper does not stand behind a counter 24 hours a day waiting for the player. They sleep, they eat at the tavern, and they go to the stockpile to restock their shelves.

Need-Driven Interrupts: If hunger reaches a critical threshold, it creates a high-priority ActionIntent that interrupts the current Routine block.

2. The Routine Component

Every Tier 2 entity possesses a ScheduleComponent. This maps the 24-hour Macro-Tick cycle to behavioral states.

Sleep (e.g., 22:00 - 06:00): Seeks a designated [Bed] or [Safe_Zone]. Pauses most sensory processing. Replenishes energy.

Work (e.g., 06:00 - 18:00): Executes jobs derived from their ProfessionComponent and the faction's global JobQueue.

Leisure (e.g., 18:00 - 22:00): Seeks [Social_Zone] (Taverns, Plazas, Shrines). Replenishes morale.

3. Professions & Roles (The Job Enablers)

An entity's ProfessionComponent acts as a filter for the faction's JobQueue. Legacy prose like
`[Prof_Hauler]` is shorthand for `ProfessionComponent.profession = &"Prof_Hauler"`. The
Faction Planner generates hundreds of jobs; the Profession determines who claims what.

A. The Civilian Economy (Sustainment)

The Hauler ([Prof_Hauler]): The backbone. Low prestige. Claims jobs to move loose items from [Mining_Zones] or [Farms] to [Stockpiles].

The Crafter ([Prof_Smith], [Prof_Cook]): Anchored to specific [CraftingStations].

Cooks: Pull MAT_BIOMASS and MAT_WATER, output [Cooked_Meal] (grants a temporary buff to maximum morale and stamina).

The Merchant / Shopkeeper ([Prof_Merchant]):

Behavior: Claims ownership of a [Shop_Zone].

Loop: During Work hours, they generate Job_Restock, pulling items from the faction stockpile based on what is selling. When the player (or an NPC from an allied faction) enters the zone, they enter a Trade_State, overriding standard AI to offer goods based on the EconomySystem's local scarcity index.

B. Leisure & Culture (Morale Management)

If a faction's average morale drops, efficiency plummets, and Schisms (mutinies) occur. Leisure professions prevent this.

The Entertainer ([Prof_Bard], [Prof_Priest]):

Behavior: Operates in a [Social_Zone] during the Leisure block.

Mechanic: Executes a looping Job_Perform. This emits an invisible, expanding ECS Aura (using the same mechanics as magic). Any allied entity inside the aura slowly regenerates morale and temporarily suppresses grievance modifiers.

C. The Military (Defense & Expansion)

Military roles do not participate in the standard economy. They are a pure resource drain (consuming food/weapons) necessary for survival.

The Guard ([Prof_Guard]):

Behavior: Claims Job_Patrol (walking a spline between faction borders) or Job_Stand_Watch (anchored to a chokepoint).

Engagement Rules: Automatically shifts to Combat_State if an entity with Relationship: War enters their vision cone.

The Soldier / Raider ([Prof_Soldier]):

Behavior: Kept in reserve (training in barracks) until the Tier 3 LLM Leader issues a
RAID_FACTION objective (registry §3 `Objective`).

Mechanic: They form a Squad (a temporary sub-faction entity) that moves as a cohesive unit, following a Squad Leader to the target zone.

4. Day-to-Day Life Mechanics

How the ECS actually handles the simulation of life.

Taverns & Consumption: A Tavern is just a [Social_Zone] combined with a [Food_Stockpile]. During the Leisure block, entities pathfind here. They physically remove a [Cooked_Meal] or [Ale] entity from the stockpile, play a consumption animation, and their NeedsComponent updates. If the stockpile is empty, they suffer a massive morale penalty.

Conversation (The Rumor Mill): When two allied entities idle near each other during Leisure, they sync their MemoryComponents.

Emergence: If Entity A saw the player murder a guard, Entity A has that memory. During Leisure, Entity A passes it to Entity B. This is how the player's reputation organically updates across a faction, rather than updating instantaneously via a global hivemind.

5. Interaction with the LLM (The Supervisor)

The Tier 3 Leader (LLM) does not assign these professions manually.

The Workforce Ratio: The LLM manages ratios, not individuals.

Example: If the LLM reasons, "We are under attack, we need more defense," it outputs the
FORTIFY objective (registry §3 `Objective`), whose JobTemplate includes ReassignToGuard(ratio).

The Engine Planner receives this, and forcibly reassigns 20% of [Prof_Hauler] entities to [Prof_Guard], directing them to the armory to equip weapons. The sudden lack of Haulers means crops might rot in the fields, leading to starvation a week later—a systemic consequence of the LLM's decision.

6. Integrated Corrections (ADR / Adversarial Review)

Authoritative note: governed by docs/architecture_decisions.md and
docs/component_and_field_registry.md.

Aura / Ephemeral primitive is a Sprint 1 deliverable (review G3). Bard morale auras,
[Alert] auras, and the Sprint 1 [Ephemeral_Noise_Entity] all use ONE shared primitive: an
EphemeralComponent entity with a TTL and an expanding radius that applies tags to entities it
overlaps (queried via the ECS SpatialHash). Sprint 4 magic builds ON this primitive rather
than introducing it, so social/alert features do not depend on the Sprint 4 magic system.

Job-claim lifecycle (see factions doc §6): the faction JobQueue holds JobComponents with
status:JobStatus and claimed_by:EntityHandle. ProfessionComponent filters which jobs an entity
may claim; claiming sets status=CLAIMED. If the claimant dies/aborts, the job returns to OPEN.
This prevents orphaned jobs and double-claims within the single-threaded tick.

Perception/witness primitive: social alerting uses PerceptionSystem, not omniscience.
Witnessed crimes create WitnessEvents and MemoryEvents; unwitnessed crimes do not update
faction reputation until discovered through normal sensory/evidence paths.

Time source (ADR-9): schedule blocks read the GameClock (introduced in Sprint 1). Sleep
22:00-06:00, Work 06:00-18:00, Leisure 18:00-22:00 are hour ranges evaluated on the Sim tick.

Conversation/rumor sync writes MemoryEvents (registry §4); significant Tier-2 memories are
periodically summarized up into FactionCoreComponent.faction_memory for the LLM (review B6).
