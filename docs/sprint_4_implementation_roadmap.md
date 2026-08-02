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

The Objective: Build the backend data structure for the player to construct spells using Runes (Triggers, Shapes, Catalysts).

CORRECTED 2026-08-01: "No UI yet, just data validation" is superseded. `docs/scope_and_milestones.md`
assigns Sprint 4 "chemistry reactions, spell compiler **plus the Grimoire UI that fronts it**", and
this project has shipped four systems that were implemented, tested, and had no route in from the
keyboard (`resolve_fall`, `DebugOverlay.select_row`, `on_timeout`, `report_crime`). A compiler with
no way to reach it would have been the fifth. Built at debug-panel fidelity — a keyboard-driven
rune list with a live preview — NOT the node-graph editor, the 3D Dry Run hologram, or the cipher
minigame, which remain a UI sprint and are declared in RUNNING.md's NOT-built list.
Required Implementation:

Build the SpellCompilerSystem. It accepts an array of Rune IDs.

CRITICAL - The Complexity Cap: Implement a Strain_Cost calculation. If a spell's complexity
exceeds `MindComponent.insight.get(&"Rune_Stability", 0) * 1.5`, compilation fails.
(`insight` is a Dictionary{StringName:int} — registry §2 — never a bare scalar.)

CRITICAL - The Geometric Cap: Enforce absolute maximums on shape variables (e.g., max projectile speed, max aura radius = 15m) to prevent CPU-wiping "Map Nuke" spells.

Success State: The engine successfully validates a 3-rune array, calculates its base stamina cost, caps its radius, and registers it as a valid Action_ID.

CORRECTED 2026-08-01: the two caps FAIL DIFFERENTLY and the distinction is the design. Complexity
REFUSES with a reason the player can act on; geometry CLAMPS and records that it clamped. Refusing
an oversized radius would let a player author a spell they can never cast and never learn why;
clamping silently would hand them a different spell than the one they built. See the scaffolding
§6.

Step 3: Ephemeral Entities (Magic Execution)

The Objective: Translate a compiled spell into physical ECS reality.
Required Implementation:

Update ActionResolutionSystem to handle ActionIntent_Cast.

When executed, spawn an [EphemeralEntity] into the ECS. This entity has a strict TTL (Time-To-Live).

The EphemeralEntity moves via the ECS movement/collision systems or expands as an ECS aura,
applying Catalyst tags to entities found via SpatialHash overlap.

Success State: The player casts "Fireball." A glowing Node3D moves through the world. It hits a Goblin, applies the [Burning] tag, and deletes itself.

CORRECTED 2026-08-01: "a glowing Node3D" overstates the visual. The cast spawns a real ECS entity
that moves, tests contact against the SpatialHash and the tile grid, applies its payload and
deletes itself — and `ViewManager` draws it as an ordinary box. Particles, light and trails are
not built, and are declared in RUNNING.md.

Also corrected: heat alone does not ignite. There is no ignition-temperature model, so the
standard fireball needs an `Apply_Burning` catalyst as well as `Add_Temperature` for the success
state above to hold.

Step 4: Biological Mutation & The Ecology Loop

The Objective: Make the player's body vulnerable to the environment, turning hazards into progression (or regression).
Required Implementation:

Build the MutationSystem (Runs on the Simulation Tick).

If Entity 0 stays in a chunk with high [Filth] or [Radiation] tags without protective gear, increment an Exposure float in their BodyComponent.

When Exposure hits 100, roll on a mutation table. Apply a permanent physiological tag (e.g., [Tag_Fungal_Lungs]).

CRITICAL - Faction Alignment Shift: Connect the SocialSystem to check player tags. If the player mutates to [Tag_Fungal], the Spore-Lord's faction shifts toward neutral, while the Surface Village shifts toward hostile.

Success State: The player wades through toxic sludge. They gain acid resistance, but the village guards refuse to let them into the tavern.

CORRECTED 2026-08-01: the second half of that sentence is NOT built and is not Sprint 4 scope.
Guards, arrest, and gated access do not exist; there is no tavern and nothing refuses you entry
anywhere. What IS built is the reputation half: a witnessed mutation moves the village's opinion
of you negative and a scavenging culture's positive, propagated by gossip rather than instantly.
The behavioural consequence of that opinion is a later sprint. Declared in RUNNING.md rather than
quietly reinterpreted.

Also: there is no toxic sludge to wade through. No hazard zone occurs naturally in either
scenario, so `H` toggles one on the current chunk — the same standing-in-for-content role `K`
plays for death.

Integrated Corrections (ADR / Adversarial Review): reaction keys are sorted tag-pairs with
INTRA/INTER scope (F2); temperature uses the material §7 heat model (H2); Absorb_Tag consumes a
quantified, atomically-guarded environmental resource (D8); magic reuses the Sprint 1 Ephemeral/
aura primitive; the mutation->faction shift is gossip-propagated reputation, not instant (D3).
See sprint_4_technical_scaffolding.md §5.

Step 5: Playability Defects Carried Into Sprint 4

The Objective: Clear player-facing defects found in play during Sprint 3, before adding systems
on top of them. These are not new features. Each one is something a play-tester hit.

Required Implementation:

TAB MUST TOGGLE. Tab currently selects the entity under the cursor and there is no way to
deselect. `_select_under_cursor()` falls back to the player row when nothing is near the cursor,
so the LIVE overlay always shows an inspection panel and the player cannot get the display back.
Pressing Tab again on the same target must CLEAR the selection.

Three behaviours, and they must be distinguishable:

- Tab on a new target -> inspect that target.
- Tab again on the SAME target -> clear the selection, restoring the unobstructed LIVE view.
- Tab on empty ground -> clear the selection. Do NOT fall back to the player row.

That last one reverses a Sprint 3 decision. The fallback was added so Tab "always shows something
useful", which was the right fix for a hitbox that felt broken and the wrong fix once the panel
became large enough to obstruct the view. `DebugOverlay` already treats `_selected_row = -1` as
"nothing selected" and branches on it, so the state exists and only the input path needs changing.

Success State: The player Tabs a villager, reads the panel, Tabs the same villager again and the
panel disappears. They then Tab a second villager directly without a clearing press in between,
and the panel shows the second villager rather than toggling off.

Do this FIRST in the sprint. Sprint 4 adds chemistry, spells and mutation, all of which are
inspected through this panel — debugging them through a panel you cannot dismiss makes every
later step slower.
