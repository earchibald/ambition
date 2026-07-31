Implementation Roadmap: Sprint 0 (Foundation & Workflow)

Target Audience: Lead Coding Agent / DevOps
Objective: Establish the Godot 4 project, the strict directory architecture, the testing framework, and the CI/CD pipeline. This sprint ensures that all future code adheres to the "Godot is a Dumb Viewer" philosophy through automated checks, rigid structural boundaries, and explicit AI prompting.

Step 1: Repository Initialization & Git SDLC

The Objective: Create a clean, version-controlled environment with a strict branching strategy to protect stable builds.
Required Implementation:

Initialize the Git repository with a Godot-specific .gitignore (ignoring .godot/, exports, and .import bloat).

CRITICAL: Create the Godot 4 project properly using the CLI (godot --headless --editor --quit) before modifying config files. Do not just fabricate a raw text file.

CRITICAL - Branching Strategy: Establish three tiers of branches:

main: The holy grail. Must ALWAYS compile and run flawlessly.

dev: The integration branch. May contain bugs or incomplete features.

feature/[sprint_name]: Working branches for the AI agent. Always branch off dev.

Physics Tick Lock: In project.godot, hardcode physics_ticks_per_second to 60. This serves as the unyielding metronome for the ECS Micro Tick.

Step 2: Directory Architecture Enforcement

The Objective: Physically separate the ECS (Pure Data) from the Viewer (Godot Nodes).
Required Implementation:

Construct the folder tree outlined in sprint_0_technical_scaffolding.md.

Establish res://ecs/ (Strictly RefCounted data and math processors).

Establish res://viewer/ (Strictly Node3D, MeshInstance3D, and UI).

Step 3: The Autoload (Singleton) Initialization

The Objective: Establish the global managers that drive the game loop and event bus.
Required Implementation:

Create GameLoopManager, ECSManager, and ECSEvents.

Ensure load order prioritizes data (ECSEvents -> ECSManager -> GameLoopManager).

CRITICAL: These must be pure .gd scripts added as Autoloads. Do NOT create .tscn (scene) files for these singletons, as headless CI runners can crash loading unnecessary spatial dependencies.

Step 4: Quality Assurance (Unit Testing & Linting)

The Objective: Ensure logic is tested and formatting is standard.
Required Implementation:

Install GUT (Godot Unit Test). Use a bash script (curl or wget) to pull the GUT addon repository directly into res://addons/gut, or add it as a git submodule.

CRITICAL: All test files MUST be prefixed with test_ (e.g., test_ecs_entity_creation.gd). If they are not, GUT will ignore them, resulting in a false-positive CI pass.

Install gdtoolkit via pip to enforce gdlint standards.

Step 5: Continuous Integration (GitHub Actions)

The Objective: Automate the policing of the codebase.
Required Implementation:

Implement a GitHub Actions workflow (.github/workflows/godot_ci.yml).

CRITICAL: The workflow must run godot --headless --editor --quit ONCE before running tests to build the .godot/ import cache, otherwise the test step will hang indefinitely.

CRITICAL: The checkout step MUST include submodules: recursive in case GUT was installed via submodule.

Step 6: AI Agent Onboarding & System Prompts

The Objective: Guarantee that any LLM/Coding Agent operating within this repository understands the boundaries.
Required Implementation:

Create CLAUDE.md in the root directory using the exact scaffolding provided.

Implement the rigid STATE.md protocol to prevent context-window bloat during handoffs.

Explicitly forbid the agent from auto-merging its own Pull Requests.
