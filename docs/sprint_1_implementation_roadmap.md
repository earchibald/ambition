Implementation Roadmap: Sprint 1 (The Core Vertical Slice)

Target Audience: Lead Coding Agent
Objective: Build a self-contained, purely systemic prototype proving the ECS engine, basic thermodynamics, the Godot Viewer integration, and a single Tier 2 AI loop. No LLMs or macro-generation yet.

CRITICAL ARCHITECTURAL DIRECTIVE: The Physics Trap

DO NOT use Godot's built-in physics nodes (CharacterBody3D, RigidBody3D, move_and_slide()) for game logic. The ECS is the absolute source of truth. Godot is a "Dumb Viewer." Visual nodes must be standard Node3D or MeshInstance3D objects whose global_position is explicitly set by reading the ECS PositionComponent during Godot's _process frame.

ADR ADDITIONS TO SPRINT 1 (see architecture_decisions.md + sprint_1_technical_scaffolding.md
Sections 8-10): Sprint 1 also delivers (a) a minimal GameClock (schedules need time-of-day),
(b) the ECS-owned SpatialHash + CollisionResolveSystem + PickSystem that replace
move_and_slide/Area3D/physics-raycasts for movement, collision, melee targeting, interaction,
and Tactical-Lens picking (NavigationServer3D is a sanctioned Active-only steering exception),
and (c) generational entity handles with atomic destroy across all registries. Sprint 1 also
introduces the PerceptionSystem primitive (sight cone + DDA LoS, hearing/noise ephemerals,
witness events) so combat, stealth, and crime are not omniscient. Combat uses the defined
strength/density/force model, not undefined stats.

MANDATORY BUILD ORDER (added 2026-07-31). The numbered Steps below describe WHAT Sprint 1
delivers. They are NOT the order to build it in. The Step order puts fluids and collision before
the grid they run on, and appends SpatialHash as an appendix (§9) although Steps 3, 4, 5, and 6
all depend on it. Build in these five stages, with a human gate after each of the first four.
Everything in the Steps still ships; only the sequence changes.

Stage 0 — Skeleton (no gameplay; ADR-7 requires this precede code)
  EntityHandle (ADR-19 packed int) + free-index list; ECSManager canonical registries + atomic
  destroy; the query(mask) -> row-indices facade (ADR-19); RNGService streams; ECSEvents signal
  contract; GameLoopManager three-tick driver; GameClock.

Stage 1 — Hands on keyboard
  PositionComponent + velocity integrator; ChunkData + a hand-authored test room (no worldgen);
  SpatialHashSystem; CollisionResolveSystem; ViewManager + camera rig; InputMap + ActionIntent ->
  action_queue -> velocity; PickSystem.
  GATE A: a human walks the room and points at things. Fix the interpolation constant, corner
  catching, and input latency NOW. Hand-rolled character collision fails in feel-only ways
  (corner catch, stair pop, wall jitter, latency) that NO test detects and ten seconds of play
  does. Write play note #1.

Stage 2 — Things to do to the room
  PhysicalProperty + MaterialComposition + derived mass; Inventory/Container with volume+mass and
  the speed divisor; loose-item integrator with sleep-on-rest; BodyComponent +
  ActionResolutionSystem melee (§10 energy model); corpse conversion; EphemeralComponent
  primitive (the shared noise/aura/magic TTL primitive).
  GATE B: pick up, drop, get slowed, swing, kill. This tests the single riskiest unvalidated bet
  in the whole design — "combat is just physics" — while it is still cheap to change. Play note #2.

Stage 3 — The world reacts
  ChemistryComponent tags; thermodynamics (heat capacity, conduction, phase thresholds);
  FluidDynamicsSystem CA (§5 corrected algorithm); spoilage -> Filth.
  GATE C: pour water, freeze it, slip on it, bleed into it.

Stage 4 — Something else is alive
  NeedsComponent + MetabolismSystem; ScheduleComponent reading GameClock; PerceptionSystem
  (§11); WitnessEvent/MemoryEvent write path; JobComponent + claim lifecycle + utility evaluator
  with the job latch; NavBridge async queue over grid A*.
  GATE D: an NPC lives a day, hears you, investigates, eats. Play note #3.

Stage 5 — Observability, built ALONGSIDE Stages 1 and 4, never afterwards
  Tick/perf strip; ECS entity inspector (selected via PickSystem, which dogfoods the pick path);
  perception overlay; fluid/tag overlay; raw event log; free camera + spawn console; the
  --scenario debug boot path (<= 2 s to controllable); the ADR-20 soak harness; tests/perf/
  benchmark printing real ms per system at N in {50, 500, 1500}.
  Without a spawn console you cannot reproduce a single success state below on demand.

Step 1: The Tick Driver & ECS Data Structure

The Objective: Establish the decoupled data layer and the Master Clock. The game must run in pure data without Godot rendering a single pixel.
Required Implementation:

Implement the GameLoopManager to drive the ECS ticks safely from Godot's engine.

Initialize the Component Registries (structs/data classes).

Add the first observability counters from docs/debugging_and_observability_architecture.md:
tick durations, component counts, alive handle count, and per-system entity counts. These are
debug/read-only surfaces, not gameplay logic.
Scaffolding Validation:

Reference: sprint_1_technical_scaffolding.md (Section 1).
Success State: The console prints an entity's hunger increasing on the 2Hz Simulation Tick while its position updates 60 times a second on the Micro Tick.

Step 2: The Physical Reality (Matter & Chemistry)

The Objective: Define "Stuff" and how it reacts. Prove the tag-based chemistry engine.
Required Implementation:

Implement MaterialCompositionComponent and ChemistryComponent.

Build the FluidDynamicsSystem (Cellular Automata on grid, utilizing the Flood Buffer logic).
Scaffolding Validation:

Reference: material_crafting_and_economy_architecture.md (Sections 1, 2 & 3).
Success State: You can spawn a puddle of MAT_WATER in code, set the chunk's
ambient_temperature_c to -5.0, and observe PhysicalPropertyComponent.phase become
ECSEnums.Phase.SOLID while &"Slippery" is added to ChemistryComponent.active_tags.
(Phase is an enum, never a tag string — ADR-13 / registry §3.)

Step 3: The Godot "Viewer" (LoD Handshake)

The Objective: Make the Godot Engine listen to the ECS and render only what is necessary.
Required Implementation:

Implement LoDComponent (Active, Simulated, Abstracted).

Build the ViewManager Event Bus listener to instantiate/pool visual Nodes.
Scaffolding Validation:

Reference: ecs_architecture_and_data_layer_specification.md (Section 3) & sprint_1_technical_scaffolding.md (Section 2).
Success State: An entity moves across a chunk border in the ECS. Godot dynamically spawns a visual cube for it, and despawns it when it moves too far away.

Step 4: Input & Action Intent (Entity 0)

The Objective: Bridge Godot's hardware input to the ECS pure-data processing.
Required Implementation:

Build a Godot script that reads Input.get_vector() and translates it into an ActionIntent struct, pushing it to Entity 0's ActionQueue.

Build InventoryComponent adhering strictly to Volume and Mass limits.
Scaffolding Validation:

Reference: sprint_1_technical_scaffolding.md (Section 4).
Success State: Pressing "W" does not move the player directly. It pushes a movement ActionIntent to the ECS. The ECS updates the position. The Godot camera follows the new position. Total mass from inventory directly scales the velocity float applied to the position.

Step 5: The First NPC & Basic Routine (The AI Loop)

The Objective: Prove that NPCs are biological agents driven by needs.
Required Implementation:

Implement ScheduleComponent and MetabolismSystem.

Implement the static Utility AI Evaluator.
Scaffolding Validation:

Reference: sprint_1_technical_scaffolding.md (Sections 7-8).
Success State: The NPC hauls rocks. When hunger > 80, it interrupts its Routine to execute ActionIntent_Consume on a MAT_BIOMASS entity.

Step 6: Action Resolution (Combat & Kinetics)

The Objective: Prove that combat is just physics.
Required Implementation:

Build the ActionResolutionSystem for melee kinetic transfer.

Implement Spoilage timers turning MAT_BIOMASS into Filth.
Scaffolding Validation:

Reference: the_first_hour_day_0_gameplay_and_transition.md (Phase 4: Combat Resolution).
Success State: The player swings an Iron Sword at a Rat. The ECS calculates: Player_Velocity * (Weapon_Mass + BodyComponent.strength). The rat's health hits 0, it becomes a [Corpse] item, bleeds, and the blood spreads via Cellular Automata.
