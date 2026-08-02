# Remediation Ledger — Sprints 1–4 full audit pass (2026-08-01) — FINAL

Working ledger for the full-audit/gap-fill/remediation pass, closed out 2026-08-01.
`FIXED` = implemented with tests. `DECLARED` = recorded as not built, with a reason, in
RUNNING.md's NOT-built list and the manifest. `REMOVED` = deleted as dead code.

Sources: the two published gap lists (Sprint 3/3.5 manifest §4b, Sprint 4 manifest §6), plus
four fresh audit sweeps run 2026-08-01: S12 (Sprints 1–2 spec-vs-code, 17 findings), S35
(Sprint 3/3.5 beyond §4b, 16 findings), S4X (Sprint 4 + cross-cutting, 18 findings), DS
(dead-symbol sweep, 72 findings).

## Wave 1 — Sprint 3 reasoning stack

| ID | Item | Status |
|---|---|---|
| W1-1 | Queue priority classes, FIFO within class [§4b G-5] | FIXED |
| W1-2 | ADR-12 faction cap = the pending bound, enforced before enqueue [§4b G-1] | FIXED |
| W1-3 | 200-char cap on `reason_summary`/`public_declaration` at ingest [§4b G-4] | FIXED |
| W1-4 | Thinking bark: `faction_thinking` + feed line [§4b G-2] | FIXED |
| W1-5 | Adventurer's Residence carved and used as the world spawn [§4b G-3] | FIXED |
| W1-6 | Perf gates as tests: arena ≤2 s, death→respawn ≤5 s, pump ≤ micro budget [§4b G-6] | FIXED |
| W1-7 | `counters()` merges all systems — F1 showed zeros forever [S35-12] | FIXED |
| W1-8 | Planner jobs claim at a real score; LLM objectives survive routine utility [S35-8] | FIXED |
| W1-9 | Professions attached in production, `Prof_*` vocabulary aligned [S35-1,2] | FIXED |
| W1-10 | Faction memory decays at read; cap 64; lowest-weight non-core eviction [S35-5,6] | FIXED |
| W1-11 | Timeout requeues next Macro tick [S35-9] | FIXED |
| W1-12 | Spawn-faction NEUTRAL floor as an explicit, directly-tested rule [S35-14] | FIXED |
| W1-13 | `release_jobs_of` on death; `mark_precondition_failed` on failed walks [S35-15] | FIXED |
| W1-14 | Swarms seeded by worldgen, bred by the Interregnum, cap reachable [S35-3] | FIXED |
| W1-15 | Committed `llm_config.cfg` with env-var overrides [S35-16] | FIXED |
| W1-16 | Guest_Status + wealth-derived starting kit, withdrawn not minted [S12-2] | FIXED |
| W1-17 | Leader memories in the prompt [§4b G-8] | FIXED |
| W1-18 | Declarations into leader memory so gossip can repeat them [§4b G-9] | FIXED |
| W1-19 | `most_salient` total order [DS] | FIXED |
| W1-20 | `player_died`/`player_reborn` listeners [DS] | FIXED |

## Wave 2 — Sprint 3.5 social layer (`ecs/systems/social_system.gd`, new)

| ID | Item | Status |
|---|---|---|
| W2-1 | `leader_handle`; leaders designated at materialization | FIXED |
| W2-2 | Succession by prestige + immediate crisis reasoning [the "most damning row"] | FIXED |
| W2-3 | Loyalty recalculated each Simulation tick from needs/memory/wealth; READ by schism | FIXED |
| W2-4 | Schism: real DAG faction, WAR both ways, RAID objective, ADR-12 cap respected | FIXED |
| W2-5 | WAR's behavioural consumer: hostile citizens engage on sight [S35-4] | FIXED |
| W2-6 | Brawls over contested resources, non-lethal by construction, grievances both ways | FIXED |
| W2-7 | ClaimTags: `claim_faction_id` set at materialization; trespass drip; Guest_Status revoked on witnessed crime | FIXED |
| W2-8 | TRADE band reachable; caravans with real, interceptable cargo; loss remembered | FIXED |
| W2-9 | Prestige assigned deterministically at spawn | FIXED |

## Wave 3 — Sprint 4 + cross-cutting

| ID | Item | Status |
|---|---|---|
| W3-1 | Burning: DoT, burnout, fuelled sources burn down [S4X-1] | FIXED |
| W3-2 | Quench works; ONE word for water (`Wet`), SCOPE_BOTH [S4X-2] | FIXED |
| W3-3 | Strain per spec (max-stamina damage), rest recovery, stamina restores at all [S4X-3] | FIXED |
| W3-4 | Event trace: ring, flag-gated, CSV dump on death [S4X-4, S12-10] | FIXED |
| W3-5 | Insight grows: kills and rune-reading [S4X-5] | FIXED |
| W3-6 | Explosion/Smoke lifetimes + smoke/steam block LoS [S4X-9, S12-7] | FIXED |
| W3-7 | Registry reconciled both directions [S4X-7,8, S35-10,11] | FIXED |
| W3-8 | Ignition-temperature model [§6 G-7] | FIXED |
| W3-9 | Natural hazard zones in worldgen [§6 G-11] | FIXED |
| W3-10 | Rune learning: lecterns in arena + dungeon chunks [§6 G-3] | FIXED |
| W3-11 | Spell/aura visuals: emissive payload-coloured spheres [§6 G-4] | FIXED |
| W3-12 | Overclocking, d100 mishap table, Mercy Cap, trauma tags [§6 G-2] | FIXED |
| W3-13 | Pre-Warm actually runs in the shipped boot [S12-1] | FIXED |
| W3-14 | Soak harness: `--soak`, CSV, committed baseline, SOAK_OK gate [S12-5] | FIXED |
| W3-15 | Free camera (F8) + spawn console (F9/F10) [S12-6] | FIXED |
| W3-16 | Noise loudest-first; listener cap counts hearers, nearest-first [S12-13] | FIXED |
| W3-17 | Perception/fluid overlay flags have readers [S12-9, S4X-12] | FIXED |
| W3-18 | Boot per-phase timing, clocked outside `ecs/` per ADR-20 [S12-12] | FIXED |
| W3-19 | DAG compaction at each Interregnum [S12-16] | FIXED |
| W3-20 | Projectile boundary exits resolved by real DDA, counted [S12-14] | FIXED |
| W3-21 | Cross-LoD combat branch STATED in ActionResolutionSystem [S12-15] | FIXED |
| W3-22 | `conduct_pair` wired: fire heats what it touches [DS] | FIXED |
| W3-23 | `spawn_noise` wired: detonations and blasts are audible [DS] | FIXED |
| W3-24 | `tick_completed` consumed: worst-frame row in the overlay [DS] | FIXED |
| W3-25 | HeatSource fields live; `fuel_materials` removed [DS, S4X-8] | FIXED |
| W3-26 | Job lifecycle: DONE and ABORTED reachable [DS] | FIXED |
| W3-27 | Dead-symbol cull: 24 deleted, 2 wired (`validate_table` at boot; the Interregnum advances the calendar), survivors declared | FIXED |

## Verification

- **585 tests across 37 scripts, all passing; gdlint clean; boot sentinel present.**
- **27 mutations run, 27 killed** — three needed a second round: one test was a tautology
  (asserting against the constant the mutation changed), one asserted evidence the boot-time
  planner produces without Pre-Warm, and one could not be evaluated because mutating the `World`
  autoload triggers a Godot cyclic-parse quirk that silently skips dependent test FILES —
  "nothing ran" reads exactly like "everything passed". The harness now verifies the file RAN.
- **Harness defect found and worth recording:** restoring mutations with `git checkout` reverted
  UNCOMMITTED work sitting in the same file (`spawn_faction_floor` vanished mid-run). Restore
  from the saved source string, never from git, when the tree is dirty.
- **Soak gate green and deterministic** across repeated runs (10 integer metrics, 600 ticks).
- Perf: reactions 1.33 ms/tick at 500 reactive entities (burn pass is budget-capped and did not
  regress the benchmark); the ADR-10 1,500-entity miss is unchanged and still on the record.

## Declared (not built, with reasons — the play-facing list lives in RUNNING.md)

Arrest/jail/tavern-gating beyond WAR hostility; swarm counters materializing as creatures;
Grimoire node-graph/hologram/cipher (G-1); NPC casting (G-5); spell material costs; the
[Spark]-fizzle/absorb-on-collision shape (recorded departure); gas emission/pressure/ventilation
(G-8) and spatial temperature; disease branch of exposure; protective-gear items; trauma cures;
AbstractGraph + topology-dirty consumers (S12-3,4 — no production tile mutation exists to feed
them); perception amortization + sector bitset (S12-8, recorded substitution); NavBridge async
shape (S12-17, intent satisfied by bounded synchronous search); explanation records (S4X-13);
`hard_fail` flag consumers (S4X-11); macro writers of faction memory (S35-7); Interregnum world
evolution beyond taxes/swarms/compaction (S35-13); ADR-10 at 1,500 entities (G-12 — the
Rust/GDExtension port remains the agreed response); ephemeral TTL soak coverage (S4X-15).

Known test-limitation on the record: the Macro-tick timeout REQUEUE wire in
`GameLoopManager._think`'s pump callback is asserted at queue level with a test-owned callback;
a mutation of the production lambda itself would survive. The behaviour is one line and reads
directly; accepted and recorded rather than scaffolding a provider-failure boot harness.
