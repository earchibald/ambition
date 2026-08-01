# Agent Handoff State

*   **Current Branch:** `feature/sprint1-vertical-slice`, stacked on
    `feature/sprint0-setup`, stacked on `feature/spec-gestalt-review`, off `dev`.
    `dev` was fast-forwarded to `main` (it was 1 commit BEHIND, so any branch cut from `dev`
    would have missed the entire ADR-integration pass).

*   **SPRINT 2 COMPLETE (2026-07-31).** All six roadmap steps implemented and green:
    DAG history, world generation + tile sampler, DAG-to-ECS instantiator, LoD boundary two-way
    sync with the conservation property test, gray-box ledger economy, and the bootstrapper.
    `Main` now boots the GENERATED WORLD by default; `test_arena` remains reachable via
    `debug_config.json` and is still the fast iteration loop.
    Measured: cold boot 22 ms, 11 chunks resident, 14 factions (1 materialized with 40 citizens,
    13 left abstract), 52 entities alive, micro 0.92 ms against the 8 ms budget.
    Bugs this sprint surfaced, all silent: ChunkData defaulted to LoD.ACTIVE so every generated
    chunk claimed to be Active; the instantiator generated a chunk per faction just to read a
    flag; `_clear_previous_world` swept only positioned entities so faction ledgers accumulated
    across boots; and Sprint 1's collision could not cross a chunk seam at all.
    STILL UNPLAYED BY A HUMAN in the world scenario — frames inspected only.

*   **Active Goal:** Sprint 0 and Sprint 1 are implemented, visually verified, and merged into
    `dev`. Next: Sprint 2.

*   **START HERE IF YOU ARE NEW:** `RUNNING.md`. It has the exact commands to run the game, the
    control list, what every object in the test arena is there to test, how to read the debug
    overlay, how to run one test file, and how to capture frames without a display session.

*   **Last Completed:**
    1.  Final gestalt adversarial review by six independent reviewers (implementability,
        consistency/drift, math/algorithms, gestalt scope, plus two competing neutral panels
        for the controversial items). Unlike the three earlier rounds, this one EXECUTED the
        specs against Godot 4.7.1 and against real numbers, which is where every blocker came
        from. See `docs/ADVERSARIAL_REVIEW_GESTALT_2026-07-31.md`.
        New authoritative decisions: **ADR-18** (world scale/units/bounds/movement law),
        **ADR-19** (EntityHandle is a packed 64-bit int; the query facade returns row indices),
        **ADR-20** (simulation never reads wall-clock; soak harness is a deliverable),
        **ADR-21** (JSON cannot hold 64-bit ints). ADR-10's CA budget corrected by measurement.
        New `docs/scope_and_milestones.md` assigns the previously unowned economy, faction
        politics, and UI work to new Sprints 2.75, 3.5, and U.
    2.  **Sprint 0:** GUT vendored at v9.7.1; six autoloads; `Main.tscn` + `icon.svg`;
        `project.godot` with autoloads, main scene, icon, and the `[input]` actions;
        CI rewritten against four defects verified in the real container image; PR template.
    3.  **Sprint 1:** full vertical slice — 24 components, packed-int handles with atomic
        destroy, the `query(mask)` row-index facade, GameClock, RNGService, the hand-authored
        TestArena chunk, SpatialHash (flat counting sort), CollisionResolveSystem (substepping,
        entity-vs-entity, axis order, diagonal-gap, 2.5D step/drop), PickSystem, fluid CA,
        thermodynamics, perception with hearing and witness events, metabolism, utility AI with
        a job latch, melee combat on the energy model, ephemeral/aura primitive, spoilage, LoD,
        inventory, ViewManager, camera rig, input bridge, debug overlay, perf benchmark, soak
        harness.
    4.  **Renderability repair (the reason 135 green tests still meant nothing).** Sprint 1
        passed every test and printed the boot sentinel while displaying an EMPTY GREY VOID.
        Three defects, all invisible to a headless suite:
        *   Nothing in `viewer/` ever read `tile_map` or `height_map`, so there was no floor,
            no walls, no ledge, no pit. Added `viewer/terrain_view.gd` (MultiMesh, cosmetic
            only — collision still resolves against `tile_map`, never against these meshes).
        *   `World._spawn_player` never emitted `entity_created`, and `ViewManager` spawns
            visuals ONLY from that signal, so the player had no body at all.
        *   `DebugOverlay.select_row` — the highest-value debug surface in the build — had zero
            callers. `Tab` now selects the entity under the mouse cursor through `PickSystem`;
            bullet-time moved to its own `slow_time` action on `T`.
        `tests/test_viewer_visibility.gd` guards all three. Entities are now colour-coded AND
        size-coded (cyan player, red creature, gold item) because grey-on-grey was unreadable.
    5.  **ADR-5 amended by the human owner: the LLM is now an OPTIONAL layer**, not a required
        dependency. `NullLLMProvider` is promoted from test double to shipped provider and
        becomes the CI default. Rationale in `docs/architecture_decisions.md` ADR-5. Sprint 3
        acceptance now requires a complete play session with no endpoint configured.
    6.  `RUNNING.md` written — the run/test/debug documentation that should have shipped with
        Sprint 0.

*   **VERIFIED STATE (run locally, not asserted):**
    *   `godot --headless --import` — clean.
    *   Boot smoke — prints `ECS_BOOT_OK`, no `SCRIPT ERROR`.
    *   `gdlint` — clean across `ecs singletons ui viewer tests`.
    *   GUT — **141 tests, 14 scripts, 141 passing, ~7,480 asserts.**
    *   **Rendered frames inspected**, via
        `godot --write-movie /tmp/frames/f.png --fixed-fps 10 --quit-after 40 res://viewer/Main.tscn`.

*   **PLAY NOTE 2026-07-31 (b) — FIRST HUMAN PLAY SESSION. Gate A/B signed with defects.**
    The owner played the build. It boots, renders, and the movement rules hold up: wall sliding
    works, the automatic step onto the 0.4 m ledge works, the diagonal pinch does NOT let you
    through, the pit reads as lower ground, fluid spreads and trails off, and overlay text
    resizing works. Seven defects were found that 146 green tests did not catch. The shape of
    every one: the SIMULATION was right and the PLAYER'S ROUTE INTO IT was wrong.
    1.  **`E` never worked on anything.** Reach was compared against the ray's own travel
        distance, but the ray starts at the camera ~14 m away, so the 2.5 m check could never
        pass. Reach is now measured from the actor, and the actor is excluded from its own pick.
    2.  **`LMB` could not hit a target you were standing next to.** The swing arc came from the
        movement keys, so a standing player swung along a hard-coded +Z and a rat due east sat
        90 degrees outside the 120-degree arc. Aim now runs from the player to the cursor tile.
    3.  **Nothing ever moved vertically.** The collision resolve integrated X and Z only, so a
        falling body accumulated downward velocity forever while its position stayed put. The
        pit could not be entered, dropped items hung in the air, and creatures had no gravity
        at all — `resolve_fall` had zero callers anywhere in the codebase. Fall damage was
        implemented, tested, and unreachable.
    4.  **No outcome feed.** Melee, falls, deaths and pickups all resolved correctly and reported
        nothing, so a hit and a miss looked identical. Added `entity_damaged`, `entity_died`,
        `item_taken` and `action_rejected` to the bus, plus an 8-entry event feed in the overlay.
        Refusals are reported too: silence was the single worst thing about the build.
    5.  **`boot_scenario` never reset the ECS.** A second boot left every entity from the first
        one alive at its old position. Found via a leaking test, but it is a real duplication bug.
    6.  **Enums printed as raw integers.** `awareness 0` was read as "asleep"; it is UNAWARE, and
        Sprint 1 has no sleep state. The inspector now prints names.
    7.  **No vitals or input state on screen.** Added health/stamina/airborne and LMB/RMB state.
    Verified after the fixes: the player falls into the pit, lands at frame 32 at 5.4 m/s,
    and rests exactly on the pit floor. **158 tests green**, 12 of them new regression guards in
    `tests/test_playtest_regressions.gd`.
    STILL UNJUDGED: whether melee reach and arc feel fair in play.

*   **PLAY NOTE 2026-07-31 (c) — MOTION FEEL. "Swimmy", with a diagnosable cause.**
    The owner reported the level sloshing around the player enough to cause mild motion
    queasiness. The cause was TWO independent exponential lags chasing the same moving target at
    different rates: `ViewManager` smoothed the avatar toward ECS truth at 15.0, and `CameraRig`
    smoothed the camera toward the player at 8.0. Exponential smoothing toward a moving target
    never catches it — at speed v and rate k it settles a constant v/k behind. At the 4 m/s walk
    speed that is 0.27 m for the avatar and 0.50 m for the camera, and the DIFFERENCE is visible
    drift of the avatar inside its own frame on every acceleration and stop. A third contributor
    was a per-frame `camera.look_at`, which rotated the entire world a fraction of a degree every
    frame — invisible in a screenshot, and the most nauseating part of the rig.
    Both halves are now exact rather than tuned:
    *   `ViewManager` uses FIXED-TIMESTEP INTERPOLATION between the previous and current
        simulation positions. Zero steady-state lag, and no tuning constant to get wrong.
        `SMOOTHING_RATE` is deleted.
    *   `CameraRig` has a DEADZONE, as the owner suggested. Inside 5 m horizontally (2 m
        vertically) it does not move at all; outside, it moves exactly far enough to put the
        player back on the boundary. No smoothing anywhere. Orientation is set once in `_ready`
        and frozen. The camera tracks the DRAWN position, not raw ECS truth, or it would sit one
        interpolation fraction ahead of the avatar it frames.
    Also added, on request: `viewer/debug_gizmos.gd` (`G`) drawing the facing arrow, melee arc,
    interact radius and sight radius. Every radius is read from the system that enforces it, so a
    gizmo cannot disagree with its rule. 7 new tests in `tests/test_camera_and_motion.gd` pin the
    deadzone arithmetic and assert `_process` contains no `look_at`.

*   **PLAY NOTE 2026-07-31 (a) (required by `docs/scope_and_milestones.md` R3):**
    Verified by looking at rendered frames, not by hand at the keyboard — so Gates A/B are
    provisionally signed for *renders correctly and boots controllable*, and remain UNSIGNED
    for *feel*. What the frames changed:
    *   The camera follow offset was `(0, 6, 8)`. That put the horizon halfway up the screen and
        gave half the frame to empty floor, and made the 0.4 m ledge and the 2.5 m pit read as
        the same flat shape. Now `(0, 11, 9)`. Steeper pitch is what makes 2.5D legible, which
        is the entire reason the camera is third-person.
    *   Entity visuals were all the same grey as the stone floor. Now tag-coloured.
    *   `SMOOTHING_RATE = 15.0` in `ViewManager` is STILL an untested guess. It needs a human
        with hands on WASD; frames cannot judge it.
    *   Still unjudged by anyone: whether melee at 2.0 m reach and a 120-degree arc feels fair,
        and whether the step-up onto the ledge reads as intentional or as a glitch.

*   **Known Blockers/Bugs:**
    *   **MEASURED PERF GAP (ADR-10).** On an M5 Max debug build:
        `collision + spatial hash` = 0.9 ms at 50 entities, 4.8 ms at 500, **13.7 ms at 1,500
        against an 8 ms budget for ALL Micro systems.** Scaling is linear; the constant is too
        high. Fluid CA measures **0.83 us/cell, so 20,000 cells would cost ~16.6 ms** — which
        independently reproduces the review's finding that ADR-10's original CA budget was
        ~164% of the whole frame budget on its own. Fluids therefore run at 15 Hz with a 12,000
        cell budget. The honest position: **Sprint 1 does NOT meet the ADR-10 Micro budget at
        the 1,500-entity target**, and both competing panels concluded the correct response is
        to pre-commit the Rust/GDExtension port for the CA and spatial hash rather than treat
        it as a contingency, and NOT to lower the entity caps. Reducing the entity-vs-entity
        query radius already took 1,500 entities from 32 ms to 13.7 ms; more remains.
    *   The rat does not move or perceive. It has Needs, Schedule, Perception and Memory but no
        job source and no Simulated-tier movement, so `perceived 0  witnesses 0` on a bare boot
        is expected, not a bug. NPC movement lands in Sprint 2.
    *   NavigationServer3D is deliberately OUT of Sprint 1 (nothing bakeable exists yet and it
        is untestable under GUT). NavBridge/grid A* is not implemented either.
    *   Deferred to their own sprints: persistence build-out (Sprint P), economy (2.75),
        faction politics (3.5), player-facing UI (U), content validators (5).

*   **Next Immediate Steps:**
    1.  **Play it with hands.** `godot res://viewer/Main.tscn`. Judge movement feel, the
        `SMOOTHING_RATE` guess, melee reach, and the ledge step. Write the result here. Do this
        BEFORE Sprint 2, as the staged build order requires.
    2.  Sprint 2 (world/floor generation, chunk streaming, LoD conservation property tests),
        per `docs/scope_and_milestones.md` §6. Sprint 2's WorldGrid replaces `TestArena` as the
        *producer* of ChunkData; the consumer contract must not change.
    3.  Fold the ADR-5 amendment into `docs/llm_reasoner_and_planning_architecture.md` and into
        the Sprint 3 roadmap, whose acceptance criteria now include a no-endpoint play session.
    4.  Close the ADR-10 perf gap. Rust/GDExtension port of the CA and the spatial hash.
