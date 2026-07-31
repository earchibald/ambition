Sprint 0 Technical Scaffolding

Target Audience: Lead Coding Agent / DevOps
Context: The concrete files, folder trees, and CI/CD YAML configurations required to execute sprint_0_implementation_roadmap.md.

AUTHORITATIVE NOTE (ADR): The canonical CI workflow is the committed
.github/workflows/godot_ci.yml — NOT the YAML reproduced below, which is illustrative and
has intentionally diverged (the real file scopes gdlint to first-party dirs, pins
gdtoolkit, adds a guarded boot smoke test, and guards steps for the pre-bootstrap state).
When they differ, the committed file wins. Also per ADR-3, chunk_id is Vector3i(x,y,floor)
everywhere. A first-class Persistence/Serialization deliverable (ADR-6) must be added to
the folder plan: reserve ecs/persistence/ for the save system.

1. Strict Directory Architecture

The coding agent MUST adhere to this exact folder structure to maintain the ECS boundary.

res://
├── .github/
│   └── workflows/
│       └── godot_ci.yml          # Automated testing
├── ecs/                          # PURE DATA (No Godot Canvas/Physics Nodes)
│   ├── components/               # RefCounted Data Structs (e.g., PositionComponent.gd)
│   ├── systems/                  # Logic loops (e.g., FluidDynamicsSystem.gd)
│   └── data_models/              # JSON Schemas and Enum definitions
├── viewer/                       # GODOT NODES (The Dumb Viewer)
│   ├── actors/                   # MeshInstance3D scenes for entities
│   ├── environment/              # Voxel/GridMesh rendering for chunks
│   └── vfx/                      # Particle systems
├── ui/                           # HUD and Menus
│   ├── tactical_lens/
│   └── grimoire/
├── singletons/                   # Autoloads (MUST INHERIT FROM NODE)
│   ├── ECSEvents.gd
│   ├── ECSManager.gd
│   └── GameLoopManager.gd
├── tests/                        # GUT (Godot Unit Test) scripts
├── addons/                       
│   └── gut/                      # Must be installed via script/submodule, not UI
├── assets/                       # Raw textures, audio, fonts
├── CLAUDE.md                     # Agent System Prompt & Rules
└── STATE.md                      # The Agent Handoff / Memory File



2. GitHub Actions CI Pipeline (Anti-Hang Patch)

This file guarantees that broken simulation logic never merges. It includes the mandatory pre-import step to prevent Godot 4 headless hanging.

# .github/workflows/godot_ci.yml
name: Godot ECS CI Pipeline

on:
  pull_request:
    branches: [ "dev", "main" ]
  push:
    branches: [ "main" ]

jobs:
  test_and_lint:
    runs-on: ubuntu-latest
    container:
      image: barichello/godot-ci:4.7.1 # ADR-15 (illustrative; the committed workflow is canonical)
    
    steps:
      - name: Checkout Code
        uses: actions/checkout@v3

      - name: GDScript Linter
        run: |
          pip3 install "gdtoolkit==4.3.*"   # pinned
          # Lint first-party dirs ONLY; never addons/ (third-party GUT is not gdlint-clean).
          gdlint ecs singletons ui viewer tests

      - name: Pre-Import Assets (CRITICAL ANTI-HANG FIX)
        run: |
          # Forces Godot to build the .godot/ folder headlessly so GUT doesn't time out
          godot --headless --editor --quit

      - name: Run ECS Unit Tests (Headless)
        run: |
          # Run GUT tests. Fail the pipeline if any ECS math fails.
          godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gexit



3. The PR Template

.github/pull_request_template.md.

## Description of Changes
[Briefly describe what this PR adds or fixes.]

## Architectural Checklist (MANDATORY)
- [ ] I did NOT use `CharacterBody3D`, `RigidBody3D`, or `move_and_slide()` for game logic.
- [ ] If I added a new System, I explicitly registered it to the `Micro`, `Simulation`, or `Macro` tick in `GameLoopManager`.
- [ ] UI components added in this PR only *listen* to `ECSEvents` and do not modify ECS data directly.
- [ ] I wrote a unit test in `res://tests/` for any new math calculations.
- [ ] I updated `STATE.md` using the exact required format.



4. Initialization (project.godot snippets)

[autoload]

; Order is critical. Events must exist before Manager. Manager before Loop.
ECSEvents="*res://singletons/ECSEvents.gd"
ECSManager="*res://singletons/ECSManager.gd"
GameLoopManager="*res://singletons/GameLoopManager.gd
"
[physics]
common/physics_ticks_per_second=60 ; The engine heartbeat for the Micro Tick



5. The Agent Instruction File (CLAUDE.md)

Place this file at the root.

# Agent Instructions: "The Living Delve"

## Your Role
You are the Lead Systems Coding Agent. You are tasked with implementing a massive, systemic dungeon crawler in Godot 4 using a custom, data-oriented architecture.

## 1. Git Workflow & SDL (MANDATORY).
*   **`main`**: The Stable Release. **NEVER push directly to `main`.**
*   **`dev`**: The Integration Branch. All features merge here first. It may contain bugs, but it must compile.
*   **`feature/*` or `fix/*`**: Your working branches. Always create a new branch off `dev` before writing code (e.g., `git checkout -b feature/sprint1-ecs-core`).
*   **Pull Requests:** When a feature is done, create a PR targeting the `dev` branch. CI tests will run. Once `dev` is stable and a milestone is reached, we will merge `dev` into `main`.

## 2. State Tracking (The Handoff Protocol)
You are part of an ephemeral swarm. Your session may end at any time, and another agent will take your place. To prevent context loss, you MUST maintain a file named `STATE.md` in the root directory.
*   Before ending any response, opening a PR, or switching tasks, update `STATE.md` with:
    *   **Current Branch:** (e.g., `feature/sprint1-movement`)
    *   **Active Goal:** What we are trying to achieve right now.
    *   **Last Completed:** The specific file/logic just finished.
    *   **Known Blockers/Bugs:** What is currently broken.
    *   **Next Immediate Steps:** The exact next thing the incoming agent should do.

## 3. The Prime Directive: Godot is a Dumb Viewer
1. **NEVER use Godot Physics Nodes for logic.** Do not use `CharacterBody3D`, `RigidBody3D`, `Area3D`, or `move_and_slide()`.
2. **The ECS is the Source of Truth.** All entity logic, positions, and chemistry live in `res://ecs/` as pure data (`RefCounted` or `Resource` objects).
3. **Strict Decoupling.** Visual nodes (`res://viewer/`) are only spawned to represent ECS data visually. They interpolate to the ECS `PositionComponent` values. The UI only ever listens to `ECSEvents` signals; it never modifies state directly.
4. **Data Arrays over Nodes:** Whenever possible, use `PackedFloat32Array` or typed arrays for massive loops (like Cellular Automata or Micro Tick updates) instead of nested Dictionaries.

## 4. Your Immediate Tasks (Before Writing Code)
Before you implement a single system, you must understand the gestalt of the architecture. You have access to a suite of documents (Sprints 0-4 Roadmaps and Scaffolding).

**Task 1: Full Architecture Review**
Read all architectural specifications and provide a critical review of the overall project structure. Identify any remaining paradoxes or missing data pipelines in the ECS-to-Viewer handshake.

**Task 2: Sprint-by-Sprint Review**
Provide a step-by-step technical critique of Sprints 1, 2, 3, and 4. Tell me exactly what files you intend to create first for Sprint 1, how you will structure the `ECSManager`, and flag any constraints you feel are missing.

Do not write implementation code until we have completed this review dialogue.


