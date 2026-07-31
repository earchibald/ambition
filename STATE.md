# Agent Handoff State

*   **Current Branch:** `main` (repo now initialized with remote `origin`:
    https://github.com/earchibald/ambition.git; no commits yet; `dev` not yet created).
*   **Active Goal:** Targeted adversarial review repairs COMPLETE. NO gameplay code until the
    repaired spec set is accepted and Sprint 0 is greenlit.
*   **Last Completed:** Applied `docs/ADVERSARIAL_REVIEW_2026-07-31.md` recommendations across
    the owning docs: added Perception/Hearing/Witness primitives; created
    `docs/persistence_and_save_architecture.md` and slotted Sprint P / Sprint 2.5; added
    MaterializationPolicy for LoD identity preservation; added mutable topology/nav
    invalidation; expanded `docs/component_and_field_registry.md`; repaired stale scaffold
    traps (1Hz/60s macro, ordinary macro interregnum, GOAP wording outside ADR, randf,
    thought_process, ownership tags, mass-as-payment, text scrambling, NavServer async
    method mandate); created root `CLAUDE.md` so `copilot-instructions.md` resolves. Then
    added `docs/invariants_and_test_strategy.md`,
    `docs/debugging_and_observability_architecture.md`, and
    `docs/content_authoring_and_schema_validation.md`, wired through README/ADR/sprint docs.
    Added `docs/archetypal_content_catalog.md` as the pure-content seed catalog and wired it
    into README, ADR, content validation, and Sprint 5. Then delegated a read-only targeted
    adversarial review of that work and captured findings in
    `docs/ADVERSARIAL_REVIEW_TARGETED_2026-07-31.md`. Applied all targeted findings:
    CLAUDE scaffold now points to root canonical file; Sprint P authority clarified; Entity 0
    death creates a separate corpse/remains entity and bumps/reuses the player handle;
    Guest_Status main text is witness-gated; residual handle/enum examples cleaned; catalog
    and schema now validate hazards/policies; review docs now read as resolved logs.
*   **Known Blockers/Bugs:**
    *   Sprint 0 bootstrapping still not done: empty `ecs/ viewer/ ui/ singletons/ tests/
        addons/`; GUT not installed; no `Main.tscn`/`icon.svg`; `project.godot` autoloads/
        scene/icon commented until Sprint 0 restores them.
    *   No push yet on `origin`; branch protection not configured.
    *   No known open spec contradiction from the dated or targeted review remains; remaining
        work is implementation-time validation and normal Sprint 0 bootstrap.
    *   Deferred to IMPLEMENTATION time: code enforcement of ADR-12 caps; the
        Persistence/serialization system build-out from the new spec; invariant/property/
        integration tests; observability/debug overlays; content schema validators.
*   **Next Immediate Steps:**
    1.  Human reviews the repaired spec set and comments if any further spec loop is needed.
    2.  After doc repairs are accepted: branch `feature/sprint0-setup` off `dev`, install GUT, create
        autoload stubs + `Main.tscn` + `icon.svg`, restore the commented `project.godot`
        entries, and open a PR into `dev` (never auto-merge).
