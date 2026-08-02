# Agent Handoff State

*   **Current Branch:** `dev`. **`dev` IS PROMOTED TO `main` (2026-08-02, PR #11, merge commit
    `f7fc75b`), on the owner's explicit instruction** ("merge, promote, get everything into
    main", re-approved when the permission layer first blocked the merge). The promotion was a
    clean fast-forward: `main` (`ce03868`, the spec baseline) was a strict ancestor of `dev`;
    56 commits, 696 files, CI green on every `dev` push including the tip. `main` now carries
    Sprints 1-4, the remediation, and the player UI layer. The standing rules stand: never push
    directly to `main`; promotions go through a PR the owner authorizes.

*   **THE WHOLE SPRINT 3-4 STACK IS MERGED INTO `dev` (2026-08-02), on the
    owner's explicit instruction** ("merge it all, i'd rather fix things later than get them
    tangled up"): PR #7 (world inspector), #8 (Sprint 3.5), and #10 (Sprint 4 + the Sprints 1-4
    remediation + the player UI pass) are merged into `dev`; all feature branches deleted.
    PR #9 shows CLOSED, not merged — GitHub closed it when its base branch was deleted — but
    every commit in it landed through #10's ancestry (verified with `git merge-base
    --is-ancestor`; noted on the PR). Post-merge `dev` verified locally: 619 tests / 39
    scripts green, gdlint clean, world scenario prints `ECS_BOOT_OK`. Next feature work:
    branch off `dev` as usual.

*   **LAST CHANGE: THE PLAYER UI PASS (2026-08-02). 619 tests across 39 scripts, gdlint clean,
    both scenarios frame-verified, and two subagent beauty reviews (genre + accessibility)
    applied against rendered frames — eighteen findings closed or declared, recorded in the
    design doc §7.** The goal-set order was a full UI/UX exercise plus "make it
    easy and beautiful to play what we have". The central audit finding: hiding the debug
    overlay left the player with NO health bar, no stamina, no event feedback, no clock — every
    player-facing fact lived inside a developer tool, which is why debug info "drowned". What
    shipped:
    *   **`ui/player_hud.gd`** — the always-on player layer, laid out per
        `docs/hud_and_main_interface_architecture.md` §2: drawn vital bars top-left (ticks
        every 25, 0.6 s damage ghosting, casting strain as an amber dent in the stamina bar),
        the spam-aggregated running log bottom-left (player-relevant events only, one line per
        repeat with `(xN)`), the keybar bottom-center with the bound spell named in player
        words (`Fire bolt`, via `EntityCard.spell_name`), the load chip bottom-right, the
        clock top-right. Never eats input; every Control is MOUSE_FILTER_IGNORE.
    *   **`ui/pack_panel.gd`** (`I`) — the inventory made visible: auto-sorted heaviest-first
        list (ui_ux spec §5: never a Tetris grid), space/load bars, pace penalty, and its
        read-only limit stated on its face (no DROP intent exists yet).
    *   **`ui/ui_theme.gd` + `ui/vital_bar.gd`** — one visual voice for all player panels
        (warm parchment palette, 3 px radius, 12 px padding, WCAG-verified contrast asserted
        by `tests/test_player_hud.gd`; stamina is TEAL not green for colour-blind safety).
        Debug keeps its cool monospace voice ON PURPOSE — two voices tell the player which
        layer is talking. Hover card and Grimoire rethemed onto it.
    *   **Debug segregation** — the overlay boots HIDDEN (`F1` summons, `overlay_visible_on_boot`
        restores) and gizmos boot OFF (`G`; persisted key renamed `gizmos_visible` as a
        one-time default reset, because every existing config had the old on-default baked in).
    *   **A real input bug fixed**: the bridge polled only the debug overlay's `wants_mouse`,
        so a click on the open Grimoire swung a weapon at the world behind it. All panels now
        claim their own clicks.
    *   **The design record** is `docs/ui_information_architecture_and_hud_plan.md`: the ring
        model (glance/point/summon), answers to mouseover/examine/inventory/keys/radial/debug
        questions, a 12-row ambiguities-resolved-by-choosing table (spec deviations recorded,
        e.g. two bars + strain dent instead of three bars; radial DEFERRED until >1 bound
        spell), and the genre beauty standard with verified contrast maths in Appendix A.
    *   **Frame-verified** via a temporary capture harness (deleted): windowed captures of both
        scenarios; found and fixed a placement bug (RichTextLabel min-size under-reporting —
        `reset_size()` before measuring) and a capture pitfall worth remembering: the project
        boots MAXIMIZED, so movie-writer frames CROP the real canvas and lie about clipping.

*   **The player-facing hover card (2026-08-01). 602 tests across 38 scripts,
    gdlint clean.** Point at anything and `ui/hover_card.gd` names it — no key, no panel, no tag
    vocabulary. Words come from `ui/entity_card.gd`, which is pure, static and row-only so a
    headless test asserts every line. Three things changed underneath it: `BodyComponent.species`
    now exists (`spawn_creature` took a species, branched on it and threw it away, so every
    animal displayed as "creature"); `DebugOverlay._label_for`/`_name_of` delegate to
    `EntityCard` so the feed, the inspector header and the card cannot drift apart; and
    `_remembered_names` is keyed by HANDLE rather than row, which fixes a real misattribution —
    rows are recycled, so the feed could name a death after whatever now occupied the slot.
    **Known gap this did NOT close:** entities still all render as coloured boxes, so telling
    things apart *without* pointing at them is unsolved. Declared in RUNNING.md.

*   **THE SPRINTS 1–4 REMEDIATION PASS IS COMPLETE (2026-08-01). 585 tests across 37 scripts,
    gdlint clean, soak gate green, 27/27 mutations killed.** Four audit sweeps (Sprints 1–2
    spec-vs-code, Sprint 3/3.5 beyond §4b, Sprint 4 beyond §6, and a dead-symbol sweep over
    every first-party declaration) produced 51 spec findings and 72 dead symbols on top of the
    ~28 already-declared gaps. Every declared gap and every buildable finding is closed; the
    rest are declared with reasons. The ledger is
    `docs/audits/REMEDIATION-LEDGER-sprints1-4.md` (56 items, all FIXED); the external-audit
    manifest is `docs/audits/OUTPUT-IMPL-AUDIT-remediation-sprints1-4.md`.
    The headline closures:
    *   **The social layer exists** (`ecs/systems/social_system.gd`): loyalty recalculated and
        READ, succession by prestige with an immediate crisis reasoning tick, schism into a
        real DAG faction at war with its parent, WAR's first behavioural consumer (hostile
        citizens attack on sight), non-lethal brawls, trade caravans carrying real
        interceptable cargo, ClaimTags with a trespass rule, and Guest_Status that a witnessed
        crime revokes.
    *   **Fire is a process**: DoT, burnout, fuelled sources burn down, ignition temperatures,
        fire heats what it touches (`conduct_pair`'s first production caller), smoke blocks
        sight, detonations are audible (`spawn_noise`'s first callers). One word for water
        (`Wet`) — the starting water spell could not quench a fire it hit before.
    *   **Strain per the magic doc** (temporary max-stamina damage) with rest recovery —
        nothing in the build restored stamina at all; a fireball was castable five times per
        LIFE. Overclocking + the d100 mishap table + the Mercy Cap. Rune learning at lecterns.
        Insight grows in play.
    *   **The wiring blockers**: Pre-Warm actually runs at boot (the counter used to claim 100
        ticks while zero ran); all seven missing systems merged into `counters()` (F1 showed
        zeros forever); planner jobs claim at a real score (LLM objectives used to survive
        half a second); professions attached with matching `Prof_*` keys; faction memory
        decays at read; queue priorities; timeout requeue; the 200-char cap enforced.
    *   **Infrastructure**: the ADR-20 soak harness (`--soak=<n>`, CSV, committed baseline,
        SOAK_OK gate, verified deterministic), the debugging spec's event trace (ring buffer,
        dump-on-death), free camera + spawn console (F8/F9/F10), boot per-phase timing,
        per-floor hazard zones, the Adventurer's Residence, DAG compaction at the Interregnum,
        the Interregnum advancing the CALENDAR, and the dead-symbol cull (24 deleted, 2 wired,
        registry reconciled in both directions).

*   **SPRINT 4 "THE CRUCIBLE" IS IMPLEMENTED (2026-08-01). 506 tests across 32 scripts, gdlint
    clean, boot sentinel present.** All five roadmap steps plus the Grimoire UI the scope
    document assigns to this sprint:
    *   **Step 5 first, as the roadmap instructs.** `Tab` now toggles: a new target inspects, the
        same target clears, empty ground clears. That last case REVERSES the Sprint 3 player-row
        fallback, deliberately.
    *   **Reaction matrix.** Sorted-pair keys, INTRA/INTER/**BOTH** scope, the 60-frame
        anti-recursion lock, energy DERIVED from the burning material rather than typed into the
        rule table, a real ambient rise over the chunk's air, and a capped kinetic blast.
    *   **Gas in the fluid CA**, keyed on ambient versus boiling point: gas ignores elevation and
        dissipates, while liquid stays exactly conservative.
    *   **Spell compiler**, with the two caps failing DIFFERENTLY on purpose — complexity refuses,
        geometry clamps and says so. Runes, triggers, shapes, catalysts, `Absorb_Tag`
        conservation.
    *   **Casting** through the Sprint 1 Ephemeral primitive. The TRIGGER decides when the payload
        fires and the SHAPE decides where, which is what makes the magic doc's Trap and its
        fireball different spells.
    *   **Mutation and the ecology loop**, with the faction shift propagated by gossip and
        weighted by the WITNESS faction's own culture — the only act in the game whose severity
        depends on who saw it.
    *   **The Grimoire panel** (`B`), because `docs/scope_and_milestones.md` assigns Sprint 4 the
        UI that fronts the compiler, and a compiler with no route in would have been the fifth
        system this project shipped unreachable.

*   **SIX DEFECTS FOUND AGAINST MY OWN WORK, before any external audit.** Listed because the
    METHOD that found each one is the reusable part:
    1.  **Four trigger runes and a Cone that did nothing.** `trigger`, `delay_s` and
        `cone_angle_deg` were written by the compiler and read by nobody. Found by GREPPING FOR A
        SECOND REFERENCE to every new symbol — not by any test.
    2.  `RuneLibrary.ids_of_kind` had exactly one reference. Same grep. Deleted.
    3.  **The mutation affinity table named four cultures that do not exist.** Every branch
        unreachable. Same grep, then checked against `DAGGenerator.CULTURES`.
    4.  **The documented flash-fire demo did not work.** The rule was INTER-only and a fireball
        leaves both tags on ONE entity. Every unit test passed because they all arranged the tags
        across two neighbours. Found by RUNNING THE DOCUMENTED PLAY ROUTE END TO END.
    5.  **A +48% regression in the CA, the hottest loop in the build.** Found by A/B BENCHMARKING
        AGAINST `git stash`, not by any test. Now ~10%, and stated in RUNNING.md.
    6.  `LineageJournal.apply_to` REPLACED insight rather than merging. Pre-existing and harmless
        until Sprint 4 made insight load-bearing; an empty journal would have left a successor
        permanently unable to cast.

*   **`--scenario=<name>` FINALLY EXISTS.** `scope_and_milestones.md` §7 specifies it as a
    SPRINT 1 deliverable and it was never built, which meant the only route to the test arena —
    where every hand-authored feature in the build lives, including all three Sprint 4 props —
    was hand-writing JSON into an OS-specific application-data directory that RUNNING.md named
    eleven times before saying where it was. It cost the owner a play session on the very first
    attempt at Sprint 4. Also `--overlay-font=` and `--no-overlay`. **CLI overrides are never
    persisted**: without that guard, one `--scenario=test_arena` plus any runtime font change
    would write the debug room in as the permanent default. Every boot now prints the active
    scenario and the real config path.

*   **30 MUTATION TESTS RUN AGAINST THE NEW CODE, ALL KILLED.** Two initially survived and both
    turned out to be BAD MUTATIONS rather than weak tests — worth re-deriving rather than
    trusting. The harness is in the session log; the pattern is: break the fix, run the file,
    confirm red, restore.

*   **SPRINT 3 + 3.5 (2026-07-31). Green, and under adversarial audit.**
    375 tests across 28 scripts, gdlint clean, boot sentinel present.
    Sprint 3 delivered: grid A* with bounded expansions and partial-route degradation; two-tier
    locomotion; the `JOB_TEMPLATES` planner; the reasoner (heuristic default, remote optional per
    the ADR-5 amendment) behind a Validation Gate; the death loop with corpse, generation bump,
    Interregnum taxes and the Lineage Journal; stairs and floor streaming; and a rewritten F1
    inspector. Sprint 3.5 delivered the consequence layer: grievances, per-faction-pair
    reputation, hostility crossing, and gossip.
    **Sprint 3.5 is deliberately PARTIAL and this is on the record.** Its spec names nine things;
    three are built, one under a different shape, one partial, two exist as unread fields, two do
    not exist. `docs/audits/OUTPUT-IMPL-AUDIT-sprint3-and-3.5.md` §4b enumerates every one, plus
    four Sprint 3 requirements that were not built (per-faction reasoning cap, thinking bark,
    Adventurer's Residence, `reason_summary` length cap). Do not treat that section as scope
    creep to close silently — it is the declared baseline two external auditors are checking.
    TWO EXTERNAL INPUT AUDITS ARE IN AND TRIAGED — see `docs/audits/TRIAGE--*.md`. The second
    (GPT-5.5 via Copilot CLI) found three defects that were live in the SHIPPED CODE, not only in
    the specs, all now fixed:
    *   The player-death DAG edge was `DESTROYED(player, killer)`, which under this graph's own
        convention read as the player having wiped out the killer's faction. `KILLED_BY` is now a
        registered `EdgeType` with the direction convention written down. The old test asserted
        only `source_id`, so it passed against an edge that said the opposite of the truth.
    *   `PromptBuilder.salient_memories` and `FactionCoreComponent.prune_diplomacy` both sorted on
        one field with the unstable `sort_custom`, so ties changed WHICH items were selected.
        That violates ADR-20 and silently missed the prompt-hash response cache. Both now use a
        total order ending in a unique id. **Any `sort_custom` comparing a single field is a
        candidate for the same bug — check before adding one.**
    *   Interregnum reputation decay was never implemented at all, so a hostile faction stayed
        hostile across every future life and the death loop was a respawn. Now decays annually
        (`GRUDGE_RETAINED`); the grievance LIST deliberately survives.
    Also added: `test_every_registry_enum_matches_the_code`, because nothing enforced the
    registry-is-canonical rule and that is how a roadmap came to name an `EdgeType` that did not
    exist.

*   **BOTH OUTPUT AUDITS ARE IN AND TRIAGED** — `docs/audits/TRIAGE--OUTPUT-AUDITS--20260801.md`.
    392 tests. Ten more defects fixed, and **two of my own §4 claims were flatly FALSE**:
    *   A timeout forced FORTIFY, so a faction mid-raid abandoned it because the network was slow.
        `on_timeout()` — the function implementing the rule I claimed — had NO CALLER. Failures of
        every kind now change nothing.
    *   A fatal fall or blow ran `_convert_to_corpse` on ROW 0, tagging the reserved player row
        `Corpse`/`Filth` before `DeathLoopSystem` ran, which then built a second corpse from the
        mutated state. Guarded now.
    *   Also fixed: unbounded response cache; `objective_target` written and never read (a raid
        marched around its own village); reasoning running hourly instead of ADR-9's weekly;
        registry COMPONENT drift in both directions; `was_recently_attacked` never checking when.
    *   ONE FINDING REJECTED. An audit reported the `Authorization` header as a broken format
        string. The auditor's own harness had masked the credential-shaped token and it analysed
        its own redacted output. `od` shows `"Authorization: Bearer %s" % _api_key` intact.

*   **THE RECURRING DEFECT IN THIS CODEBASE IS A DOC COMMENT THAT DESCRIBES BEHAVIOUR THE CODE
    DOES NOT HAVE. Eight instances across two sprints.** Sprint 3: `PREFERRED_PROFESSION`
    (declared, never read), `on_timeout` (written, never called), `_convert_to_corpse` ("for
    non-player entities", no check), `was_recently_attacked` ("recently", no time check).
    Sprint 4: `trigger` and `delay_s` (compiled, never read — four trigger runes with identical
    behaviour), `cone_angle_deg` (a Cone that was a sphere), `ids_of_kind` (one reference),
    and `MUTATION_AFFINITY` (naming four cultures no faction has).
    Every one read as covered and passed review.
    **BEFORE BELIEVING A COMMENT, GREP FOR A SECOND REFERENCE TO THE SYMBOL.** This is now the
    single highest-yield check on this codebase; it found four of Sprint 4's six self-caught
    defects. A test that calls a helper directly does not prove the production path uses it, and
    a unit test that arranges its own fixture does not prove the shipped content reaches it —
    the flash-fire demo passed every unit test and did not work.

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

*   **Active Goal:** Everything through the player UI pass is merged into `dev` and verified.
    Nothing is in flight. The next UI increment, in order of declared intent: the examine tier
    (pinned insight-gated card), DROP intent + an actionable pack, the settings screen
    (remapping + accessibility), quick-belt slots, and the `B`→`G` Grimoire key reconciliation
    (decision #4 in the HUD plan). The big engineering debt remains the ADR-10 perf gap
    (Rust/GDExtension port of the CA and spatial hash). Branch off `dev` for whichever comes
    next.

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
        player-facing UI (U), content validators (5). Faction politics (3.5) is now PARTIALLY
        built — see the Sprint 3.5 note at the top and §4b of the output audit manifest for
        exactly which parts.
    *   **Dead-code hazard, twice hit.** `FactionPlanner.PREFERRED_PROFESSION` was declared with
        a doc comment describing behaviour it did not have, because nothing read it;
        `SocialIdentityComponent.loyalty` and `.prestige` are still in that state. A declared
        symbol with one reference is a claim with no implementation behind it. Grep for a second
        reference before believing a doc comment.

*   **Next Immediate Steps:**
    1.  **Play it.** The remediation checks table in RUNNING.md §3a is the route: the water
        spell, the burning rat, the lectern, overclocking, succession-then-war, the Residence
        respawn. Everything is test-covered and NOTHING is judged for feel.
    2.  **Send `OUTPUT-IMPL-AUDIT-remediation-sprints1-4.md` to external auditors.** The
        highest-yield attack is unchanged: grep every FIXED item's symbol for its second
        PRODUCTION reference.
    3.  Close the ADR-10 perf gap — the one big engineering debt this pass deliberately did
        not touch. Rust/GDExtension port of the CA and the spatial hash; `ViewManager`'s
        one-MeshInstance3D-per-entity remains the flagged viewer-side lead.
    4.  The declared list in RUNNING.md is the content backlog: swarms materializing as
        creatures, doors/arrest/tavern-gating, NPC casting, reagent costs, trauma cures,
        disease, gear. Each is scoped and none is concealed.
    5.  **Mutation-harness lesson, for the next agent:** restore mutated files from the saved
        source STRING, never `git checkout` (it reverts uncommitted work), always re-import
        after editing an autoload, and treat "test file did not run" as its own verdict —
        Godot's cyclic-parse quirk makes a skipped file read as a green one.
