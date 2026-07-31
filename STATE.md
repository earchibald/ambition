# Agent Handoff State

*   **Current Branch:** `feature/spec-gestalt-review` (off `dev`). `dev` has been
    fast-forwarded to `main` (it was 1 commit BEHIND, which would have made any branch cut off
    `dev` miss the entire ADR-integration pass). Remote `origin` exists but **nothing has been
    pushed yet**.
*   **Active Goal:** Final gestalt adversarial review is COMPLETE and applied. Next: implement
    Sprint 0, then Sprint 1, per the mandatory staged build order now at the top of
    `docs/sprint_1_implementation_roadmap.md`.
*   **Last Completed:** Final end-to-end gestalt review by six independent reviewers
    (implementability, consistency/drift, math/algorithms, gestalt scope, plus two competing
    neutral panels for the controversial items). Unlike the three earlier rounds, this one
    EXECUTED the specs against Godot 4.7.1 and against real numbers — which is where every
    blocker came from. Findings and resolutions:
    `docs/ADVERSARIAL_REVIEW_GESTALT_2026-07-31.md`.

    New authoritative decisions: **ADR-18** (world scale/units, bounds, movement law),
    **ADR-19** (EntityHandle is a packed 64-bit int; query facade returns row indices),
    **ADR-20** (simulation never reads wall-clock time; soak harness is a deliverable),
    **ADR-21** (JSON cannot hold 64-bit ints — save format corrected). ADR-10's CA budget was
    corrected by measurement. New `docs/scope_and_milestones.md` assigns the previously
    unowned economy / faction-politics / UI work to Sprints 2.75, 3.5, and U.

*   **Known Blockers/Bugs:**
    *   Sprint 0 bootstrapping still not done: empty `ecs/ viewer/ ui/ singletons/ tests/
        addons/`; GUT not installed; no `Main.tscn`/`icon.svg`; `project.godot` autoloads/
        scene/icon still commented out; no `[input]` section yet.
    *   The committed CI workflow is **known broken in three ways** and must be fixed as part of
        Sprint 0 (all verified empirically, see review §2 F9-F11): the gdlint dir-guard never
        matches so lint never runs; `pip3 install` fails on the image's PEP-668 Ubuntu 24.04 base
        (and the image has no python3/pip3 at all); GUT exits 0 having run zero tests via three
        separate paths; and the boot smoke test cannot fail.
    *   Nothing pushed to `origin`; branch protection not configured.
    *   **OPEN PRODUCT DECISION FOR THE HUMAN (not applied):** competing panel A recommends
        demoting the LLM from a required dependency to an optional layer, on the grounds that
        ADR-5's own Validation Gate and Fallback Matrix already oblige a fully working no-LLM
        path. This changes the product's identity, so ADR-5 stands until the human rules.
    *   Deferred to implementation time: ADR-12 cap enforcement in code; the Persistence
        build-out (Sprint P); content schema validators.

*   **Next Immediate Steps:**
    1.  Implement Sprint 0 on `feature/sprint0-setup` off `dev`: install GUT at tag `v9.7.1`,
        create the three autoload stubs (each MUST `extends Node`), `viewer/Main.tscn` printing
        the `ECS_BOOT_OK` sentinel, `icon.svg`, restore the commented `project.godot` entries,
        add the `[input]` actions, and rewrite the CI workflow per
        `docs/sprint_0_technical_scaffolding.md` §2 R1-R7. Verify headless import, boot smoke,
        and a green GUT run locally before opening the PR.
    2.  Implement Sprint 1 in the five mandatory stages, honouring the human gate after each of
        Stages 1-4 and writing the play notes those gates require.
    3.  Open PRs into `dev`. NEVER auto-merge.
