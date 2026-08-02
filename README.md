The Living Delve - Master Architecture Index

HOW TO RUN AND TEST IT: see RUNNING.md. It covers the exact commands, the controls, what every
object in the test arena exists to test, how to read the debug overlay, and how to capture
rendered frames without a display session. Read it before reading any architecture document.

ATTENTION AI AGENTS: If you are reading this, you are operating within a strict Entity Component System (ECS) architecture. Do not write a single line of Godot code until you have read CLAUDE.md in the root directory and parsed the relevant documentation below.

0. Decisions & Review (Read Before Everything)

These two documents are authoritative and override any older spec they contradict.

docs/architecture_decisions.md - The Architecture Decision Record (ADR). Canonical cross-cutting decisions (physics model, world model, ticks, LLM, save, performance, identity). WINS over any conflicting spec.

docs/component_and_field_registry.md - The canonical component/field/enum/tag registry. Every
component, field, enum value, and tag name in any doc or any line of code must match it.
WINS over any conflicting spec on naming and typing.

The three docs/ADVERSARIAL_REVIEW*.md files are HISTORICAL, NON-BINDING repair logs. Read them
for the "why" behind a decision. They never override the ADR or the registry, and nothing in
them is an open blocker unless STATE.md explicitly says so.

1. Core Architecture (Read First)

Before starting any Sprint, you must understand the rules of this universe. The engine is just a dumb viewer.

docs/ecs_architecture_and_data_layer_specification.md - The foundational rulebook for the pure-data ECS.

docs/component_and_field_registry.md - Canonical component/field/enum/tag registry. Every sprint and system doc must match it (ADR-13).

docs/persistence_and_save_architecture.md - The first-class Save & Quit / Lineage / schema-version persistence contract (ADR-6). Required before Sprint 3 depends on death-loop persistence.

docs/game_vision_and_architecture_the_living_delve.md - The overarching game design document.

docs/invariants_and_test_strategy.md - Cross-system invariants and required test gates. Use
this to decide whether a sprint is actually correct, not merely implemented.

docs/debugging_and_observability_architecture.md - Debug overlays, event tracing, counters,
and "why did this NPC do that?" inspection surfaces for tuning the systemic simulation.

docs/content_authoring_and_schema_validation.md - Data/content schema, ID, migration, and
validation contract for materials, creatures, runes, reactions, cultures, job templates, and
LLM prompts.

docs/archetypal_content_catalog.md - Pure-content seed catalog of reusable systemic object
families (fixtures, containers, documents, hazards, route markers, social tokens) that should
be authored once schemas exist.

2. System Specifications (The Rules of Reality)

These documents dictate the math, physics, and AI behavior of the world.

docs/material_crafting_and_economy_architecture.md - Matter, Chemistry, Thermodynamics, and Crafting.

docs/entity_behavior_and_society_architecture.md - Tier 2 NPC Schedules, Needs, and Utility AI.

docs/factions_and_social_mechanics_architecture.md - Diplomacy, Mutiny, and Faction Warfare.

docs/magic_and_skill_progression_architecture.md - The Modular Node-Based Spell Compiler.

docs/llm_reasoner_and_planning_architecture.md - The Tier 3 LLM Asynchronous Integration.

docs/meta_progression_and_death_loop_architecture.md - The Death Loop, Interregnum, and Lineage.

docs/dag_history_generation_architecture.md - The Procedural History Graph.

docs/world_and_floor_generation_architecture.md - Biomes, Zones, and Level Generation.

docs/world_bootstrapping_and_the_overworld_architecture.md - Day 0 Initialization and Pre-Warm.

docs/the_first_hour_day_0_gameplay_and_transition.md - The expected first hour of ECS interaction.

3. UI/UX Architecture (The Viewport)

These documents dictate how the player interfaces with the ECS.

docs/ui_ux_architecture_and_player_interactivity.md - The Tactical Lens, Developer God-Mode, and player-input-to-ECS-intent translation.

docs/hud_and_main_interface_architecture.md - Resolution scaling, the Log Aggregator, and Focus management.

docs/inventory_and_grimoire_mechanics_specification.md - Physical inventory ruptures, acoustic padding, and magic UI validation.

docs/ui_ux_qol_review.md - Resolved UI/UX feedback log (historical; see notes inside).

4. The Implementation Sprints (Your Tasks)

When tasked with a Sprint, review its Roadmap and Technical Scaffolding.
Files: docs/sprint_<N>_implementation_roadmap.md and docs/sprint_<N>_technical_scaffolding.md.

Sprint 0: CI/CD, Folder Structure, Testing Framework.

Sprint 1: The Core Vertical Slice (Micro Tick, ECS Physics/Collision, Spatial Index, LoD Handshake).

Sprint 2: The World Canvas (DAG Generation, Macro-Tick, Chunk Streaming).

Sprint P / Sprint 2.5: Persistence Contract (versioned save/load, RNG stream state, WorldGrid/DAG/component serialization). `docs/persistence_and_save_architecture.md` is the complete roadmap/scaffold for this workstream unless it is later split into dedicated sprint files.

Sprint 3: The Brains & Bloodline (LLM Bridge, Interregnum Fast-Forward).

Sprint 4: The Crucible (Chemistry Reactions, Spell Compilation, Mutation).

Sprint 5: Content & Data (JSON Schemas, Dictionaries).

Sprint 6: LLM Prompt Fine-Tuning.

Sprint U (Interface & Accessibility): HUD edit mode, GridFocusManager, escape stack, radial
menu, keybind remapping, colorblind filters, font scaling, shake toggle, cipher toggle.

UNOWNED SPECIFICATION — VERIFIED GAPS (2026-07-31 gestalt review)

A grep of every `docs/sprint_*.md` file returns ZERO hits for `scarcity`, `price`, `barter`,
`merchant`, `recipe`, `forge`, `EconomySystem`, `ClimateSystem`, and `weather`, and no hits for
`HUD`, `paper doll`, `quick-belt`, `radial`, or `focus manager` outside Sprint 0's folder tree.
The following specified systems currently have NO implementing sprint. They are not cancelled;
they are unscheduled, which is how they ambush a project later:

- **The entire economy.** Scarcity_Index, the price formula, barter resolution, coin
  change-making, merchant Trade_State, crafting stations, forges, alloys, recipes.
  `material_crafting_and_economy_architecture.md` §5 and the Day-0 walkthrough (which is
  literally a shopping trip) both depend on it. Proposed slot: **Sprint 2.75 "The Market."**
- **Faction politics.** Loyalty, schism/mutiny, succession by prestige, ClaimTags, caravans,
  grievance accumulation, war-time job generation, Job_Chat gossip propagation, profession
  assignment. Sprint 3 only mentions these as triggers for ADR-12 cap enforcement. Without
  them Sprint 3 ships an LLM that emits RAID_FACTION into a world with no soldiers, no
  loyalty, and no succession. Proposed slot: **Sprint 3.5 "The Body Politic."**
- **Climate/weather** (ClimateSystem), the **Bounty Board**, **encumbrance**, **smart
  sub-containers**, and **muscle-memory skill growth**.
- **All player-facing UI.** ~420 lines across the three UI specs. See Sprint U above and the
  per-sprint allocation in `docs/scope_and_milestones.md`.

Note: The Persistence/Serialization workstream (see ADR-6 and docs/persistence_and_save_architecture.md) is a first-class deliverable and should land before Sprint 3's death-loop implementation depends on it.

Every sprint must preserve docs/invariants_and_test_strategy.md and expose the debug surfaces
specified in docs/debugging_and_observability_architecture.md as its systems come online.
Content/data work must validate against docs/content_authoring_and_schema_validation.md.

5. Tooling & Conventions (Pinned)

Godot Engine: 4.7.1 (canonical). Pinned in three places that MUST stay in sync:
project.godot (config/features "4.7"), .github/workflows/godot_ci.yml
(barichello/godot-ci:4.7.1), and this README. Do not upgrade without updating all three.

Linter: gdtoolkit (gdlint/gdformat), pinned in CI. Lints first-party dirs only; never addons/.

Testing: GUT (Godot Unit Test) in addons/gut, installed via script/submodule (Sprint 0).

CLAUDE.md is the root canonical agent instruction file. copilot-instructions.md is a symlink
to CLAUDE.md. NOTE: symlinks may not resolve on Windows checkouts / some CI runners;
contributors on Windows should read CLAUDE.md directly.

build_repo.py was a ONE-SHOT bootstrap generator and is now retired — do NOT re-run it (it
would overwrite hand-edited files such as the CI workflow and project.godot). Kept only for
historical reference.
