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
│   ├── data_models/              # JSON Schemas and Enum definitions
│   └── persistence/              # Save/load schema + migration logic (Sprint P / ADR-6)
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
├── CLAUDE.md                     # Root canonical agent System Prompt & Rules
├── .claude/
│   └── CLAUDE.md                 # Optional tool-specific mirror of root CLAUDE.md
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
GameLoopManager="*res://singletons/GameLoopManager.gd"
[physics]
common/physics_ticks_per_second=60 ; The engine heartbeat for the Micro Tick



5. The Agent Instruction File (CLAUDE.md)

Place the canonical file at the repository root as `CLAUDE.md`. Tool-specific mirrors such as
`.claude/CLAUDE.md` and `copilot-instructions.md` must either point to that file or be kept
byte-for-byte equivalent so onboarding instructions never dangle.

Do not duplicate the body of `CLAUDE.md` in this scaffold. The root file is the single
source of truth; if it changes, update mirrors/symlinks rather than copying stale prompt text
into sprint docs.
