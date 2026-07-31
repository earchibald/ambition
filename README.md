The Living Delve - Master Architecture Index

ATTENTION AI AGENTS: If you are reading this, you are operating within a strict Entity Component System (ECS) architecture. Do not write a single line of Godot code until you have read CLAUDE.md (or .cursorrules) in the root directory and parsed the relevant documentation below.

0. Decisions & Review (Read Before Everything)

These two documents are authoritative and override any older spec they contradict.

docs/architecture_decisions.md - The Architecture Decision Record (ADR). Canonical cross-cutting decisions (physics model, world model, ticks, LLM, save, performance, identity). WINS over any conflicting spec.

docs/ADVERSARIAL_REVIEW.md - The end-to-end adversarial review that produced those decisions. Read for the "why" and for the list of still-open engineering fixes.

1. Core Architecture (Read First)

Before starting any Sprint, you must understand the rules of this universe. The engine is just a dumb viewer.

docs/ecs_architecture_and_data_layer_specification.md - The foundational rulebook for the pure-data ECS.

docs/game_vision_and_architecture_the_living_delve.md - The overarching game design document.

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

Sprint 3: The Brains & Bloodline (LLM Bridge, Interregnum Fast-Forward).

Sprint 4: The Crucible (Chemistry Reactions, Spell Compilation, Mutation).

Sprint 5: Content & Data (JSON Schemas, Dictionaries).

Sprint 6: LLM Prompt Fine-Tuning.

Note: A dedicated Persistence/Serialization workstream (see ADR-6) is required and is not yet slotted into a numbered sprint; treat it as a first-class deliverable.
