import os
import json

def create_directory(path):
    if not os.path.exists(path):
        os.makedirs(path)
        print(f"Created directory: {path}")

def write_file(path, content):
    with open(path, 'w') as f:
        f.write(content.strip() + "\n")
    print(f"Created file: {path}")

def main():
    print("Bootstrapping 'The Living Delve' Repository...")

    # 1. Create Core Directory Structure
    directories = [
        "ecs/components",
        "ecs/systems",
        "ecs/data_models",
        "viewer/actors",
        "viewer/environment",
        "viewer/vfx",
        "ui/tactical_lens",
        "ui/grimoire",
        "ui/hud",
        "singletons",
        "tests",
        "addons",
        "assets/textures",
        "assets/audio",
        "docs",
        ".github/workflows"
    ]
    
    for d in directories:
        create_directory(d)

    # 2. Generate project.godot
    project_godot_content = """
; Engine configuration file.
; It's best edited using the editor UI and not directly,
; since the parameters that go here are not all obvious.
;
; Format:
;   [section] ; section goes between []
;   param=value ; assign values to parameters

config_version=5

[application]

config/name="The Living Delve"
run/main_scene="res://viewer/Main.tscn"
config/features=PackedStringArray("4.2", "Forward Plus")
config/icon="res://icon.svg"

[autoload]

; Strict order required. Events first, then Managers.
ECSEvents="*res://singletons/ECSEvents.gd"
ECSManager="*res://singletons/ECSManager.gd"
GameLoopManager="*res://singletons/GameLoopManager.gd"

[physics]

common/physics_ticks_per_second=60
    """
    write_file("project.godot", project_godot_content)

    # 3. Generate .gitignore
    gitignore_content = """
# Godot-specific ignores
.godot/
*.translation
*.import
export.cfg
export_presets.cfg

# Logs and OS files
*.log
.DS_Store
Thumbs.db
    """
    write_file(".gitignore", gitignore_content)

    # 4. Generate GitHub Actions CI YAML
    ci_content = """
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
      image: barichello/godot-ci:4.2.1 
    
    steps:
      - name: Checkout Code
        uses: actions/checkout@v3
        with:
          submodules: recursive # CRITICAL for GUT framework

      - name: GDScript Linter
        run: |
          apt-get update && apt-get install -y python3-pip
          pip3 install gdtoolkit
          gdlint .

      - name: Pre-Import Assets (CRITICAL ANTI-HANG FIX)
        run: |
          godot --headless --editor --quit

      - name: Run ECS Unit Tests (Headless)
        run: |
          godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gexit
    """
    write_file(".github/workflows/godot_ci.yml", ci_content)

    # 5. Generate Initial STATE.md
    state_content = """
# Agent Handoff State

*   **Current Branch:** `main`
*   **Active Goal:** Initialize Sprint 0 - Core ECS Data structures.
*   **Last Completed:** Repository bootstrapping via `build_repo.py`.
*   **Known Blockers/Bugs:** None. Awaiting Sprint 0 commencement.
*   **Next Immediate Steps:** Create a branch `feature/sprint0-setup`, install GUT into `/addons`, and construct the `GameLoopManager.gd` skeleton.
    """
    write_file("STATE.md", state_content)

    print("\n✅ Bootstrap complete!")
    print("\nNEXT STEPS FOR HUMAN:")
    print("1. Save all generated markdown design documents into the new /docs/ folder.")
    print("2. Run 'git init' and commit this skeleton to your repository.")
    print("3. Point your AI coding agent to this directory.")

if __name__ == "__main__":
    main()
