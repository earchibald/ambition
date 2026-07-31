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



2. GitHub Actions CI Pipeline — REQUIREMENTS (not a copyable YAML body)

The canonical workflow is the committed `.github/workflows/godot_ci.yml`. The illustrative YAML
that used to live here was deleted: it had diverged from the committed file and invited
copy-paste of steps that are now known to be broken.

The following requirements were VERIFIED EMPIRICALLY against `barichello/godot-ci:4.7.1` and
Godot 4.7.1. Each exists because the naive version silently passes while doing nothing.

**R1 — The lint step must install pip itself, and must pass `--break-system-packages`.**
The image contains NO `python3` and NO `pip3`. Its base is Ubuntu 24.04, which ships
`/usr/lib/python3.12/EXTERNALLY-MANAGED`, so a bare `pip3 install` fails with
`error: externally-managed-environment` (PEP 668). Verified both the failure and the fix.

**R2 — Pin gdtoolkit to the version actually verified against the pinned engine.**
Use `gdtoolkit==4.5.*` (gdlint 4.5.0). The old `4.3.*` pin predates Godot 4.5+ syntax and
fails to parse `@abstract` with a parse error rather than a lint error.

**R3 — The "does this dir have .gd files" guard must not use `**`.**
`ls "$d"/**/*.gd` does NOT work: bash `globstar` is off in Actions, so `**` degrades to `*`,
and `ls` with any non-matching pattern returns non-zero, short-circuiting the `&&`. Verified:
gdlint was skipped for `ecs` and `singletons` even though both contained `.gd` files.
Use `[ -n "$(find "$d" -name '*.gd' -print -quit)" ]`.

**R4 — Import before anything that needs `class_name`.**
Verified: `class_name` globals and cross-file enums do NOT resolve until the project has been
imported; `--script` on a fresh checkout dies with `Identifier "X" not declared`. Use
`godot --headless --import`.

**R5 — GUT must be proven to have actually run tests.**
GUT exits 0 while running ZERO tests via three separate paths: missing import, an empty test
dir, and `-gdir` not recursing into subdirectories. All three verified. Therefore the CI must
pass `-ginclude_subdirs`, emit `-gjunit_xml_file`, and then FAIL the job if the parsed test
count is 0. A guard of "does gut_cmdln.gd exist" is not sufficient.

**R6 — The boot smoke test must assert a sentinel.**
Verified: a `Main.tscn` whose `_ready()` throws a hard runtime error still exits 0. The smoke
step must grep the log for a `ECS_BOOT_OK` sentinel printed at the end of `Main._ready()`, and
must fail on `SCRIPT ERROR` / `^ERROR:` in the output.

**R7 — Pin the GUT version.** Use the tag `v9.7.1`, verified green on Godot 4.7.1.



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
; All three MUST `extends Node` — Godot refuses to autoload a script that does not.
ECSEvents="*res://singletons/ECSEvents.gd"
ECSManager="*res://singletons/ECSManager.gd"
GameLoopManager="*res://singletons/GameLoopManager.gd"
[physics]
common/physics_ticks_per_second=60 ; The engine heartbeat for the Micro Tick

[input]
; REQUIRED IN SPRINT 0. Sprint 1 Step 4 mandates Input.get_vector(), which pushes an error
; every frame if these actions are unmapped. The Sprint 0 gate asserts InputMap.has_action()
; for each of these names.
;   move_left / move_right / move_forward / move_back  -> A / D / W / S
;   interact -> E      attack -> Mouse Left      inspect -> Tab
;   cancel   -> Escape



5. The Agent Instruction File (CLAUDE.md)

Place the canonical file at the repository root as `CLAUDE.md`. Tool-specific mirrors such as
`.claude/CLAUDE.md` and `copilot-instructions.md` must either point to that file or be kept
byte-for-byte equivalent so onboarding instructions never dangle.

Do not duplicate the body of `CLAUDE.md` in this scaffold. The root file is the single
source of truth; if it changes, update mirrors/symlinks rather than copying stale prompt text
into sprint docs.
