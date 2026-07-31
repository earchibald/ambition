UI/UX Architecture & Player Interactivity

Target Audience: Lead Coding Agent / UI UX Designer
Context: This document outlines how the player (Entity 0) interacts with the systemic world built in Sprints 1-4. The UI must expose the massive ECS simulation without overwhelming the player, strictly gating information behind the player's diegetic knowledge (MindComponent). It also defines the Developer "God-Mode" required to debug this complex architecture.

1. Core Philosophy: The UI is a "Dumb Listener"

The UI must never contain game logic.

Signals Only: The Godot UI subscribes to global signals emitted by the global ECSEvents autoload (e.g., on_inventory_updated(entity_id), on_health_changed()).

Intent Generation: Clicking "Drink Potion" does not increase health. It constructs an ActionIntent_Consume struct and pushes it to the ECS JobQueue. The ECS processes the fluid transfer and chemistry, emits the change, and the UI merely visually reflects that change.

2. The Tactical Lens (The Insight Filter)

The world is a web of chemical tags, temperatures, and LLM objectives. Floating text above every object would ruin the atmosphere and cause extreme visual clutter.

Activation (Toggle-to-Think): Pressing the "Inspect" key (e.g., 'Tab') acts as a toggle by
default, applying a simulation `time_scale` multiplier (bullet-time) and overlaying ECS data
onto the 3D world. NOTE (ADR-9): the Micro tick rate stays fixed at 60Hz. Bullet-time scales
the per-tick `delta` used for integration/velocity, never the tick frequency itself. The player can safely mouse over entities to read them at their own pace, then press the key again to exit. (A "Hold-to-Inspect" option is available in the accessibility settings).

Passive Integration (Rewarding Mastery): The player shouldn't have to pause to understand the world once they learn it. As Insight increases, the universal color/shape language passively bleeds into the standard view (e.g., subtle auras, specific sound effects). An expert player won't need the Tactical Lens to know an enemy is poisoned; they will see the passive Neon Purple particle effect and act instantly in real-time.

The Gating Mechanism (Crucial): The UI queries the player's MindComponent.insight, a
Dictionary{StringName:int} (registry §2) — e.g. `mind.insight.get(target_tag, 0)`. There is no
`insight_level` field. It does not show raw data unless the player has earned it.

GATE DETAIL, NEVER PRESENCE (corrected 2026-07-31). The Lens is the designated teaching tool and
was gated behind the very insight a new player lacks — the least information at the moment of
least knowledge. The rule is now: **the Lens never hides THAT something is dangerous, only WHY.**
Insight 0 must still surface category and hazard. Additionally, run 1 seeds the Lineage Journal
with a "Field Primer" of 10-15 pre-unlocked entries for the tags encountered in hour one (water,
fire, cold, biomass, filth, iron) — diegetically the Residence's previous owner left notes. This
removes run-1 blindness without flattening the progression curve.

Insight 0 (Novice): Looking at a puddle. UI says: "Liquid — reacts to cold." (Hazard present,
cause withheld. NOT bare "Liquid".)

Insight 20 (Familiar): UI says: "Water + Unknown Substance."

Insight 50 (Master): UI says: "Water (80%), Venom (20%). Flammable."

Social & AI Insight: Looking at an NPC (e.g., a Goblin).

Insight 0: "Humanoid."

Insight 80: "Faction: Ug's Horde. Morale: Low. Current Objective: Fleeing (Fear)."

Actionable UI Alerts: If the UI detects an incoming [Hostile] entity due to a player mutation, the Tactical Lens highlights the guards in red before they enter combat range, giving the player time to react systemically.

3. Ergonomics (Minimizing Friction & Cognitive Load)

The player should never fight the interface. We must minimize mouse travel and utilize the keyboard effectively around the WASD cluster.

The Context-Sensitive 'E' (Action Intent Router): The player should not have to open a menu to decide how to interact with the world. The 'Interact' key dynamically constructs the ActionIntent based on the crosshair target's ECS tags.

Target has [Loot_Pile] tag? 'E' triggers ActionIntent_Take.

Target has [Crafting_Station] tag? 'E' opens CraftingUI.

Target has [Prof_Merchant] tag? 'E' triggers ActionIntent_Trade.

The Combat Radial (Slow-Mo Pivot): Pressing and holding 'Q' opens a contextual Radial Menu and
applies the same simulation `time_scale` multiplier (tick rate stays 60Hz — ADR-9). This allows the player to quickly select a spell or a quick-slot item using muscle memory (flick mouse up for heal, flick right for fireball) without moving their eyes off the center of the screen.

4. Mnemonic Design (Building Instinct)

The ECS is heavily tag-based. We must use a strict visual and auditory language so the player can "read" the simulation's state instantly without relying on text.

Universal Tag Color Coding: Every major chemical or state tag is hardcoded to a specific color palette that persists across the UI, VFX, and world lighting.

[Toxic/Venom] = #8A2BE2 (Neon Purple). Not green, to avoid confusion with healing herbs.

[Volatile/Explosive] = #FF4500 (Harsh Orange).

[Filth/Spoilage] = #556B2F (Sickly Olive).

Grimoire Shape Language (Syntax as Geometry): In the modular spell-crafting UI, Runes have distinct physical shapes that intuitively explain how they link.

Triggers (e.g., On_Cast) are Circles.

Shapes (e.g., Projectile) are Arrows/Chevrons.

Catalysts (e.g., Add_Temp) are Squares.

The player's brain mnemonically remembers that a spell must flow from Circle -> Chevron -> Square.

Acoustic Mnemonics (Material Identity): The UI and gameplay share a soundboard derived strictly from MaterialCompositionComponent.

Dropping an item, moving it in the inventory, or striking it with a sword plays an audio cue based on its highest percentage material. MAT_GLASS always chinks; MAT_BIOMASS always squelches. The player learns to identify hidden items or enemy armor types purely by sound.

5. Physical Inventory & Encumbrance

The inventory directly interfaces with the physical reality of the ECS (PhysicalPropertyComponent). There are no abstract "stacks of 99". However, the UI abstracts the management of this physical space to respect the player's time.

Slot-Based Body Plan: Head, Chest, Legs, Back, Belt (Quick Slots), Hands.

The Smart Backpack (Zero Tetris): The "Backpack" is an item equipped on the Back with a hard VolumeCapacity_cm3 limit. We never force the player to manually arrange items in a grid.

The Backpack UI is a dynamic, auto-sorting list driven by ECS tags.

It features robust toggles and selectors (e.g., "Filter by: Consumables", "Sort by: Heaviest", "Show: Crafting Materials").

As long as Total_Held_Volume < VolumeCapacity_cm3, the item fits. The computer handles the spatial math.

Mass Penalty: Total mass_kg held across all slots acts as a divisor against the player's movement speed ActionIntent.

Fluid Handling: Liquids (MAT_WATER, Venom) cannot exist bare in the inventory. If the player
tries to "pick up" a puddle, the UI asks the ECS for an empty item with ContainerComponent
that accepts liquids (like a flask). If none exists, the action fails.

6. The Grimoire (Spell Compilation UI)

This is the frontend for the SpellCompilerSystem defined in Sprint 4. Fucking around to learn a spell is gameplay; manually rebuilding it every time you need it is tedium.

The Node Grid: A visual node-based UI where the player drags Rune items they have discovered or translated to experiment with combinations.

Live Validation (Dry Run): As the player connects nodes, the UI sends a dry-run array to the ECS compiler, instantly displaying the calculated Strain_Cost (Stamina drain) or turning red if the spell breaks a hard cap (e.g., trying to make a radius > 15m).

The Blueprint Library (QoL): Once a player successfully compiles and registers a spell by clicking "Bind", they can save that specific node arrangement as a Blueprint.

Blueprints are stored in a side-panel.

A single click auto-populates the grid with the saved rune arrangement, bypassing the manual setup entirely for frequent use, allowing the player to quickly bind it to a Quick Slot.

7. The Rumor Mill (LLM Output Formatting)

Tier 3 LLM Agents output grand objectives and dialogue barks via the JSON payload. How does the player perceive this diegetically?

Diegetic Barks: When an NPC executes a Job_Chat (passing gossip), a standard 3D text bubble appears above their head.

The Semantic Translation Cipher: The text bubble is run through a cipher based on the player's MindComponent.language_fluency for that faction's specific culture tag.

Instead of visually scrambling text (which hurts accessibility), the cipher leverages the semantic structure of the sentence, replacing unknown words with their grammatical function.

Fluency Low: "The noun? hoard noun? while we verb?!"

Fluency High: "The Dwarves hoard bread while we starve!"

Bounty Boards: In the Surface Village, the LLM's GATHER_RESOURCES objectives are formatted into physical UI documents on the [Bounty_Board].

8. Integrated Corrections (ADR / Adversarial Review)

Redundant encoding (review G2): the "passive color/particle bleed" that lets experts read the
sim without the Tactical Lens must NOT rely on hue alone. Each tag pairs a color with a
distinct shape/motion/particle signature (and the Grimoire's shape language). Acoustic cues
are additive, never sole. This keeps colorblind and deaf/HoH players on equal footing.

Picking & spatial queries (ADR-2): the Tactical Lens "mouse over an entity to read it" and the
context-sensitive 'E' router resolve their target via the ECS PickSystem (pure-math camera ray
through the SpatialHash + tile_map). No Godot physics raycasts / Area3D (Prime Directive).
NavigationServer3D is only an Active-chunk steering accelerator (sanctioned exception).

Translation Cipher (accessibility, review G1): the cipher uses SEMANTIC replacement (unknown
words shown as their grammatical function, e.g. "noun?"/"verb?"), never letter/symbol
scrambling. An accessibility toggle shows raw text. (The old scrambling design is void; see
ui_ux_qol_review.md for history.)

Inspect input (review, RSI): the Tactical Lens defaults to TOGGLE; a Hold option exists in
accessibility settings.
