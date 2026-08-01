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

**Expected at the audited commit: 28 test scripts, 364 tests, 0 failures, gdlint clean.**
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

### Sprint 3C — reasoner

- **C-C1** The game reasons with **no endpoint and no API key configured**, and this is the
  default path exercised by CI — not a fallback.
- **C-C2** The queue stores entity ids only; the prompt is built at dispatch time, never at
  enqueue time.
- **C-C3** Exactly one request is in flight at a time.
- **C-C4** The queue is bounded (`MAX_PENDING`) and de-duplicates repeat submissions.
- **C-C5** A leader that dies while queued costs zero requests.
- **C-C6** The salience filter sends at most top-3-by-weight plus 3-most-recent, de-duplicated.
- **C-C7** Valid target ids are enumerated explicitly in the prompt, and the player (Faction 0) is
  always among them.
- **C-C8** The Validation Gate applies identically to the heuristic and remote providers.
- **C-C9** Malformed output, timeout and refusal all arrive as one empty Dictionary, so there is
  no failure shape without a branch.
- **C-C10** A hallucinated or since-destroyed target is stripped and the raid cancelled.
- **C-C11** A timeout preserves the current objective rather than changing it.
- **C-C12** The remote provider is **refused** unless both endpoint and key are present, and the
  key never reaches a log or the overlay.

### Sprint 3D — death loop

- **C-D1** The corpse is a separate entity; row 0 never holds a corpse.
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

- **C-X1** 364 tests pass, gdlint is clean, and the boot sentinel prints with no errors.
- **C-X2** The window opens **maximized and windowed**, not fullscreen.
- **C-X3** No Godot physics node or `move_and_slide` appears in first-party code.
- **C-X4** `ecs/` contains no wall-clock reads.

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
For each Sprint 3 roadmap Step, does the implementation deliver what the Step asked? Report
*missing* deliverables and *unrequested* additions. Do not report that the spec was vague — that
is the other auditor's finding.

### Pass 6 — Sprint 3.5 scope honesty
Sprint 3.5's specification names nine things (see the other manifest, §3). The implementation
claims grievances and gossip. **Enumerate all nine and state which are implemented, which are
partially implemented, and which are absent.** Then judge: is calling this "Sprint 3.5
implemented" honest, overstated, or false? Say so plainly.

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
| Tests passing | 364 | |
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

## Sprint 3.5 scope assessment
<The §6 enumeration and your plain judgement on whether the claim is honest.>

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
