The First Hour: Day 0 Gameplay Flow & Transition

Target Audience: Lead Coding Agent / QA / UI UX Team
Context: This document traces the exact user experience, ECS event flow, and data state for "Entity 0" (The Player) during the first hour of gameplay. It provides concrete examples of how the Godot Engine (Viewer) interacts with the pure-data ECS layer.

Phase 1: Waking Up (06:00, The Estate)

The Scene: The player spawns in the [Zone_Residence]. The Overworld macro-clock reads Epoch 42, Spring 1, 06:00.
System State: The Micro Tick is active for the player's 3x3 chunk grid. The rest of the village is on the Simulation Tick.

Initialization Payload: Entity 0 is constructed via the world_bootstrapping_and_the_overworld_architecture.md parameters.

// Entity 0 Initial State
{
  "BodyComponent": { "health": 100, "stamina": 100, "skills": {} },
  "MindComponent": { "insight": {"Cult_Dwarf": 10}, "known_runes": ["RUNE_KINETIC"] },
  "InventoryComponent": { "held_items": [{"index": 401, "generation": 1}, {"index": 402, "generation": 1}], "total_volume_used": 1200 },
  "ContainerComponent": { "capacity_cm3": 50000 },
  "ChemistryComponent": { "active_tags": ["Guest_Status"] }
}



(Note: Entity_401 is an Iron Dagger, Entity_402 is 10 Gold Coins).

The Interface (Tactical Lens): The player holds the "Inspect" key. The Godot UI fires an event to the ECS: query_entity_data(target_id=881).

Entity 881 is a Candle. The ECS checks the player's MindComponent.insight against the Candle. Because candles are basic, it returns full data.

UI Renders: [Wax], [Burning], Temp: 80°C.

The Lineage Journal: The player clicks the journal. Godot reads the local journal_save.json (empty on run 1) and cross-references it with the player's MindComponent. The UI populates with baseline Dwarven smelting recipes.

Phase 2: The Village Loop (Economic Prep)

The Scene: The player walks out into the [Plaza_Zone]. The ECS Pre-Warm has finished.
System State: The MetabolismSystem is ticking. NPCs are executing their ScheduleComponent
Work block (registry §2 — there is no `RoutineComponent`).

Physical Barter (The Math): The player approaches a [Prof_Merchant] in the [Zone_Smithy]. They inspect an Iron Shield (Entity 905).

Price Calculation Event: The EconomySystem calculates real-time value.
Base_Value (10) * (1 + (Demand_MILITARY / Local_Iron_Stockpile + 1)) * Quality (1.0) = 15 Gold.

The Transaction: The player places 15 MAT_GOLD physical entities on the barter zone. The Godot UI sends a JobIntent_Trade.

Resolution: The ECS verifies the offered coins' summed value meets the price (mass remains
only an encumbrance/physics property). The Merchant's AI accepts. The ECS transfers the
shield's OwnershipComponent from faction 12 to Faction 0. The player equips it.

The Rumor Mill (DAG Leakage): Passing the well, an NPC (Entity 112) is running a Job_Chat.

The SocialSystem randomly selects an edge from the DAG connected to the village: [Village] --(Fears)--> [Floor 1 Rust-Mites].

The NPC barks: "The old foundry on the first floor is infested with rust-mites... keep your blade oiled."

Phase 3: The Threshold (Leaving the Gray Box)

The Scene: The player approaches the elevator leading to Floor 1.
System State: Crossing this threshold triggers the LoDSystem boundary logic.

The Unload: As the player descends, the Z-axis coordinate changes. The Godot Engine unloads the 3D/2D visual nodes of the Village.

ECS Memory Shift: The Village chunks shift from Active -> Simulated -> Abstracted. Village NPCs drop their Vector3 positions and are now tracked as Node_IDs on a topological graph.

The Load: Floor 1's entry chunk shifts from Abstracted directly to Active. The Godot Engine instantiates visual nodes based on the ECS entities currently occupying that chunk.

Phase 4: Floor 1 (The First Encounter)

The Scene: The player steps out onto Floor 1 (Dwarven Ruin on Granite).
System State: The Micro Tick engages for this chunk. Physics and Chemistry are live.

Thermodynamics & Survival: The ClimateSystem detects the player is in [Zone_Subterranean]. The ambient temperature is 5°C.

The player lacks a [Warm] clothing tag or a [Torch].

MetabolismSystem math: Stamina_Drain = Base_Drain (1.0) + (Ideal_Temp (20) - Current_Temp (5)) * 0.1 = 2.5 per tick. The player notices their stamina bar depleting faster.

The Tier 1 Swarm (Combat Resolution): The SwarmGrowthSystem evaluates the [Filth_Heavy] tag in the room and physically spawns 3 Corpse-Rats. A rat lunges.

The Swing: The player clicks attack. Godot sends ActionIntent_Melee(Target: Rat_1).

The Math: ActionResolutionSystem calculates: Player_Velocity * (Dagger_Mass + Player_Strength). The kinetic force exceeds the Rat's Biomass_Density.

The Result: The Rat's health hits 0. It is converted into a [Corpse] item. 3 units of MAT_BLOOD are spawned as a PuddleEntity, which begins spreading via Cellular Automata.

The Tier 2 Scavenger (Emergent AI): The player spots a Goblin [Prof_Hauler] mining copper.

Perception: The Goblin's VisionCone intersects the player.

Threat Calculation: The Goblin's Utility AI evaluates the player's equipment (Dagger + Shield) vs. its own (Pickaxe). Player Threat > Goblin Combat_Skill.

State Shift: The Goblin's JobComponent aborts Job_Mine. It pushes Job_Flee(Target: Nearest_Guard) to the top of its queue. It turns and runs, emitting an ECS [Alert] aura that will wake up adjacent hostile NPCs.

Resource Extraction (Inventory Physics): The player approaches the copper vein.

They execute ActionIntent_Mine.

The wall's MaterialComposition yields 5 MAT_COPPER nuggets.

The player puts them in their backpack. The InventorySystem adds 5kg to the player's Total_Mass. The player's movement speed slightly decreases because ECS movement resolution applies the mass divisor before the viewer reads the resulting PositionComponent.

The Loop Closes: The player is cold, their stamina is draining, they have 5kg of copper, and they know the Goblin is bringing a guard. They retreat to the elevator. The simulation of Floor 1 returns to Simulated state, while the Village wakes back up into the Active state to receive them.

Integrated Corrections (ADR / Adversarial Review)

Authoritative note: governed by docs/architecture_decisions.md and the registry. This
narrative walkthrough predates the ADRs; where it differs, the ADRs win:
- chunk_id is Vector3i(x,y,floor) (ADR-3); ticks per ADR-9 (Sim 2Hz, Macro hourly).
- Player = Entity 0 = Faction 0 (ADR-14).
- Combat targeting uses the ECS PickSystem, and kinetic force uses
  BodyComponent.strength + the defined force unit (Sprint 1 §10) — not undefined stats.
- When the Village shifts Active -> Simulated, movers retain current_edge/edge_progress/
  edge_speed (not just Node_Id) so positions/interceptions can be reconstructed (review G4);
  wealth uses the transactional/idempotent ledger sync (Sprint 2 D1).
- Movement/collision is ECS-owned (no move_and_slide); the copper mass affecting speed is the
  velocity divisor applied in the ECS, read by the viewer.
