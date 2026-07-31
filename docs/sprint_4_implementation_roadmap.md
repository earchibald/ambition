Implementation Roadmap: Sprint 4 (The Crucible)

Target Audience: Lead Coding Agent
Objective: Implement the modular spell-crafting system, advanced ECS chemistry (chain reactions), and the biological mutation loop. This sprint turns the dungeon from a physical simulation into a reactive, magical ecosystem.

Step 1: Advanced Chemistry & Chain Reactions

The Objective: Expand the tag-based chemistry system from Sprint 1 to support volatile chain reactions, area-of-effect states, and environmental hazards.
Required Implementation:

Update FluidDynamicsSystem to handle gas and temperature propagation (e.g., expanding radii).

Implement ReactionSystem. When two incompatible tags meet (e.g., [Volatile_Gas] + [Burning]), trigger an immediate physics event (Kinetic explosion + temperature spike) and consume the entities.

CRITICAL - Anti-Recursion Lock: Immediately apply a [Reaction_Cooldown] tag to the participating entities/grid-cells for 60 Micro Ticks to prevent infinite loop stack overflows.

Success State: Dropping a torch into a room filled with [Spores] causes a flash-fire that burns all biomass in the room, raises the ambient temp, and cannot instantly re-trigger itself.

Step 2: The Grimoire (Modular Spell Logic)

The Objective: Build the backend data structure for the player to construct spells using Runes (Triggers, Shapes, Catalysts). No UI yet, just data validation.
Required Implementation:

Build the SpellCompilerSystem. It accepts an array of Rune IDs.

CRITICAL - The Complexity Cap: Implement a Strain_Cost calculation. If a spell's complexity exceeds the player's MindComponent.insight, compilation fails.

CRITICAL - The Geometric Cap: Enforce absolute maximums on shape variables (e.g., max projectile speed, max aura radius = 15m) to prevent CPU-wiping "Map Nuke" spells.

Success State: The engine successfully validates a 3-rune array, calculates its base stamina cost, caps its radius, and registers it as a valid Action_ID.

Step 3: Ephemeral Entities (Magic Execution)

The Objective: Translate a compiled spell into physical ECS reality.
Required Implementation:

Update ActionResolutionSystem to handle ActionIntent_Cast.

When executed, spawn an [EphemeralEntity] into the ECS. This entity has a strict TTL (Time-To-Live).

The EphemeralEntity moves via physics or expands, applying its Catalyst tags to any entity it collides with.

Success State: The player casts "Fireball." A glowing Node3D moves through the world. It hits a Goblin, applies the [Burning] tag, and deletes itself.

Step 4: Biological Mutation & The Ecology Loop

The Objective: Make the player's body vulnerable to the environment, turning hazards into progression (or regression).
Required Implementation:

Build the MutationSystem (Runs on the Simulation Tick).

If Entity 0 stays in a chunk with high [Filth] or [Radiation] tags without protective gear, increment an Exposure float in their BodyComponent.

When Exposure hits 100, roll on a mutation table. Apply a permanent physiological tag (e.g., [Tag_Fungal_Lungs]).

CRITICAL - Faction Alignment Shift: Connect the SocialSystem to check player tags. If the player mutates to [Tag_Fungal], the Spore-Lord's faction shifts toward neutral, while the Surface Village shifts toward hostile.

Success State: The player wades through toxic sludge. They gain acid resistance, but the village guards refuse to let them into the tavern.

Integrated Corrections (ADR / Adversarial Review): reaction keys are sorted tag-pairs with
INTRA/INTER scope (F2); temperature uses the material §7 heat model (H2); Absorb_Tag consumes a
quantified, atomically-guarded environmental resource (D8); magic reuses the Sprint 1 Ephemeral/
aura primitive; the mutation->faction shift is gossip-propagated reputation, not instant (D3).
See sprint_4_technical_scaffolding.md §5.
