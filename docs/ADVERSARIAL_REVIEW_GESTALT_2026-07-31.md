# Gestalt Adversarial Review — 2026-07-31 (final pre-implementation round)

**Status:** Applied. This is the resolution log for the final end-to-end review before Sprint 0
and Sprint 1 implementation. Findings are retained as the pre-repair record; §7 lists what was
applied where.

**Authority:** This document is HISTORICAL and NON-BINDING, like the three earlier review logs.
`docs/architecture_decisions.md` and `docs/component_and_field_registry.md` remain the only
authoritative documents.

## 1. What made this round different

The three earlier review rounds were **document reviews** — they read the specs against each
other. None of them executed anything. This round ran the specs against **Godot 4.7.1 itself and
against actual numbers**, and that is where every blocker below came from. Two of the earlier
rounds' own "resolved" fixes turn out to be broken (see F1 and F14).

Six independent reviewers, deliberately non-overlapping:

| Lens | Scope |
|---|---|
| Implementability | Would a coding agent get stuck, guess, or produce something wrong? |
| Consistency & drift | Contradictions against the ADR and the registry |
| Math & algorithms | Do the formulas and algorithms actually work, with worked numbers? |
| Gestalt | Scope, sequencing, risk, is there a game at the end |
| **Competing panel A** | Independent verdicts on the controversial items, with measurement |
| **Competing panel B** | Independent verdicts on the same items, answered separately |

Panels A and B were given the same controversial questions and no knowledge of each other's
answers, per the requirement that controversial recommendations be judged by competing but
otherwise neutral reviewers. Both were told Sprint 0 and Sprint 1 ship in full, so scope-cutting
was off the table and the questions reduced to build order and what the specs should say.

## 2. BLOCKERS — verified by execution, not inference

### F1 — `EntityHandle` as a `RefCounted` cannot be a Dictionary key
Every component registry in the specs is written as `{ EntityHandle: Component }`. GDScript
`RefCounted` hashes by **object identity**, so this silently does not work:

    d[HandleRC.new(5,1)] = "A"
    d.has(HandleRC.new(5,1))  -> false
    d.size()                  -> 2        # a duplicate key was created
    a == b                    -> false

Confirmed independently three times (lead, implementability reviewer, panel A). Panel A
established two further facts: a script-defined `hash()`/`_eq()` is **ignored** by `Dictionary`
(so custom hashing is not a tradeoff, it is impossible), and the bug is **latent** — passing the
same object through a signal works, so early Sprint 1 tests all pass. It fails only on
*reconstruction*: save/load, test fixtures, the debug console.
Corollary: `EntityHandle.invalid()` allocates per call, so `target == EntityHandle.invalid()` is
**always false**, breaking every "has a target?" check.
→ **ADR-19.** Handles are packed 64-bit ints.

### F2 — Fluid CA: double buffering plus a sparse dirty set annihilates every settled puddle
The two mechanisms are mutually exclusive. Double buffering requires writing every cell each
tick; a sparse set writes only the dirty subset; after the swap, non-dirty cells read two-tick-old
data. A settled 100-unit puddle is simply gone on the first tick it stops being dirty. The full
4096-cell copy this was avoiding costs **0.236 µs**, so the premise was false anyway.
→ Single buffer + delta accumulator. Sprint 1 §5.

### F3 — No flow rule existed; the natural integer rule never terminates and leaks mass
With A=1, B=0 at equal elevation, "push to the lower neighbour" gives a permanent 2-cycle, so
those cells stay dirty forever and every puddle edge becomes a permanent budget consumer.
Integer redistribution also either destroys matter (`share = V/4` then zero the source) or
fabricates it (`ceil`, ~1.2M units/second at budget).
→ `FLOW_MIN_DIFF = 2` hysteresis with floor division. Provably terminates, exactly conservative.

### F4 — Flat-array neighbour probes wrap rows and run off the end
`x=63,y=0 -> idx 63`, and `idx+1 = 64` is `x=0,y=1` on the far side of the chunk.
`x=63,y=63 -> idx 4095`, and `idx+1 = 4096` is out of range on a 4096-element array. Affects the
CA, the collision DDA, and LoS. Every Active/Active chunk seam is affected, a case the Flood
Buffer (an Active→Simulated mechanism) does not cover.
→ Mandatory 1-cell ghost apron, stride 66, plus a `world_tile()` accessor.

### F5 — The ADR-10 CA budget does not fit, by measurement
20,000 cell-updates/Micro tick costs **7.3 ms** (M5 Max) and **~13.1 ms** on ADR-10's own
M1 reference — 164% of the entire 8 ms budget before anything else runs. Panel A independently
measured a fused micro tick and reached the same conclusion by a different route: CA is **68% of
the fused cost** at K=20,000, GDScript's ceiling is ~4,700 cell-updates/ms, and it is
memory-bound, so optimization moved it only 8% (4.56 → 4.20 ms) while the same effort halved the
entity loop.
→ Fluids move to a 15 Hz cadence at 12,000 updates/fluid-tick. 20,000 survives only as the
post-GDExtension target. **Both panels agree the CA Rust port should be pre-committed, not a
contingency, and that the entity caps should NOT be lowered** — entities are cheap (2.05 ms for
3,000 fully optimized); CA is what must give.

### F6 — Combat math is broken five ways
`impact_force = |velocity| * (weapon_mass_kg + strength)`, kill at `mass * density * TOUGHNESS`:
1. m/s × kg is **momentum**, not force.
2. Adds a dimensionless stat to kilograms; at baseline strength is 87% of the term, so weapon
   choice barely matters.
3. `mass × density` double-counts density — mass is *already* volume × density.
4. `|velocity|` is the attacker's **body** velocity, so a stationary player deals exactly **zero**,
   making Sprint 1 Step 6's own success state unreachable.
5. Boolean kill test with **no bridge to `health`**, which both roadmaps describe reaching 0.
At K=400 every unarmoured human is one-shot and a 200 L water barrel is 1.6× tougher than a
plate-armoured knight. The valid band for the constant was 277 < K < 82,143 — it constrained
nothing. `TOUGHNESS_CONST` had no value anywhere in the repo.
→ Kinetic-energy model, Sprint 1 §10, verified against rat / human / knight / boulder.

### F7 — Perception is 65 ms in a single Simulation tick
A DDA LoS march is 2.77 µs on M1. At the ADR-10 target of 1,500 active entities each observer has
~16 post-FOV candidates → 23,436 marches per Sim tick → **65 ms in one frame, twice per second**
(a 4-frame hitch). At the 3,000 hard cap, 260 ms.
→ Awareness tiering, `MAX_CANDIDATES_PER_OBSERVER = 8`, symmetric LoS cache, sector pre-reject,
Micro-tick amortization → ~0.09 ms/frame.

### F8 — Sprint 1 has no world to collide with
Sprint 1 needs `tile_map` in five places (collision DDA, pick DDA, LoS, grid A*, the fluid grid's
host chunk). `ChunkData`, `WorldGrid`, and `tile_map` are defined **only in Sprint 2**.
→ Sprint 1 owns a hand-authored test-arena chunk; Sprint 2's generator becomes the producer. The
consumer contract does not change.

### F9 — The CI lint step never executes
`ls "$d"/**/*.gd "$d"/*.gd` — bash `globstar` is off in Actions, so `**` degrades to `*`, and
`ls` returns non-zero if *any* pattern fails to match, short-circuiting the `&&`. Reproduced
against the exact mandated tree: gdlint was **skipped for `ecs` and `singletons`** although both
contained `.gd` files. Also verified in the real image: it has **no python3 and no pip3 at all**,
and its Ubuntu 24.04 base is PEP-668 externally-managed, so the bare `pip3 install` fails with
`error: externally-managed-environment`.
→ `find`-based guard, `--break-system-packages`, gdtoolkit pinned 4.5.*.

### F10 — GUT exits 0 having run zero tests, via three separate paths
(1) missing import → `quit(0)` with `Missing class_names`; (2) empty test dir → `Nothing was run`,
exit 0; (3) **`-gdir` does not recurse** — a deliberately failing test in `tests/unit/` was never
seen and the run reported "All tests passed". The roadmap warned only about the `test_` filename
prefix and missed all three.
→ `--headless --import`, `-ginclude_subdirs`, JUnit XML, and a hard failure if the parsed test
count is 0.

### F11 — The boot smoke test cannot fail
A `Main.tscn` whose `_ready()` throws a hard runtime error still exits 0, so "main must always run
flawlessly" was entirely unenforced.
→ `ECS_BOOT_OK` sentinel plus a grep for `SCRIPT ERROR`.

### F12 — Component pseudo-code cannot compile as written
`class X extends RefCounted:` inside a file is an **inner class** and registers no global
identifier, yet every doc writes the bare name as a type. Registry §3's nine enums are listed with
**no owning file**, and a cross-file enum without `class_name` is unreachable. `ECSEvents.gd`'s
snippet has no `extends Node`, so Godot refuses to autoload it. Also verified: `class_name`
globals do not resolve at all until the project is imported.
→ One file per component with a top-level `class_name`; an `ECSEnums` holder; `extends Node` on
all three singletons.

### F13 — Six invented `Objective` enum values across six docs
`CONQUER`, `MILITARIZE`, `Request_Resource`, `RAID`, `RAID_FLOOR_4_FOR_FOOD`, plus a `VENGEFUL`
emotion and a string target where the Validation Gate requires an integer faction id. Six of the
eight objective mentions outside the registry would fail the project's own content-validation gate
(`content_authoring §164`: "Objective must be in the registry enum"). `MILITARIZE` was the sole
worked example of the LLM→workforce-ratio mechanic; `Request_Resource` the sole driver of the
Bounty Board.

### F14 — Seven authoritative docs and root `CLAUDE.md` were untracked in git
`git ls-files docs/` returned 31 of 38 files. On a fresh clone, five README links dangle, four
docs the ADR declares authoritative are absent, and `copilot-instructions.md` is a **dangling
symlink**. The earlier review round created root `CLAUDE.md` and marked the fix applied — but
never committed it, so the fix did not exist for anyone else.

### F15 — JSON cannot hold this save payload
The persistence spec mandates a JSON root **and** saving 64-bit RNG stream states. Godot's JSON
parses every number as a double. Verified: state `-5247995915623386297` → `-5247995915623386112.0`,
and the restored stream produces `0.94077587` where `0.93109381` was expected. ADR-8's single
promise is silently violated. `var_to_bytes` and `var_to_str` both round-trip exactly.
→ **ADR-21.**

## 3. Competing-panel verdicts on the controversial items

Both panels were neutral and answered independently. Where they diverged, the divergence is
recorded rather than smoothed over.

| Item | Panel A | Panel B | Resolution |
|---|---|---|---|
| Packed-int handles (F1) | ADOPT WITH MODIFICATION — `INVALID = 0`, not `-1`; and fix the registry *shape*, not just the key | (not asked) | Adopted with A's corrections |
| Query façade backed by a simple index | ADOPT WITH MODIFICATION — the façade must return **row indices**, not handles, or the later swap is impossible | (not asked) | Adopted A's contract |
| Demote the LLM to optional | **ADOPT** (high confidence) | (not asked) | Adopted — see below |
| Defer mid-run save | ADOPT WITH MODIFICATION — keep a headless round-trip **test** in Sprint 1; discipline without an executing test is not discipline | (not asked) | Adopted A's modification |
| Lower the ADR-10 caps | **REJECT** — entities are cheap; cut CA instead | (not asked) | Rejected |
| Force an art decision before Sprint 2 | ADOPT WITH MODIFICATION — this is a **schema/scope** defect misdiagnosed as an art defect; Sprint 2 has no art dependency | (not asked) | Adopted A's reframing |
| Force a playable slice / reorder Sprint 1 | (not asked) | **ADOPT WITH MODIFICATION** — but the premise "first playable arrives after Sprint 4" is **false**; Sprint 1 as written already ends playable. The real defect is the absence of a *judgment* step | Adopted B's correction |
| Add a scope/milestones doc | (not asked) | ADOPT WITH MODIFICATION — a must/nice/graveyard doc is the wrong shape; use a **block rule** (spec work gated behind code), which is enforceable, instead of a trade rule, which is not | Adopted B's version |
| tunables.json + slider panel | (not asked) | ADOPT WITH MODIFICATION — the slider is the low-value half; typed hot-reloadable data with a trace on every reload is what matters, and material properties belong to the **content** pipeline, not tunables | Adopted B's split |
| 5-second launch budget | (not asked) | **REJECT** the number — it optimizes the loop you should be skipping. Budget the debug scenario (≤2 s), cold boot (≤30 s), and the **unbudgeted death→respawn transition** (≤5 s) | Adopted B's three budgets |

**On the LLM (panel A's strongest argument, which the original proposal missed):** ADR-5's own
Validation Gate and Fallback Matrix **already require a fully working no-LLM path** — on timeout
the faction maintains its objective; on invalid JSON or a hallucinated target it defaults to
`FORTIFY`. So the game must already be correct when every LLM response is discarded. A heuristic
objective selector is therefore *pre-existing obligated work*, not new competing scope. The
current specified fallback ("always FORTIFY") is not a fallback, it is a stall. The LLM's entire
mechanical decision space is ≤240 discrete outcomes chosen about once per faction per 28 real
minutes; only `public_declaration` prose is genuinely LLM-shaped.
**Recorded as a recommendation for the human, not applied.** It changes the product's identity and
ADR-5 is a human decision. Everything else in this document has been applied.

**Where the panels disagreed with the originating reviewers** — recorded because it is the point
of the exercise:
- Panel B **refuted** the gestalt reviewer's headline claim that nothing is playable until after
  Sprint 4. Sprint 1 Step 4 plus §9 plus Step 6 already yield a controllable player in a collided
  room killing a rat with a following camera.
- Panel A **refuted** the "possibly off by an order of magnitude" framing of the perf risk;
  measured reality is ~1.5–2.5× over budget on reference hardware. Overstating it invites the
  whole finding being dismissed.
- Panel A **corrected the lead's own `INVALID = -1`**, which is a hard parse error when
  constant-folded. Verified.

## 4. Verified unowned specification — the largest structural gap

Nobody had noticed this. A grep of every `docs/sprint_*.md` returns **zero** hits for `scarcity`,
`price`, `barter`, `merchant`, `recipe`, `forge`, `EconomySystem`, `ClimateSystem`, `weather`, and
no UI hits outside Sprint 0's folder tree. Independently re-verified by the lead.

- **The entire economy has no owning sprint** — no scarcity index, no price formula, no barter, no
  merchants, no crafting stations, no forges, no recipes. The Day-0 walkthrough is literally a
  shopping trip.
- **Faction politics has no owning sprint** — loyalty, schism, succession, caravans, grievances,
  war-time job generation, gossip propagation, profession assignment. Without them Sprint 3 ships
  an LLM emitting `RAID_FACTION` into a world with no soldiers, no loyalty, and no succession.
- **~420 lines of player-facing UI across three specs have no owning sprint.**
- Also unowned: climate/weather, the Bounty Board, encumbrance, sub-containers, muscle-memory
  progression.
→ `docs/scope_and_milestones.md` §6 assigns all of it, including new Sprints 2.75, 3.5, and U.

## 5. Design defects found (not merely spec drift)

- **Inherited hostility, un-inherited competence.** ADR-14 fixes Player = Faction 0 permanently
  and diplomacy toward Faction 0 survives the Interregnum, while the new adventurer resets to
  novice. So adventurer #4 can spawn inside village limits, at 06:00, with a rusted dagger, into a
  faction already at War — unwinnable, and reachable in a single run. → reputation decay + a
  neutral floor on the spawn faction.
  Panel B also **refuted** the broader "death spiral" claim: the 40% interregnum entropy tax, the
  ADR-12 faction cap, DAG compaction, and the gray-box vacuum effect all actively *de*-consolidate
  factions each year, and insight carries forward. The defect is narrow and precise, not general.
- **The Tactical Lens gate is inverted** — it is the designated teaching tool and it is gated
  behind the very insight a new player lacks. → gate *detail*, never *presence*: Insight 0 must
  still show "Liquid — reacts to cold", never just "Liquid".
- **Utility AI is a priority ladder, not utility AI.** The weights are algebraically inert
  (`(h/100)*2.0 > 1.5` is just `h > 75`), the two urgencies are never compared, and Sleep is
  unreachable while hungry — an NPC at hunger 76 / energy 0 returns `Consume` forever. With no job
  latch it re-issues a path request twice a second for a 10-second walk: 1,500 NPCs × 2 Hz = 3,000
  requests/s against NavBridge's 300/s, a **10× overrun** that grows unboundedly.
- **Memory decay collapses.** The additive core bonus drives every core memory to the same weight
  (12 memories all weighing 5.0098), so "top-3 by weight" becomes float-noise ordering. Decay had
  two contradictory definitions differing by 720× across an Interregnum, and no cap existed while
  gossip *unions* memory lists with no dedup key (200 NPCs × 30 events → 1.2M records).
- **Acoustic encumbrance has no cap** despite claiming one; `log10` is unbounded, undefined on an
  empty inventory, and returns negative radii.
- **`Add_Temperature(1000)` melts your sword and warms you by 4 °C** — distributing energy over
  *total* mass is wrong for a surface effect. No latent heat either, so 1,000 kg of water at
  99.9 °C flash-boils entirely on 1 kJ.
- **Explicit heat conduction has no stability bound.** At K=60 it becomes a perfect 2-cycle that
  looks stable (energy is conserved) while flickering ICE↔GAS 30×/second; at K=150 it reaches
  ±3.2M °C in 0.13 s.
- **Composition fractions had no declared basis.** The mass formula is a volume-weighted mean, so
  fractions must be volume fractions; read as mass fractions the error is **96%**.
- **Gold supply has one sink.** +50/Macro tick = 432,000/real-hour across 24 factions, sunk only
  by the 40% tax at player death → steady state ~648,000 gold/faction.
- **Entity-vs-entity collision was specified nowhere**, so no projectile could ever hit anything;
  and with no substep rule a 50 m/s projectile moves further per tick than a rat's whole AABB.

## 6. Process finding

Three review documents totalling ~1,400 lines — 21% of the spec corpus — describe the corpus
rather than the game, and one exists solely to review another's repairs. Meanwhile the specs
contained a handle type that cannot survive a round trip, a CA that deletes puddles, a combat
formula that cannot hurt anything while standing still, a CI lint step that never runs, and a test
runner that reports success having run nothing. **Reading specs against each other cannot find any
of that. Executing them finds all of it in an afternoon.**
Two prior "resolved" fixes were themselves broken: root `CLAUDE.md` was created but never
committed, and generational handles — adopted partly to stop dict-key churn — were given a shape
that makes every registry write leak a duplicate.
→ `docs/scope_and_milestones.md` R1/R2: spec work is gated behind code, and at most one open
review at a time.

## 7. Where each finding was applied

| Finding | Applied in |
|---|---|
| F1 handles | **ADR-19** (new), registry §1, Sprint 1 §9 |
| F2–F4 fluid CA | Sprint 1 §5, registry §6 (`ChunkData` owns the buffers + dirty set) |
| F5 CA budget | **ADR-10** (corrected by measurement), Sprint 1 §5 |
| F6 combat | Sprint 1 §10 |
| F7 perception | Sprint 1 §11, ADR-10 |
| F8 test chunk | registry §6, Sprint 1 §5 |
| F9–F11 CI | Sprint 0 scaffolding §2 (R1–R7), invariants Sprint 0 gate |
| F12 compile shape | Sprint 0 scaffolding §4, invariants gate |
| F13 objectives | entity_behavior, factions, world_bootstrapping, game_vision, sprint_3 |
| F14 git | committed; STATE.md corrected; `dev` fast-forwarded to `main` |
| F15 save format | **ADR-21** (new), persistence spec §2 |
| World scale, bounds, movement law | **ADR-18** (new) |
| Wall-clock ban + soak harness | **ADR-20** (new) |
| Material seed data | material doc §2 (density, heat capacity, phase points, acoustics) |
| Unowned specification | README §4, **`docs/scope_and_milestones.md`** (new) |
| Design defects (§5) | the owning system docs |
| LLM demotion | **NOT applied** — recorded for the human; ADR-5 is a product decision |
