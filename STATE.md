# Agent Handoff State

*   **Current Branch:** `main` (repo now initialized with remote `origin`:
    https://github.com/earchibald/ambition.git; no commits yet; `dev` not yet created).
*   **Active Goal:** Pre-implementation spec hardening. NO gameplay code until Sprint 0
    is explicitly greenlit. The 7 open architecture questions are now ANSWERED and
    recorded in `docs/architecture_decisions.md` (ADR).
*   **Last Completed:** Turned the adversarial review into concrete spec edits:
    created the ADR (`docs/architecture_decisions.md`); fixed all README doc links +
    renamed the meta-progression filename; updated the ECS hub spec (ticks, 2.5D/chunk_id,
    player identity, spatial/collision/pathfinding, entity lifecycle, RNG/serialization,
    perf); hardened CI (scoped lint, pinned gdtoolkit, guarded boot smoke); made
    `project.godot` load cleanly (commented missing autoloads/scene/icon); updated Sprint
    0/1/2/3 scaffolding (clock, spatial systems, combat stats, wealth-sync fix, ledger
    entropy tax, LLMProvider, JobTemplates); fixed material currency/mass; added a
    Resolution Log (§M) to `docs/ADVERSARIAL_REVIEW.md`.
*   **Known Blockers/Bugs:**
    *   Project still has empty `ecs/ viewer/ ui/ singletons/ tests/ addons/` — Sprint 0
        bootstrapping (GUT install, autoload stubs, Main.tscn, icon.svg) not yet done.
    *   Repo has no commits yet on `origin`; `dev` branch not created; branch protection
        not configured (review §I5).
    *   Still-open engineering fixes tracked in `docs/ADVERSARIAL_REVIEW.md` §M
        ("STILL OPEN") — to be handled inside each owning sprint.
*   **Next Immediate Steps:**
    1.  Human reviews the [EXEC — FOR REVIEW] calls in the ADR (ADR-2 physics exception,
        ADR-10 perf targets) and the spec edits.
    2.  Make an initial commit; create `dev`; enable branch protection on `main`/`dev`.
    3.  On greenlight: branch `feature/sprint0-setup`, install GUT, create autoload stubs +
        `Main.tscn` + `icon.svg`, and restore the commented `project.godot` entries.
