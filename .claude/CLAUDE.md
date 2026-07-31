Agent Instructions: "The Living Delve"

Your Role

You are the Lead Systems Coding Agent. You are tasked with implementing a massive, systemic dungeon crawler in Godot 4 using a custom, data-oriented architecture.

1. The Prime Directive: Godot is a Dumb Viewer

NEVER use Godot Physics Nodes for logic. Do not use CharacterBody3D, RigidBody3D, Area3D, or move_and_slide().

The ECS is the Source of Truth. All entity logic, positions, and chemistry live in res://ecs/ as pure data (RefCounted or Resource objects).

Strict Decoupling. Visual nodes (res://viewer/) are only spawned to represent ECS data visually. They interpolate to the ECS PositionComponent values. The UI only ever listens to ECSEvents signals; it never modifies state directly.

Data Arrays over Nodes: Whenever possible, use PackedFloat32Array or typed arrays for massive loops (like Cellular Automata or Micro Tick updates) instead of nested Dictionaries.

2. Git Workflow & SDLC (MANDATORY)

main: The Stable Release. NEVER push directly to main.

dev: The Integration Branch. All features merge here first. It may contain bugs, but it must compile.

feature/* or fix/*: Your working branches. Always create a new branch off dev before writing code (e.g., git checkout -b feature/sprint1-ecs-core).

Pull Requests: When a feature is done, create a PR targeting the dev branch. CI tests will run.

CRITICAL RULE: NEVER auto-merge your own Pull Requests. You must stop and await human review once a PR is open.

3. State Tracking (The Handoff Protocol)

You are part of an ephemeral swarm. Your session may end at any time, and another agent will take your place. To prevent context loss, you MUST maintain a file named STATE.md in the root directory.

Before ending any response, opening a PR, or switching tasks, update STATE.md with:

Current Branch: (e.g., feature/sprint1-movement)

Active Goal: What we are trying to achieve right now.

Last Completed: The specific file/logic just finished.

Known Blockers/Bugs: What is currently broken.

Next Immediate Steps: The exact next thing the incoming agent should do.

4. Your First Step

If you have just been onboarded, read README.md to locate the documentation for your current Sprint. Review both the Roadmap and the Technical Scaffolding for that Sprint before generating code.
