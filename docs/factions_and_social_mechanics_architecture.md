Factions & Social Mechanics Architecture

Target Audience: Lead Coding Agent / AI Systems Architect
Context: This document outlines the social simulation layer for "The Living Delve." It defines how Tier 2 (Citizens) and Tier 3 (Leaders) entities interact internally (loyalty, mutiny) and externally (war, trade, diplomacy). We reject static "good/evil" alignments in favor of dynamic, emergent relationships driven by resources, history, and LLM reasoning.

1. Core Philosophy: Dynamic Alignment & Emergent Conflict

Factions do not exist in a vacuum, and they are not statically hostile to the player or each other simply because of their species.

Resource-Driven Conflict: Wars are fought over scarce resources (e.g., an iron vein, a chokepoint on a floor) or historical grievances (imported from the DAG).

Granular Relationships: The player is treated by the ECS as a single-entity faction (Faction ID: 0). NPC factions track their relationship with the player exactly as they track relationships with other NPC factions.

Bottom-Up and Top-Down Sociality: Leaders (Tier 3) set the grand diplomatic stance (Top-Down), but citizens (Tier 2) react to their material conditions, which can force a leader's hand or cause a mutiny (Bottom-Up).

2. ECS Data Structures

The coding agent should implement the following components to track social data.

Macro-Level (Faction Entities)

Factions themselves are abstract Tier 1 entities in the ECS that hold macro-data.

FactionCoreComponent: faction_id, name, culture_tags (e.g., [Militaristic, Subterranean, Clan-Based]).

DiplomacyComponent: A dictionary mapping target faction_id to a RelationshipState.

RelationshipState: score (-100 to 100), status (Enum: War, Neutral, Trade, Allied), grievances (List of recent offenses).

Micro-Level (Tier 2/Tier 3 Entities)

SocialIdentityComponent: faction_id, loyalty (0-100), prestige (0-100, determines hierarchy/promotion).

MemoryComponent: A rolling list of recent significant events (e.g., "Saw brother killed by Faction 0", "Received high-quality food"). Used to calculate temporary morale/loyalty shifts.

3. Intra-Faction Dynamics (Internal Cohesion)

Factions must maintain internal stability, or they will collapse without external interference.

Loyalty Calculation: A Tier 2 entity's loyalty is recalculated during the Simulation Tick based on their NeedsComponent (are they starving?), their MemoryComponent (are they constantly fleeing in terror?), and the overall wealth of the faction.

The Schism Mechanic (Emergent Mutiny):

If a large cluster of Tier 2 entities drops below a Loyalty Threshold (e.g., 20/100), the ECS SocialSystem triggers a schism.

A percentage of these entities are stripped of their current faction_id and assigned a new, splinter faction_id.

They immediately gain a status: War with their former faction and attempt to seize the nearest stockpile.

Succession (The Promotion System):

If a Tier 3 Leader is killed (by the player, a rival faction, or starvation), the faction does not instantly vanish.

The SocialSystem scans all Tier 2 entities in the faction, selects the one with the highest prestige, and promotes them.

They are granted the LLMPromptComponent, and a "Reasoning Tick" is immediately queued to determine the new leader's agenda (which might be "Avenge the previous leader" or "Sue for peace").

4. Inter-Faction Dynamics (Diplomacy & War)

How factions interact with each other in the physical world.

Trade Routes (Peaceful Interaction):

If two factions have status: Trade, the Engine Planner generates Trade Mission jobs.

Tier 2 entities form a caravan, load surplus from their InventoryZone, and pathfind to the allied faction's zone to exchange goods. These caravans exist physically and can be intercepted by the player or hostile factions.

Territorial Control & Skirmishes:

Factions exert influence over zones via ClaimTags.

If two neutral factions attempt to mine the same ResourceSource, their Tier 2 entities will engage in "brawls" (non-lethal or low-lethal combat).

These brawls generate grievances in the DiplomacyComponent.

Total War:

When grievances mount, or if the LLM Reasoner explicitly sets an objective to CONQUER, the diplomatic status shifts to War.

The Engine Planner stops generating civilian jobs (mining, farming) near the border and generates Raid, Patrol, and Siege jobs.

Military-tagged Tier 2 entities will actively seek out and attempt to kill entities of the rival faction.

5. Player Integration (The Chaos Agent)

The player interacts with this system purely through gameplay loops, not UI menus.

Earning Reputation: Completing a physical action (dropping a pile of iron ore in a friendly village stockpile, assisting a goblin patrol under attack by spiders) is detected by the SocialSystem and positively adjusts the score in the faction's DiplomacyComponent towards Faction 0 (the player).

Losing Reputation: Stealing from stockpiles, attacking citizens, or introducing extreme Filth into a faction's zone generates massive grievances.

Diplomatic Immunity/Hostility:

At high reputation, the player is granted the Trade status, allowing them to safely access deep-dungeon faction merchants.

At War status, Tier 2 guards will attack the player on sight, and the LLM might dispatch specific "Bounty Hunter" squads (specialized Job Queue) to track the player across floors.

6. Integrated Corrections (ADR / Adversarial Review)

Authoritative note: governed by docs/architecture_decisions.md and
docs/component_and_field_registry.md. The following resolve review findings B6, C7, D3,
D4, D5, F3.

Ownership representation (C7): item ownership is the OwnershipComponent{faction_id} — NOT a
tag. Zone control uses ClaimTags on the zone entity (distinct from item ownership). The
"[Owned_By_Faction: N]" tag phrasing elsewhere is void.

Faction memory for Abstracted factions (B6): a leader's salient LLM context cannot depend on
individual Tier-2 gossip, because Abstracted factions have no individuals. Therefore
FactionCoreComponent carries its own faction_memory: Array[MemoryEvent]. Macro-level systems
(GrayBox, war resolution, diplomacy, DAG edges) write MemoryEvents here directly, so a
leader's context stays fresh even when its faction is Abstracted. Individual gossip still
feeds Tier-2 MemoryComponents when Active/Simulated and is periodically summarized up into
faction_memory.

Memory weight & decay (F3): each MemoryEvent has weight:float and core:bool. weight =
base_weight(event_type) * recency_falloff(age) + emotional_bonus(core). Salience selection
(LLM) takes the top-3 by weight (Core Memories) plus the 3 most recent, per the LLM doc.
Decay is applied on the Macro tick; core memories decay slowly, mundane ones quickly.

Crime detection vs. gossip (D3): revoking [Guest_Status] is NOT an omniscient global flag.
A [Crime] act only propagates reputation when a witness perceives it (a guard's vision cone,
or a victim entity) — that witness gains a MemoryEvent and, via the gossip/Job_Chat pipeline,
the village faction's reputation toward Faction 0 degrades and [Guest_Status] is revoked. An
explicit "caught red-handed" fast path exists (a witnessing [Prof_Guard] reacts immediately),
but an unwitnessed crime does not instantly alert the whole faction. This reconciles the
world_bootstrap "revoked on [Crime]" rule with the emergent, non-hivemind reputation model.

Bounded factions & diplomacy (D4, ADR-12): hard cap on simultaneous factions / Tier-3 LLM
agents (default 24). When exceeded, the weakest are merged or abstracted into gray-box pools.
DiplomacyComponent keeps only the top-K relationships (default 12) by |score|/recency;
dropped relationships default to NEUTRAL. Schism splinters and gray-box migrations both
respect this cap (a schism that would exceed it merges the weakest existing faction first).

Runtime DAG compaction (D5): see the DAG doc — factions that leave no live descendants,
artifacts, or physical ruins are pruned on a slow cadence and at each Interregnum so the
diplomacy matrix and DAG do not grow without bound across death loops.

Job-claim lifecycle: JobComponent carries status:JobStatus and claimed_by:EntityHandle. If a
claimant dies or drops the job, the job returns to OPEN for re-claiming (no orphaned jobs).
Squads are temporary sub-faction entities with a squad-leader handle; members steer toward
the leader (cohesion) via the same local-steering path as any mover.
