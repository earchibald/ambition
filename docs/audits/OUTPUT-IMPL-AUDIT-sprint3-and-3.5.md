# OUTPUT / IMPLEMENTATION AUDIT — Sprint 3 & Sprint 3.5

**You are an adversarial auditor. Your job is to falsify the claims below.**

This document is self-bootstrapping. Read it top to bottom, follow the procedure, write the output
file. Do not ask for further instructions.

Everything in §4 is a **claim made by the implementing agent about its own work**. Claims are not
evidence. Several were verified only by tests that same agent wrote, which is exactly the
circularity you are here to break.

---

## 0. What you are auditing

You are auditing the **IMPLEMENTATION** against (a) the specs it was built from and (b) reality.

**IN SCOPE:** claims in §4 that are false, overstated, or true only under conditions the claim
omits. Tests that assert nothing. Tests that pass for the wrong reason. Code that satisfies its
test while failing its purpose. Unbounded work. Invariants that hold in tests and not in the
running game. Anything the implementer said it did that it did not do.

**OUT OF SCOPE:** whether the specifications were any good. A separate auditor has that job via
`INPUT-SPEC-AUDIT-sprint3-and-3.5.md` in this directory. "The spec was vague here" is not your
finding; "the implementation does X and nothing anywhere asked for X" is.

### IGNORE OTHER AUDITORS' RESULTS — this is mandatory, not advice

`docs/audits/` accumulates finished reports from parallel auditors. **Treat every file matching
these patterns as if it does not exist:**

```
docs/audits/INPUT-AUDIT-RESULT--*.md
docs/audits/OUTPUT-AUDIT-RESULT--*.md
docs/audits/TRIAGE--*.md
```

Do not open them. Do not cite them. Do not check whether you agree with them. If you have already
read one, say so in your report and treat every finding you share with it as suspect.

The reason is not politeness. Several models audit this change set independently, and the entire
value of that is **independent** evidence: a defect found by three auditors who could not see each
other is strong evidence, and a defect found by one auditor and echoed by two who read it first is
one auditor with extra steps. Anchoring is not something you can decide not to do after reading.

This has already cost something. The first input audit reported a documentation heading as having
"zero text underneath" when it has seven lines under it, including a complete selection rule. An
auditor who took that on trust would have propagated it. **Verify every claim against the file,
including claims made by the implementer in §4 and §4b of this document.**

The two manifests — this one and `INPUT-SPEC-AUDIT-sprint3-and-3.5.md` — are inputs and are meant
to be read. Result files are outputs and are not.

---

## 1. Environment and how to run it

| Item | Value |
|---|---|
| Repository | `https://github.com/earchibald/ambition` |
| Local path | `/Users/earchibald/Code/ambition` |
| Branch under audit | `feature/sprint3.5-body-politic` |
| Base | `dev` |
| PRs | #8 (this branch) stacked on #7 (`feature/sprint3-world-inspector`) |
| Engine | **Godot 4.7.1 exactly** — other 4.x parse typed arrays differently |
| Test framework | GUT, vendored at `addons/gut` (nothing to install) |
| Linter | `gdtoolkit==4.5.*` (`gdlint`) |

```bash
cd /Users/earchibald/Code/ambition
git fetch --all && git checkout feature/sprint3.5-body-politic
git rev-parse --short HEAD          # record this in your report

# REQUIRED FIRST. class_name globals do not resolve until the project is imported;
# without this every script fails with `Identifier "X" not declared`.
godot --headless --import

# The full suite, exactly as CI runs it.
# -ginclude_subdirs is NOT optional: without it tests/invariants, tests/perf and
# tests/soak are silently skipped and the run reports green having never opened them.
godot --headless -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests -ginclude_subdirs -gexit

# One file at a time
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_reputation.gd -gexit

# Lint (first-party only; addons/ is third-party and not gdlint-clean)
pip3 install --break-system-packages "gdtoolkit==4.5.*"
for d in ecs singletons ui viewer tests; do gdlint "$d"; done

# Boot smoke. A scene whose _ready() throws STILL EXITS 0, so grep the sentinel.
godot --headless --quit-after 120 res://viewer/Main.tscn 2>&1 | grep ECS_BOOT_OK

# See it render without a display session (writes one PNG per frame)
godot --write-movie /tmp/f.png --fixed-fps 10 --quit-after 30 res://viewer/Main.tscn
```

**Expected at the audited commit: 28 test scripts, 392 tests, 0 failures, gdlint clean.**
If you observe otherwise, that is your first finding.

`RUNNING.md` documents controls and what each scenario contains. `STATE.md` records known
blockers. Read both before concluding something is broken — it may be documented as absent.

---

## 2. Architectural constraints the code is REQUIRED to obey

Violations here are automatically BLOCKER, regardless of whether tests pass.

1. **The Prime Directive** (`CLAUDE.md` §1): no `CharacterBody3D`, `RigidBody3D`, `Area3D`,
   `move_and_slide()`, or physics raycasts anywhere in first-party code. `NavigationServer3D` is
   a sanctioned exception (ADR-2) that is *deliberately unused*.
2. **`ecs/` never reads wall-clock time** (ADR-20). Simulation must be reproducible from RNG
   seeds. `Time.get_ticks_*` in `ecs/` is a violation. `singletons/GameLoopManager.gd` reads it
   for profiling only, which is documented and allowed.
3. **Handles are packed 64-bit ints** (ADR-19), never objects, never Dictionary keys as objects.
4. **JSON cannot hold integers past 2^53** (ADR-21). Anything serialized must respect that.
5. **Row 0 is the player, forever** (ADR-14). It must never reach the free list.
6. **The registry is canonical** (`docs/component_and_field_registry.md`). Any component or field
   whose name or type disagrees with it is a defect.

`tests/invariants/test_forbidden_apis.gd` claims to enforce 1 and 2. **Verify that it actually
does** — check that it reads real files, strips comments correctly, and would fail if a violation
were introduced. Try introducing one locally and confirm it fails, then revert.

---

## 3. Change set under audit

```bash
git log --oneline dev..HEAD
```

At time of writing:

```
0fc7c57 Open maximized, and implement Sprint 3.5: consequences
8f36b57 Lay the debug pages out properly instead of printing console lines
a24c3a9 Draw the chunk map properly, mark stairs in the world, and fix two of my own bugs
5ba70cb Add stairs and floor transitions, and make the debug panel scroll
f005593 Draggable monospace debug panel, bigger window, and honest perception counters
e8dead3 Add frame rate, fix the cursor readout and Tab picking, audit RUNNING.md
3c0ec3c Make the generated world inspectable: F1 cycles chronicle, factions, map
```

Sprint 3 proper (pathfinding, planner, reasoner, death loop) landed earlier and is already on
`dev` via PR #6. **It is in scope.** Use `git log --oneline main..HEAD` for the full picture.

### Files claimed as the Sprint 3 / 3.5 deliverable

| Path | Claimed role |
|---|---|
| `ecs/systems/grid_pathfinder.gd` | A* over the tile grid |
| `ecs/systems/locomotion_system.gd` | Two-tier movement (Active steers, Simulated advances) |
| `ecs/components/locomotion_component.gd` | Route state, survives LoD demotion |
| `ecs/systems/faction_planner.gd` | Objective → JobTemplate expansion (ADR-4) |
| `ecs/llm/llm_provider.gd` | Provider interface |
| `ecs/llm/heuristic_provider.gd` | **Default** reasoner, no network |
| `ecs/llm/openai_compatible_provider.gd` | Optional remote provider |
| `ecs/llm/prompt_builder.gd` | Lazy prompt + salience filter |
| `ecs/llm/reasoning_queue.gd` | One-in-flight queue |
| `ecs/systems/llm_resolution_system.gd` | The Validation Gate |
| `ecs/systems/death_loop_system.gd` | Death, corpse, Interregnum taxes |
| `ecs/world/lineage_journal.gd` | Cross-run persistence |
| `ecs/systems/reputation_system.gd` | **Sprint 3.5** — grievances, gossip |
| `ecs/components/faction_core_component.gd` | Ledger, diplomacy, objective |
| `ecs/world/floor_generator.gd` | Stairwell generation (modified) |
| `singletons/World.gd` | `change_floor`, `stairs_under` (modified) |
| `ui/debug/*` | Inspector, minimap, panel formatting |

---

## 4. CLAIMS — falsify these

Each claim has an ID. **Report on every one** with a verdict of `UPHELD`, `OVERSTATED`, `FALSE`,
or `UNVERIFIABLE`.

### Sprint 3A — movement

- **C-A1** Grid A* finds routes across open ground and around obstacles, and every returned
  waypoint is on a walkable tile.
- **C-A2** Every search is bounded by `MAX_EXPANSIONS`, and a search that exhausts its budget
  returns a *partial* route toward the closest node reached rather than nothing.
- **C-A3** Movement is four-way only, because a diagonal step across a solid corner is a move the
  AABB physically cannot make.
- **C-A4** Active movers are given velocity and collided by the same system that moves the player;
  Simulated movers advance analytically without collision.
- **C-A5** Steering never writes vertical velocity, so an NPC walking off a ledge still falls.
- **C-A6** Path planning is rate-limited per tick (`MAX_PATHS_PER_TICK`).
- **C-A7** Route state lives on a component, so a Simulated mover keeps its progress across a LoD
  demotion rather than restarting from its anchor.

### Sprint 3B — planner

- **C-B1** Objectives expand via a data-driven `JOB_TEMPLATES` table, not a search planner.
- **C-B2** Job count per faction is bounded by `MAX_JOBS_PER_FACTION`.
- **C-B3** A latched (in-progress) job is never overwritten by re-planning.
- **C-B4** Assigned destinations are always walkable tiles inside the faction's anchor chunk.
- **C-B5** Dead entities are not assigned jobs.
- **C-B6** The objective the reasoner chose is what the planner expands. `GameLoopManager` calls
  `planner.plan(core.current_objective, …)`, so a reasoner verdict of `FORTIFY` produces fortify
  work and not a default template. Falsify by making the reasoner return an objective and checking
  the jobs that appear.
- **C-B8** A faction that decided to raid a specific target actually marches on it:
  `MarchToTarget` resolves `core.objective_target` to that faction's anchor chunk. Until
  2026-08-01 `objective_target` was written by the resolver and read by nobody, so a raid sent its
  soldiers wandering around the attacker's own village. A raid with no named target musters at
  home rather than crashing.
- **C-B7** A worker whose `ProfessionComponent.profession` matches a job's preferred profession is
  given that job in preference to round-robin — and a faction of unqualified workers still gets
  jobs rather than stalling. (`FactionPlanner.PREFERRED_PROFESSION` was dead code until
  `_best_action_for()` was added; check the table is genuinely *read*, not merely declared.)

### Sprint 3C — reasoner

- **C-C1** The game reasons with **no endpoint and no API key configured**, and this is the
  default path exercised by CI — not a fallback.
- **C-C2** The queue stores entity ids only; the prompt is built at dispatch time, never at
  enqueue time.
- **C-C3** Exactly one request is in flight at a time.
- **C-C4** The queue is bounded (`MAX_PENDING`) and de-duplicates repeat submissions.
- **C-C5** A leader that dies while queued costs zero requests.
- **C-C6** The salience filter sends at most top-3-by-weight plus 3-most-recent, de-duplicated.
- **C-C6a** The reasoning cadence is WEEKLY (`HOURS_PER_STRATEGY_REVIEW = 168`, ADR-9), not
  hourly, with a crisis path so a faction attacked inside `ATTACK_MEMORY_WINDOW_HOURS` thinks
  immediately and then not again for `CRISIS_COOLDOWN_HOURS`. The queue is still pumped every
  macro tick — cadence governs who joins, not how fast it drains.
- **C-C6c** `ReasoningQueue._cache` is bounded by `MAX_CACHED`, evicting oldest-first. Unbounded
  until 2026-08-01: a prompt changes whenever the world does, so the "cost control" grew forever.
- **C-C6b** The salience ordering is TOTAL: `(weight, tick, event_id)` for the weight pass and
  `(tick, weight, event_id)` for the recency pass, so identical history selects identical
  memories no matter what order the history arrived in. **This was broken until 2026-08-01** —
  both sorts compared one field, and `sort_custom` is unstable, so ties changed *which* memories
  were selected, violating ADR-20 and silently missing the prompt-hash response cache.
  `FactionCoreComponent.prune_diplomacy` had the same defect and is fixed the same way. Hunt for
  a third instance: any `sort_custom` comparing a single field is a candidate.
- **C-C7** Valid target ids are enumerated explicitly in the prompt, and the player (Faction 0) is
  always among them.
- **C-C8** The Validation Gate applies identically to the heuristic and remote providers.
- **C-C9** Malformed output, timeout and refusal all arrive as one empty Dictionary, so there is
  no failure shape without a branch.
- **C-C10** A hallucinated or since-destroyed target is stripped and the raid cancelled.
- **C-C11** **CORRECTED 2026-08-01 — this claim was FALSE as originally written and an audit
  disproved it with a repro.** The rule is now: a failure of ANY kind (timeout, refusal,
  unparseable JSON — all arrive as one empty Dictionary per C-C9) leaves the objective, target,
  emotion and declaration exactly as they were. `FORTIFY` is the fallback only for a leader that
  DID answer and named a faction that does not exist. Previously every empty response forced
  `FORTIFY`, so a faction mid-raid abandoned it because the network was slow, and `on_timeout()`
  — the function implementing the claimed rule — had no caller at all.
- **C-C12** The remote provider is **refused** unless both endpoint and key are present, and the
  key never reaches a log or the overlay.

### Sprint 3D — death loop

- **C-D1** The corpse is a separate entity; row 0 never holds a corpse — **including through the
  damage paths a player actually dies from.** This was FALSE until 2026-08-01: a fatal fall or
  blow ran `ActionResolutionSystem._convert_to_corpse()` on row 0, tagging the reserved player row
  `Corpse`/`Filth` and stripping its behaviour bits before `DeathLoopSystem` ever ran, which then
  built a SECOND corpse from that mutated state. The function's doc comment said "for non-player
  entities" and there was no check. Attack this through `resolve_fall` and `resolve_melee`, not
  through `on_player_death` — that is how the tests missed it.
- **C-D2** Row 0's generation is *bumped*, not freed, so every stale handle fails validation and
  row 0 can never be handed to another entity.
- **C-D3** Control is severed before anything else.
- **C-D4** Carried possessions move into the corpse and lose their ownership.
- **C-D5** Death is detected in exactly one place, so all damage sources route through one handler.
- **C-D6** The Interregnum taxes **ledgers and counters only**, never entities. 60% of wealth
  survives; swarm counters clamp to 10 per chunk.
- **C-D7** Random junk sweeping draws from an RNG stream and is reproducible from a seed.
- **C-D8** The Lineage Journal carries insight and known runes forward and nothing else; merges
  take the higher insight per subject; a corrupt journal starts fresh; a newer-schema journal is
  refused rather than misread.
- **C-D9** The player's death is written into world history as a DAG event with an edge to the
  killer (`DeathLoopSystem._record_death_in_history`), so the death is part of the world's record
  and not only a UI message.
- **C-D9b** The death edge is `KILLED_BY(PLAYER_FACTION_ID, killer_faction)` — a registered
  `EdgeType`, pointing the way the event actually went. A death with no killer (a fall, drowning,
  starvation) is a self-loop rather than an edge to faction `-1`, because there is no node `-1`.
  **This was wrong until 2026-08-01**: it was `DESTROYED(player, killer)`, which under this
  graph's own convention (`CONQUERED(aggressor, victim)`) claimed the player had wiped out the
  killer's faction. Check the fix and check for other edges written with the direction reversed.
- **C-D11** A year away decays every faction's grievance score against the player toward neutral
  (`GRUDGE_RETAINED`), and updates the derived `status`, so a faction can cross back out of WAR.
  The grievance LIST is deliberately not cleared: they stop acting on it and still remember.
  Reputation against factions other than the player is untouched.
- **C-D10** Death suspends the tick hierarchy (`GameLoopManager.paused = true`) until the player
  presses `R`, so the world does not keep simulating around a corpse the player still controls
  nothing in.

### Stairs / floors

- **C-S1** Every landing chunk (0,0,z) has the stairs its depth allows — surface down-only,
  deepest up-only, middles both.
- **C-S2** Descending lands you on the *opposite* stair.
- **C-S3** The terrain sampler, the player's chunk id and the active chunk all move together on a
  floor change.
- **C-S4** **The spatial hash is filtered by floor.** Floors stack at the same world X/Z, so
  without this an NPC upstairs is a collision and perception neighbour of the player downstairs.

### Sprint 3.5 — consequences

- **C-P1** Combat *reports* a witnessable act; there is no global crime flag; perception decides
  who saw it via line of sight.
- **C-P2** A witnessed murder measurably lowers the witness faction's opinion of the offender's
  faction.
- **C-P3** Severity is a scale — murder costs materially more than theft.
- **C-P4** Witness confidence scales the reputation damage.
- **C-P5** Reputation is **per faction pair**; an uninvolved faction's opinion is unchanged.
- **C-P6** A faction files no grievance against itself.
- **C-P7** Grievance lists and faction memory are both bounded.
- **C-P8** Scores clamp to the registry's −100..100.
- **C-P9** The hostility crossing is announced exactly **once**, not on every subsequent crime.
- **C-P10** Gossip reaches someone who was not present, is deduplicated by `event_id`, carries
  only `core` memories, and is rate-limited per tick.
- **C-P11** A wronged faction actually changes behaviour — the reasoner returns `FORTIFY`.

### Cross-cutting

- **C-X1** 392 tests pass, gdlint is clean, and the boot sentinel prints with no errors.
- **C-X2** The window opens **maximized and windowed**, not fullscreen.
- **C-X3** No Godot physics node or `move_and_slide` appears in first-party code.
- **C-X4** `ecs/` contains no wall-clock reads.
- **C-X6** The same invariant enforces COMPONENT drift in both directions: every registry row
  without a `NOT YET IMPLEMENTED` or `STORED AS COLUMNS` marker has a class in `ecs/components/`,
  and every class there has a row. Adding this immediately found six drifts, four of which an
  audit had already reported and two of which it had not.
- **C-X5** `tests/invariants/test_forbidden_apis.gd` parses
  `docs/component_and_field_registry.md` and asserts every documented enum matches `ECSEnums`
  member-for-member and in order, so the registry cannot drift from the code in silence. Nothing
  enforced this before 2026-08-01, which is how a roadmap came to name an `EdgeType` that did not
  exist. Confirm the parse is not vacuous: add a member to any enum and check the test fails.

---

## 4b. DECLARED GAPS — things the spec asked for that are NOT implemented

The claims above are what I assert I built. This section is what I assert I did **not** build,
written down before you looked, so that a concealed omission and a declared one cannot be
confused. **Your job here is to prove this list is INCOMPLETE, not to rediscover what is on it.**

An item found missing that is already listed below is not a finding. An item found missing that is
**not** listed below is a MAJOR finding at minimum, because it means either the omission was
concealed or the implementer did not know about it. Report the difference between the two cases if
you can tell them apart.

### Sprint 3 spec requirements known to be absent

| # | Requirement | Where specified | Status |
|---|---|---|---|
| G-1 | A per-faction cap on concurrent Tier-3 (leader) reasoning requests, checked *before* enqueue | `sprint_3_technical_scaffolding.md` §7 / ADR-12 | **ABSENT.** `reasoning_queue.gd` bounds the queue globally (`MAX_PENDING`) and allows one request in flight, but never counts per faction. One faction can therefore fill the queue. |
| G-2 | A non-blocking "thinking" bark / Diplomatic Ping so the player sees that a leader is deliberating | `sprint_3_implementation_roadmap.md` review F1 | **ABSENT.** There is no UX surface for a pending decision at all. Reasoning is invisible except on the F1 debug page. |
| G-3 | The successor spawns at an "Adventurer's Residence" | `sprint_3_implementation_roadmap.md` Step 6 | **ABSENT.** The successor spawns at the same location the previous body started from. No residence structure exists in worldgen. |
| G-4 | `reason_summary` capped at 200 characters | `prompt_builder.gd:30` asks the model for it | **NOT ENFORCED.** The cap is requested in the prompt and never validated on the way back in. A remote provider returning 5 kB puts 5 kB in the overlay. |
| G-5 | Priority among weekly, crisis and diplomatic reasoning triggers | Implied by `llm_reasoner_and_planning_architecture.md`; never stated | **ABSENT.** The queue is strictly FIFO, so a faction under attack waits behind routine weekly thinking. |
| G-6 | A Sprint 3 performance gate — which scenario and metric prove `death → respawn ≤ 5 s` and that the queue stays inside the tick budget | `scope_and_milestones.md` states the budget; no sprint doc assigns a test | **ABSENT.** No sprint-owned performance failure signal exists for anything Sprint 3 added. |

### Sprint 3.5 — the nine named items, honestly

Sprint 3.5's whole specification is one table row naming nine things. Here is each one:

| Item | Status | Evidence |
|---|---|---|
| Grievance accumulation | **IMPLEMENTED** | `ecs/systems/reputation_system.gd`, claims C-P1..C-P9 |
| Job_Chat gossip | **IMPLEMENTED UNDER ANOTHER NAME** | `ReputationSystem.spread_gossip()` moves `core` memories between neighbours. There is no job named `Job_Chat` and no chat *job* in `JOB_TEMPLATES`; gossip is a system pass, not work an NPC is assigned. Judge whether that substitution is acceptable. |
| Profession assignment | **IMPLEMENTED** | `FactionPlanner._best_action_for()`, claim C-B7. Note this was dead code until this change set. |
| War-time job generation | **PARTIAL** | `JOB_TEMPLATES` has entries for hostile objectives and `HeuristicProvider` returns `FORTIFY` when attacked (C-P11). There is no distinct war*time* state, no mobilisation, no draft. |
| Loyalty | **FIELD ONLY** | `SocialIdentityComponent.loyalty` is declared in the registry and set at spawn. **Nothing reads it.** |
| Prestige | **FIELD ONLY** | `SocialIdentityComponent.prestige` — same. Declared, never read. |
| Succession by prestige | **ABSENT, AND FULLY SPECIFIED** | No code path selects a new faction leader. Grep `succession` in `ecs/` returns nothing; a faction whose leader dies simply has no leader. Unlike the rest of this table, this one has a real spec — `factions_and_social_mechanics_architecture.md:50-56` gives the selection rule (highest `prestige` among Tier 2), the component grant (`LLMPromptComponent`), and the follow-on (queue a Reasoning Tick for the new agenda). "The spec was vague" is not available as an excuse here. Treat this as the most damning row in the table. |
| ClaimTags | **ABSENT** | No `ClaimTag` component, tag, or field exists anywhere. Specified only as "factions exert influence over zones via ClaimTags" — no placement, validation, or challenge mechanics. |
| Caravans | **NAME ONLY** | `caravan` appears solely as a `MaterializationPolicy` enum value from an earlier sprint. No caravan entity, route, or trade exists. The architecture doc does specify behaviour (form from Tier 2, load surplus from the `InventoryZone`, pathfind to the ally's zone, physically interceptable); the routing cadence is what is missing from the spec. |

**My own verdict, stated so you can disagree with it on the record:** calling this "Sprint 3.5
implemented" is **overstated**. Three of nine items are genuinely built, one is built under a
different shape than named, one is partial, two exist as unread fields, and two do not exist. The
commit message says "implement Sprint 3.5: consequences" — *consequences* is the honest scope, and
the sprint's title is not. If you conclude otherwise, say why.

| G-7 | Schism, Trade Mission jobs, and territorial Brawls | `factions_and_social_mechanics_architecture.md`; Sprint 3.5 scope row | **ABSENT.** No schism path, no trade objective in `JOB_TEMPLATES`, no skirmish over neutral resources. §4b's first version drew its nine-item table from the scope row alone and missed these; an audit caught the omission. |
| G-8 | The leader prompt should include relevant active `MemoryComponent`s, not only `FactionCoreComponent.faction_memory` | `sprint_3_implementation_roadmap.md` Step 2 | **ABSENT.** Only faction memory is read, so a Tier-2 member's significant memory never reaches the leader unless something summarised it first. |
| G-9 | `public_declaration` is stored in the leader's `MemoryComponent` so gossip can repeat it | `llm_reasoner_and_planning_architecture.md` | **ABSENT.** Only `core.last_declaration` is written, so the overlay can show it once and nobody can ever repeat it. |

### Ambiguities resolved by choosing, and the choice recorded

Not gaps — decisions the spec left open where the implementation had to pick. Each is a fair
target if you think the choice is wrong; none is a concealment.

| Ambiguity | The two readings | Chosen, and why |
|---|---|---|
| Interregnum grievance decay: "60-75% toward neutral on each Interregnum pass", where a pass is one of 12 months | per-month, or once across the year | **Annual**, retaining 30%. Per-month compounds to `0.4^12 = 1.7e-5` at the gentle end — a faction that watched you murder its people forgets completely, and the consequence layer resets on every death. The arithmetic decides it. |
| Swarm cap: "cap all Tier 1 Swarm populations (Rats, Spiders) to a maximum of 10 per chunk" | 10 per species, or 10 total | **10 total**, in `ChunkData.swarm_population`. The registry defines exactly one counter; a per-species cap would need `ZonePopulationComponent.population_by_species`, which nothing in Sprint 3 populates. |
| `Job_Chat` gossip | a job NPCs are assigned, or a system pass | **A system pass** (`ReputationSystem.spread_gossip`). No `Job_Chat` exists in `JOB_TEMPLATES`. Judge whether the substitution is acceptable. |

### Known open issue not introduced by this change set

ADR-10's frame budget is 8 ms. The measured cost at 1,500 entities is 13.7 ms. Sprint 3 adds
pathfinding and a reasoning queue on top of an already-missed budget, and no spec addresses that.
`STATE.md` records this. It is listed here so you do not spend time proving a known miss — but
quantifying **how much of the 13.7 ms this change set added** would be a genuinely useful finding.

---

## 5. Procedure

### Pass 1 — Reproduce the baseline
Run everything in §1. Record actual numbers. Any divergence is finding #1.

### Pass 2 — Attack the tests, not the code
This is the highest-value pass, because every claim above is backed by tests the implementer
wrote. For each test file in §3:

- **Does it assert anything that could fail?** Look for tests that would pass against a stub.
- **Is it vacuous under some condition?** e.g. a loop asserting over a collection that may be
  empty, with no assertion that it is non-empty.
- **Does it test the claim, or a restatement of the implementation?** A test that asserts
  `CONSTANT == CONSTANT` proves nothing.
- **Mutation-test the important ones.** Break the implementation deliberately — invert a
  comparison, delete a clamp, remove a `continue` — and confirm the test fails. **A test that
  still passes with the logic broken is a finding.** Revert every mutation.

Prioritise mutation-testing: **C-A2, C-C10, C-D2, C-D6, C-P5, C-P9, C-S4.** These are where a
false pass is most expensive.

### Pass 3 — Boundaries and unbounded work
Find every loop, queue, list and dictionary added by this change set. For each, identify what
bounds it. Report anything unbounded, and anything bounded only by a value that grows.

### Pass 4 — Run the thing
Boot the world scenario and use it (`RUNNING.md` has the controls). Specifically try:
`K`×4 then `R` (death and rebirth), `E` on the stairwell, `F1` through all five pages, killing a
villager in view of another. **Report anything that reads as broken to a player**, whether or not
a test covers it.

### Pass 5 — Spec conformance, one way only
For each Sprint 3 roadmap Step and each numbered section of `sprint_3_technical_scaffolding.md`,
does the implementation deliver what it asked? Report *missing* deliverables and *unrequested*
additions. Do not report that the spec was vague — that is the other auditor's finding.

### Pass 6 — Audit the declared gaps (§4b)
§4b is my own list of what I did not build. Do not take it on trust and do not merely re-derive it.

1. **Verify each declared gap is real.** If something listed as ABSENT actually exists, that is a
   finding — I was wrong about my own code.
2. **Prove the list incomplete.** Walk the specs independently and find a requirement that is
   neither in §4 (claimed) nor §4b (declared missing). Every such item is a MAJOR finding.
3. **Judge the Sprint 3.5 verdict.** §4b concludes "overstated". Agree or disagree, with reasons.
4. **Hunt for more dead code of the `PREFERRED_PROFESSION` kind** — a constant, field, or function
   that is declared and documented as if it works but is never read. `SocialIdentityComponent`'s
   `loyalty` and `prestige` are two I already found and declared. Find the ones I did not. Grep
   each public symbol added by this change set for a second reference; one reference means the
   declaration is its only appearance.

---

## 6. Output

Write **one Markdown file** to:

```
docs/audits/OUTPUT-AUDIT-RESULT--<AGENT_SLUG>--<UTC_TIMESTAMP>.md
```

Same rules as the input audit: `<AGENT_SLUG>` identifies model **and** harness
(`gpt5-codex`, `gemini3-aider`, …); `<UTC_TIMESTAMP>` is `YYYYMMDD-HHMMZ`. Do not overwrite an
existing file.

Example: `docs/audits/OUTPUT-AUDIT-RESULT--gpt5-codex--20260801-0645Z.md`

### Required structure

```markdown
# Implementation Audit — Sprint 3 & 3.5
Auditor: <model> via <harness>
Commit audited: <git rev-parse --short HEAD>
Date (UTC): <timestamp>

## Reproduction
| Check | Claimed | Observed |
|---|---|---|
| Test scripts | 28 | |
| Tests passing | 392 | |
| gdlint | clean | |
| Boot sentinel | present | |

## Verdict
<Three sentences maximum.>

## Claim ledger
| ID | Verdict | Evidence |
|---|---|---|
| C-A1 | UPHELD / OVERSTATED / FALSE / UNVERIFIABLE | file:line, or the command you ran |
<...every claim in §4...>

## Findings
### [SEVERITY] <short title>
- **Claim affected:** <C-xx, or NEW if it is outside every claim>
- **Where:** `<file>:<line>`
- **Evidence:** <command output, or the mutation you applied and the test result>
- **Failure scenario:** <concrete inputs or player actions → wrong outcome>
- **Severity rationale:** <why this severity>

## Vacuous or weak tests
<Tests that pass without proving their claim. Name the mutation that survived.>

## Unbounded work
<Every loop/queue/collection with no effective bound.>

## Declared-gap audit (§4b)
| Declared gap | Really absent? | Notes |
|---|---|---|
| G-1 .. G-4, and each of the nine Sprint 3.5 items | yes / NO — it exists at file:line | |

### Undeclared gaps found
<Requirements in the specs that appear in NEITHER §4 nor §4b. This is the section I most want
filled. Empty is an acceptable answer if you looked and found none — say that you looked.>

### Dead code found
<Symbols declared and documented but never read, beyond the three already declared.>

## Sprint 3.5 scope assessment
<Your plain judgement. §4b says "overstated" — agree or disagree, with reasons.>

## What is genuinely well built
<Required. At least three specifics. An audit with no positive findings is not calibrated.>
```

### Severity definitions

- **BLOCKER** — violates §2; or loses/duplicates state; or a claim in §4 is FALSE; or it crashes.
- **MAJOR** — a claim is materially OVERSTATED; or an invariant holds only in tests; or unbounded
  work will degrade a real session.
- **MINOR** — cosmetic, or a defect with no reachable consequence.

---

## 7. Rules of engagement

1. **Evidence before assertion.** Every finding carries a command, an output, a file:line, or a
   surviving mutation. "This looks wrong" is not a finding.
2. **Revert every mutation you make.** Leave the tree clean; `git status` must be empty when you
   finish, apart from your output file.
3. **Do not fix anything.** Report only. A fix hides the evidence of the defect.
4. **Assume the implementer's comments are marketing.** The code is heavily commented with
   rationale. Those comments are *claims*, not proof. Several describe bugs the implementer
   themselves introduced and then fixed; check the fix rather than trusting the story.
5. **The implementer has a known pattern of building machinery and not connecting it.**
   `PerceptionSystem.report_crime` existed for two sprints with no caller. Actively hunt for other
   functions, signals and systems that are defined, tested in isolation, and never invoked in the
   real tick. Grep for callers of every public method added in this change set.
6. **A green suite is not evidence of correctness.** It is evidence that the implementer's own
   assertions agree with the implementer's own code.
