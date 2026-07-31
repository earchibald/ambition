# Agent Handoff State

*   **Current Branch:** `feature/sprint1-vertical-slice`, stacked on
    `feature/sprint0-setup`, stacked on `feature/spec-gestalt-review`, off `dev`.
    `dev` was fast-forwarded to `main` (it was 1 commit BEHIND, so any branch cut from `dev`
    would have missed the entire ADR-integration pass). Remote `origin` exists but **nothing
    has been pushed yet** and no PRs are open.

*   **Active Goal:** Sprint 0 and Sprint 1 are implemented and green. Next: push the three
    branches and open stacked PRs into `dev` (NEVER auto-merge), then Sprint 2.

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
    2.  **Sprint 0:** GUT vendored at v9.7.1; three autoloads; `Main.tscn` + `icon.svg`;
        `project.godot` restored with autoloads, main scene, icon, and the `[input]` actions;
        CI rewritten against four defects verified in the real container image; PR template.
    3.  **Sprint 1:** full vertical slice — 24 components, packed-int handles with atomic
        destroy, the `query(mask)` row-index facade, GameClock, RNGService, the hand-authored
        TestArena chunk, SpatialHash (flat counting sort), CollisionResolveSystem (substepping,
        entity-vs-entity, axis order, diagonal-gap, 2.5D step/drop), PickSystem, fluid CA,
        thermodynamics, perception with hearing and witness events, metabolism, utility AI with
        a job latch, melee combat on the energy model, ephemeral/aura primitive, spoilage, LoD,
        inventory, ViewManager, camera rig, input bridge, debug overlay, perf benchmark, soak
        harness.

*   **VERIFIED STATE (run locally, not asserted):**
    *   `godot --headless --import` — clean.
    *   Boot smoke — prints `ECS_BOOT_OK`, no `SCRIPT ERROR`.
    *   `gdlint` — clean across `ecs singletons ui viewer tests`.
    *   GUT — **135 tests, 13 scripts, 135 passing, 7,466 asserts.**

*   **PLAY NOTE 2026-07-31 (required by `docs/scope_and_milestones.md` R3):**
    Not yet played interactively — this session ran headless only, so Gates A-D are NOT
    signed off. **This is the single most important outstanding item.** The build boots to a
    controllable player in the test arena with a rat and a copper nugget in reach, so the gates
    are reachable immediately. Thing to change first, from reading the numbers rather than
    feeling them: the ViewManager smoothing rate of 15.0 and the third-person follow offset are
    untested guesses and will almost certainly feel wrong.

*   **Known Blockers/Bugs:**
    *   **MEASURED PERF GAP (ADR-10).** The new benchmark reports, on an M5 Max debug build:
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
    *   Nothing pushed to `origin`; no PRs open; branch protection not configured.
    *   **OPEN PRODUCT DECISION FOR THE HUMAN (not applied):** competing panel A recommends
        demoting the LLM from a required dependency to an optional layer, because ADR-5's own
        Validation Gate and Fallback Matrix already oblige a fully working no-LLM path. This
        changes the product's identity, so ADR-5 stands until the human rules.
    *   NavigationServer3D is deliberately OUT of Sprint 1 (nothing bakeable exists yet and it
        is untestable under GUT). NavBridge/grid A* is not yet implemented either — Simulated
        movement lands in Sprint 2.
    *   Deferred to their own sprints: persistence build-out (Sprint P), economy (2.75),
        faction politics (3.5), player-facing UI (U), content validators (5).

*   **Next Immediate Steps:**
    1.  **Play it.** Run `godot res://viewer/Main.tscn`, walk the arena, hit the rat, pick up
        the nugget, and write Gates A/B play notes here. Fix movement feel BEFORE Sprint 2, as
        the staged build order requires.
    2.  Push the three branches and open stacked PRs into `dev`. Do NOT auto-merge.
    3.  Decide the ADR-5 LLM question above.
    4.  Then Sprint 2 (world/floor generation, chunk streaming, LoD conservation property
        tests), per `docs/scope_and_milestones.md` §6.
