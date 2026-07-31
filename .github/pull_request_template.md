## Description of Changes

[Briefly describe what this PR adds or fixes.]

## Architectural Checklist (MANDATORY)

- [ ] I did NOT use `CharacterBody3D`, `RigidBody3D`, `Area3D`, `move_and_slide()`, or a physics
      raycast for game logic. (`tests/invariants/test_forbidden_apis.gd` enforces this.)
- [ ] If I added a new System, I explicitly registered it to the `Micro`, `Fluid`, `Simulation`,
      or `Macro` tick in `GameLoopManager`.
- [ ] UI/viewer code added here only *listens* to `ECSEvents`; it does not mutate ECS state.
- [ ] Every component, field, enum value, and tag I used exists in
      `docs/component_and_field_registry.md`. If I added one, I updated the registry.
- [ ] Entity references are packed-int handles (ADR-19). I did not introduce an object handle,
      and no `Dictionary` is keyed by an object.
- [ ] Nothing in `ecs/` reads wall-clock time (ADR-20). Cadence comes from tick counts.
- [ ] I wrote a unit test in `res://tests/` for any new math, and it actually runs
      (`-ginclude_subdirs` if it is in a subdirectory).
- [ ] I updated `STATE.md` using the exact required format.

## Sprint Gate

- [ ] The relevant sprint gate in `docs/invariants_and_test_strategy.md` §4 passes.
- [ ] If this closes a sprint: I played it for ten minutes and added a dated play note to
      `STATE.md` naming at least one thing to change. ("Feels fine" is not a play note.)

## Verification

Paste the actual output, not a claim:

```
# godot --headless --import
# godot --headless --quit-after 120 res://viewer/Main.tscn   (expect ECS_BOOT_OK)
# godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

---

**DO NOT AUTO-MERGE.** Await human review (CLAUDE.md §2).
