World Bootstrapping & The Overworld Architecture

Target Audience: Lead Coding Agent / Systems Architect
Context: This document defines the engine's initialization sequence immediately following DAG History Generation, up to the moment the player gains control on Day 0. It covers the procedural generation of the Surface Village, the "Pre-Warming" of the ECS economy, the distribution of DAG history via a diegetic Information Economy, and the strict initialization parameters for the Player Entity.

1. The Overworld (Village) Generation

The Surface Village cannot use standard dungeon generation (WFC or Cellular Automata). It requires a rigid, functional zoning algorithm to ensure it acts as a reliable safe haven and economic hub.

A. The Radial Zoning Algorithm

The village is generated on a grid, but logically organized in concentric rings from a central anchor.

The Anchor (Ring 0): The [Plaza_Zone]. Contains a well (MAT_WATER source) and the [Bounty_Board].

The Core (Ring 1 - Radius 10 tiles): Essential services.

[Zone_Tavern]: High [Social_Zone] value.

[Zone_Residence]: The Adventurer's Estate (Entity 0 spawn point).

[Zone_Market]: General merchants.

The Industry (Ring 2 - Radius 20 tiles): [Zone_Smithy], [Zone_Alchemist]. These require EnergyComponent stations (Forges) and generate [Filth_Minor] (smoke/ash), so they are placed away from the plaza.

The Agrarian Rim (Ring 3 - Radius 30 tiles): [Zone_Farm]. Spawns MAT_BIOMASS crops.

B. Building Instantiation

Buildings are predefined prefab nodes or modular WFC blocks, but they are dynamically assigned to the zones based on the DAG. If the DAG says the village was founded by Dwarven refugees, the buildings use the [Stonework] tag.

2. The Engine Pre-Warm Sequence

To prevent the economy from crashing on Day 0, Minute 1, the ECS must simulate a brief period of "off-screen" time to stock shelves and stabilize needs.

The Resource Injection: Based on the Village's terminal DAG state (e.g., "Wealth: Moderate, Focus: Mining"), the engine injects raw Base Materials directly into the faction's [Stockpile] entities.

The 100-Tick Fast Forward: Before giving the player input, the engine runs 100 Simulation Ticks as fast as the CPU allows.

Result: Haulers move the injected materials to Crafters. Crafters turn MAT_IRON into Swords. Merchants move Swords to [Display_Tables].

End State: When the player walks into the Smithy on Day 0, there are physical weapons on the table to buy.

3. Managing the LLM Cold Start

To prevent API rate-limiting and a massive latency spike when the game starts, the Tier 3 LLM agents cannot all fire their initial "Reasoning Tick" at T=0.

The Staggered Queue: During the Pre-Warm, the engine collects all Tier 3 entities. It assigns them a random Tick_Offset between 1 and 600.

The Default State: Until their offset is reached, Tier 3 entities adopt a fallback [Objective: Fortify/Idle] state.

Effect: The Goblin King might query the LLM 10 seconds into gameplay, while the Spore-Lord queries it 3 minutes into gameplay. The API load is smoothed out.

4. The Information Economy (The Rumor Mill)

For Adventurer 0 (who has an empty Lineage Journal), the world is a black box. The DAG history must be converted into diegetic information the player can discover.

A. The Gossip System (Taverns & Plazas)

Tier 2 entities have a MindComponent with Known_History.

When idle in a [Social_Zone], they run a Job_Chat intent.

The UI hooks into this via text bubbles. The engine queries the DAG for an edge connected to this faction.

Translation: DAG Edge: [Village] --(Fears)--> [Floor 2 Spore-Lord].

NPC Bark Output: "They say the deep rocks on the second floor are breathing... the Dwarves lost everything down there."

B. The Bounty Board (Structured Quests)

The Village Elder (Tier 3 LLM) periodically generates bounties based on their faction needs.

If the village's [Stockpile] is critically low on MAT_COAL, the LLM Reasoner creates a Request_Resource objective.

The Engine Planner translates this into a physical [Paper] entity pinned to the [Bounty_Board] in the plaza: "Contract: 50kg Coal. Reward: 100 Gold."

5. Weather, Seasons, and Time

The Overworld is subject to a global ClimateSystem running on the Macro Tick.

The Calendar: 360-day year, 4 seasons. Day 0 begins on Spring 1.

Weather Events: Overworld chunks can receive the [Raining] tag.

Systemic Impact: This physically spawns MAT_WATER puddles in the village. Dirt roads turn to [Mud] (reduces movement speed). NPCs without the [Stoic] culture tag will pathfind to the nearest [Roof] zone to avoid losing Morale.

6. Entity 0 Initialization (The Player Spawn Parameters)

To ensure the player does not spawn into a hostile or broken state on Day 0, the engine applies strict initialization rules derived from the DAG.

A. The Starting Gear (Wealth Inheritance)

The player does not spawn with an arbitrary loadout. Their InventoryComponent is populated based on the Village's DAG Wealth stat.

Impoverished Village: Spawns with [Rusted_Iron_Dagger], [Tattered_Cloak], 5 MAT_GOLD coins.

Wealthy Village: Spawns with [Iron_Sword], [Leather_Cuirass], [Torch], 50 MAT_GOLD coins.

B. Baseline Knowledge (Cultural Inheritance)

To prevent the player from being utterly blind to basic crafting, their MindComponent inherits the Village_Culture tags.

If the village is [Dwarven_Refugees], the player starts with Insight[MAT_IRON_SMELTING] and Insight[Rune_Stability]. This auto-unlocks basic recipes in their Lineage Journal on Day 0.

C. Legal Authority (The Guest Status)

Because property is physically owned and zoned by NPCs, a newly spawned player would instantly trigger trespass/theft alarms.

Entity 0 is initialized with a [Guest_Status] tag inside the Village limits.

This acts as a temporary override in the ECS SocialSystem, preventing [Prof_Guard] entities from attacking them for entering [Zone_Market] or [Zone_Tavern]. This status is permanently revoked if the player commits an act with the [Crime] tag.

7. Integrated Corrections (ADR / Adversarial Review)

Authoritative note: governed by docs/architecture_decisions.md.

Guest-Status crime (review D3): [Guest_Status] revocation is witness-gated, not omniscient.
See factions doc §6 — a [Crime] act must be perceived by a witness (guard vision cone or
victim) to propagate reputation via gossip and revoke guest status; a "caught red-handed"
fast path exists for a witnessing guard. Unwitnessed crimes do not instantly alert the faction.

Climate cadence (ADR-9): the ClimateSystem runs on the Macro tick = 1 in-game hour, so
weather (rain -> MAT_WATER puddles, [Mud]) updates at hourly granularity. The 360-day/4-season
calendar derives from hour counts. This supersedes any "per-macro-tick = per-month" reading.

Player init (ADR-14): Entity 0 = Faction 0. The synthetic Faction-0 DAG node is registered
here at bootstrap so social/diplomacy systems can track the player like any faction.

Pre-Warm ordering & physics: pre-warm crafted items snap to [Display_Table] coordinates and
skip the loose-item integrator (Sprint 1 §9) to avoid Day-0 settling churn (matches Sprint 2
Bootstrapper). Ledger<->physical wealth uses the transactional/idempotent sync (Sprint 2 D1).
