Inventory & Grimoire Mechanics Specification

Target Audience: Lead Coding Agent / UI UX Team / Systems Designer
Context: This document provides the concrete systemic mechanics, math, and UX flows for the diegetic Inventory and Grimoire systems. It defines how the ECS physics engine translates these concepts into playable, interactive loops without relying on abstract menus.

1. The Inventory: Physicality Without the Tedium

A. The "Over-Stuff" & Rupture Mechanic

The Concept: Players can push their luck by exceeding their carrying capacity, risking catastrophic physical item spills during combat or traversal.

The Math: A Backpack entity has a VolumeCapacity_cm3 (e.g., 50,000). The UI allows the player to insert items up to 57,500 cm3 (115%).

The ECS State: When Volume > 100%, the Backpack entity receives the [Bursting] tag. Its Condition stat begins to degrade by 1 point per Micro-Tick while moving.

The Trigger: If the player suffers a Kinetic_Impact > 200 force (taking a heavy hit, falling more than 3 meters), the system rolls a check: Impact_Force vs (Backpack_Condition * Overstuff_Percentage).

The Rupture (Action Resolution): On failure, the Backpack's [Bursting] tag triggers a physical explosion.

The ECS forcefully removes 10-20% of the volume from the inventory (randomly selecting items).

These items are spawned as physical entities into the Active chunk with outward velocity vectors.

CRITICAL - Cascade Prevention: Immediately upon rupturing, the Backpack receives a [Rupture_Cooldown] tag for 3.0 seconds. This prevents rapid-ticking Damage-Over-Time (DOT) effects or shotgun blasts from emptying the entire inventory in a single frame and crashing the physics engine.

UX: A loud canvas-tearing sound plays, the UI volume bar flashes white, and the player watches their hard-earned gold and potions violently scatter across the dungeon floor.

B. Smart Sub-Containers & Diegetic Sorting

The Concept: Eliminating inventory tetris via rule-based physical bags that exist inside the main backpack.

ECS Implementation: The Backpack's InventoryComponent contains a sub_containers array. Each
sub-container is an entity with ContainerComponent capacity and accept/reject filters.

Nesting Limitation: To prevent infinite volume recursion exploits ("bags of holding inside
bags of holding"), sub-containers strictly reject entities with ContainerComponent unless
their own `allow_nested_container` flag explicitly permits it.

UX Flow: In the UI, the Backpack is a vertical list. Sub-containers act as collapsible headers. Clicking "Auto-Sort" routes items to matching headers based on ECS tags.

Specialized Examples:

Alchemist's Bandolier: Filter: [Fluid_Container]. Items inside this bandolier bypass the "Search" time penalty, allowing them to be instantly moved to the Belt (Quick Slots) without the normal 0.5s delay.

Lead-Lined Lockbox: Filter: [Radioactive], [Volatile]. Items inside have their Aura tags suppressed. A highly radioactive core won't mutate the player's BodyComponent while inside this box, but the box has massive mass_kg, draining stamina.

C. Acoustic Encumbrance & The Wrapping Mechanic

The Concept: Stealth is heavily compromised by the acoustic properties of the materials the player is carrying.

The Acoustic Math: Every material has an Acoustic_Resonance float. MAT_GLASS is 0.9, MAT_IRON is 0.7, MAT_CLOTH is 0.1.

CORRECTED (2026-07-31). The old curve was
`Base_Noise + Log10(Sum of Inventory Acoustic Values) * Velocity`, described as creating "a hard
cap where inventory noise cannot exceed a 30-meter radius." It does not. `log10` is unbounded,
so there is no cap at all — 1,000 glass vials (sum 900) while falling at 10 m/s gives
`5 + 2.954*10 = 34.5 m`, already past 30. It is also undefined on an empty inventory
(`log10(0) = -inf`), returns NEGATIVE radii (one cloth item at 20 m/s gives -15 m), and collapses
to `Base_Noise` at zero velocity, so standing still while carrying 1,000 vials is silent.

    const BASE_NOISE_M: float = 2.0
    const K_ACOUSTIC: float = 6.0
    const V_REF_MPS: float = 3.0
    const MAX_NOISE_M: float = 30.0

    noise_radius_m = clamp(BASE_NOISE_M
                           + K_ACOUSTIC * log10(1.0 + acoustic_sum) * (velocity_mps / V_REF_MPS),
                           BASE_NOISE_M, MAX_NOISE_M)

Verification: empty inventory -> `log10(1) = 0` -> 2 m (defined). 1,000 glass vials walking ->
19.7 m. Falling at 15 m/s -> clamped to exactly 30 m (the cap is now real). Standing still ->
2 m, not 0. Monotone in both inputs and never negative.

This feeds `SensoryEmitterComponent.noise_radius_m`, which the hearing model in
sprint_1_technical_scaffolding §11 converts to decibels and attenuates through walls.

The Solution (Wrapping & Lining): Players have two systemic ways to solve this.

Item Wrapping: In the CraftingUI, the player combines Scrap_Cloth + [Item]. The ECS applies a [Muffled] tag to the item's ChemistryComponent, reducing its Acoustic_Resonance by 90%. (e.g., Cloth-wrapped Glass Vial).

Container Lining (QoL): Instead of wrapping 50 individual vials, the player can craft a [Padded_Pouch] (Leather + Wool). Any item sorted into this specific Sub-Container automatically inherits the [Muffled] modifier while inside.

2. The Grimoire: Hacking the ECS

A. The "Dry Run" Hologram

The Concept: A safe, visual sandbox for testing dangerous node logic before committing it to memory.

UX Implementation: A small 3D viewport rendered via Godot's SubViewport node sits next to the node graph.

ECS Handshake: When nodes are linked, the UI sends the JSON array to a lightweight validation loop (a dummy math instance, not the live physics engine). This dry run costs the player zero Strain_Cost and consumes no physical materials.

Visual Feedback:

If the spell is valid, the SubViewport renders wireframe spheres and cones representing the exact geometric bounds of the spell's effect.

If the spell fails validation (e.g., geometric limits exceeded), the wireframe violently shakes, turns red, and shatters, displaying the specific error (e.g., WARN: Radius > 15m).

B. Environmental Sockets (Absorb State)

The Concept: Spells can dynamically steal tags from the physical environment to power themselves, reducing the player's biological Strain_Cost.

The Node: Catalyst: [Absorb_Tag]. The player configures the node to seek a specific string, e.g., [Heat].

The ECS Action:

The player casts the incomplete spell at a Campfire (which has the [Heat] and [Burning] tags).

The spell's EphemeralEntity collides with the Campfire.

The ActionResolutionSystem rips the [Heat] tag from the Campfire (extinguishing it), stores it in the EphemeralEntity, and forwards the energy to the next node in the graph.

The Fizzle State: If the spell collides with a wall or entity that lacks the [Heat] tag, the EphemeralEntity destabilizes into a harmless [Spark] and dissipates. The cast is wasted, enforcing precise aiming.

C. Overclocking & The Mishap Table

The Concept: Allowing players to force-compile a spell that exceeds their cognitive or stamina limits, introducing massive risk.

The Trigger: If Compiled_Strain > Max_Stamina, the "Bind" button turns jagged and red. Clicking it forces the compile but permanently brands the spell JSON with the [Unstable] tag.

The Resolution: When cast, the ECS rolls a d100 against the spell's variance.

01-50 (Success with Blood): The spell casts perfectly, but the excess Strain_Cost is deducted directly from Health, causing a physical [Bleeding] wound.

51-85 (Over-Pressure): The geometric bounds of the spell double (up to the engine's hard cap of 15m). A 5m fireball becomes a 10m fireball, hitting the enemies, the walls, and the player.

86-100 (Syntax Inversion): The trigger/target logic reverses. Target: Crosshair becomes Target: Self.

CRITICAL - The Mercy Cap: To prevent cheap permadeath, magic mishaps (including Syntax Inversion) cannot reduce Entity 0's health below 1 HP. Instead, excess damage is converted into severe BodyComponent trauma tags (e.g., [Arcane_Burn], [Shattered_Nerves]) that cripple stamina regeneration and require advanced medical crafting to cure.

D. The Translation Cipher Minigame

The Concept: Magic is archaeological. Players must translate ancient syntaxes based on their character's cultural knowledge.

UX Flow: The player loots a [Goblin_Pyromancer_Tablet] and drops it into the Grimoire.

The Cipher Engine: The UI checks the player's MindComponent.Insight[Cult_Goblin].

Low Insight (0-20): Nodes appear on the grid, but the text is semantically masked. A Shape node might read shape?_Projectile. The variables are locked (e.g., Speed: unknown?).

Medium Insight (21-50): The text is partially translated. Slow_Projectile.

High Insight (51+): Perfect translation. Heavy_Projectile(Speed: 5, Mass: 20).

Gameplay: A player with Low Insight can still attempt to "Dry Run" the spell to visually guess what the hidden nodes do based on the wireframe simulation, effectively reverse-engineering the magic through trial and error.

3. Integrated Corrections (ADR / Adversarial Review)

Rupture / loose-item motion (review B4/D7): items ejected on backpack rupture (and any
dropped/thrown solids) move via the Sprint 1 loose-item integrator + grid collision with
sleep-on-rest (sprint_1_technical_scaffolding.md §9) — there is no Godot rigid-body physics.
Resting positions are deterministic given the same inputs within a run and are serialized.

Stack split/merge (review D7): a quantity-stacked entity (e.g., 10,000 gold as one entity)
splits when a partial amount is spilled/dropped: decrement source.quantity and spawn a new
entity with the removed quantity (and identical material/quality/tags). Pickup auto-merges
into an existing stack with matching material_id + quality + tags. The [Rupture_Cooldown]
(3.0s) still guards against cascade emptying.

Materialization policy (review 2026-07-31 A3): backpack contents, sub-containers, Residence
stash contents, equipped items, artifacts, and caravan cargo are identity-bearing manifests
when LoD downgrades. Only explicit fungible commodity stacks ledgerize; containers preserve
nested manifests rather than flattening to raw material ledgers.

Absorb_Tag conservation (review D8): see magic doc §6 — Absorb consumes a quantified
environmental resource atomically; concurrent absorbs cannot double-spend, and the Dry Run
hologram reflects available environmental quantity.

Grimoire picking/validation: Dry Run uses a dummy math instance (no live physics); geometric
caps (max radius 15m, max speed) are enforced by the SpellCompiler (Sprint 4). Cipher masking
is semantic (see ui_ux §8), not scrambled.
