# Implementation Audit Manifest — Sprint 4 ("The Crucible")

**Audience:** an independent auditor, human or model, with the repository and a Godot 4.7.1
toolchain. **Written by the implementing agent**, which is exactly why it needs checking by
somebody else.

Commit under audit: the head of `feature/sprint4-the-crucible`.

---

## 0. FILES TO IGNORE

Anything matching these patterns is audit apparatus, not implementation, and must be excluded
from every judgement below — including "is this documented", "is this dead code", and any count
of files changed:

```
docs/audits/INPUT-AUDIT-RESULT--*.md
docs/audits/OUTPUT-AUDIT-RESULT--*.md
docs/audits/TRIAGE--*.md
docs/audits/OUTPUT-IMPL-AUDIT-*.md
```

This file is one of them. Do not audit the manifest against itself.

---

## 1. Reproduce the baseline first

If any of these disagree, stop and report that before anything else — every claim below is
conditional on them.

| Check | Command | Claimed |
|---|---|---|
| Import | `godot --headless --import` | clean, no `SCRIPT ERROR` |
| Tests | `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` | **32 scripts, 506 tests, 506 passing** |
| Lint | `gdlint ecs singletons ui viewer tests` | clean |
| Boot | `timeout 60 godot --headless --quit-after 200 res://viewer/Main.tscn` | prints `ECS_BOOT_OK` |

`-ginclude_subdirs` is required. Without it `tests/invariants`, `tests/perf` and `tests/soak` are
silently skipped and the run reports green having never opened them.

---

## 2. What Sprint 4 was asked to build

`docs/sprint_4_implementation_roadmap.md`, five steps: advanced chemistry and chain reactions;
the spell compiler; ephemeral casting; biological mutation and the faction shift; and Step 5, the
Tab-toggle playability defect carried over from Sprint 3. Plus `docs/scope_and_milestones.md`,
which assigns Sprint 4 "chemistry reactions, spell compiler **plus the Grimoire UI that fronts
it**".

The roadmap and the scaffolding now carry dated `CORRECTED 2026-08-01` notes where the
implementation deliberately differs. Scaffolding §6 lists twelve. **Auditing the code against the
uncorrected sketches will produce false findings**; read §6 first.

---

## 3. Claim ledger

Each row is falsifiable. Verdicts: UPHELD / FALSE / UNPROVEN.

### A. Reaction matrix (`ecs/systems/reaction_system.gd`)

| ID | Claim |
|---|---|
| C-A1 | Rules are keyed by the SORTED tag pair, so `A+B` and `B+A` resolve to one rule (review F2) |
| C-A2 | Scope is part of the rule identity: an INTER rule is not reachable as INTRA, and vice versa |
| C-A3 | `SCOPE_BOTH` registers one authored rule under both keys, and is applied per rule — the self-quench rule is INTRA-only and stays that way |
| C-A4 | Every participant receives `Reaction_Cooldown` for exactly `REACTION_COOLDOWN_FRAMES` (60) |
| C-A5 | The same pair cannot react again on the following frame, and the lock DOES lift when it expires |
| C-A6 | Cooldown expiry is stored on `ChemistryComponent.tag_expiry`, so a recycled row cannot inherit the previous occupant's lock |
| C-A7 | Deadlines are Micro-FRAME counts, so bullet-time cannot lengthen a cooldown |
| C-A8 | Reaction energy is DERIVED from the burning participant's mass and heat of combustion, not declared per rule |
| C-A9 | The ambient rise is real arithmetic over the chunk's air (14.8 MJ/°C) and is capped per tick at `MAX_AMBIENT_STEP_C` |
| C-A10 | A quench ABSORBS energy (latent heat of vaporisation), so extinguishing a fire is not free |
| C-A11 | An explosion imparts VELOCITY, capped at `MAX_BLAST_SPEED_MPS`, falling off with distance |
| C-A12 | Entities further apart than `CONTACT_RADIUS_M` do not react |
| C-A13 | A reaction never destroys row 0, whatever a `consumes` clause says |
| C-A14 | Energy is applied through the SURFACE model, not to bulk enthalpy (review H2) |
| C-A15 | The per-tick pass is bounded by `MAX_REACTIONS_PER_TICK` |
| C-A16 | The row list is snapshotted before `consumes` can destroy an entity, and the loop uses `.get` rather than indexing |

### B. Gas and temperature in the fluid grid (`ecs/systems/fluid_dynamics_system.gd`)

| ID | Claim |
|---|---|
| C-B1 | A material is gaseous when the chunk's ambient is at or above its boiling point — the same physics the phase model uses |
| C-B2 | Gas ignores elevation on BOTH sides of the head comparison, so steam climbs a ledge water pools below |
| C-B3 | Gas dissipates and a cloud provably clears; liquid volume remains EXACTLY conserved |
| C-B4 | Dissipation runs over the cells PROCESSED this tick, not the surviving dirty set — otherwise a cloud that stops flowing is stranded forever |
| C-B5 | The gas test is a table built once per tick with an `_any_gas` early-out, not a per-cell function call |

### C. Spell compiler (`ecs/systems/spell_compiler_system.gd`, `ecs/data_models/`)

| ID | Claim |
|---|---|
| C-C1 | The complexity cap REFUSES, with `REASON_TOO_COMPLEX`, against `Rune_Stability * 1.5` |
| C-C2 | The gate is inclusive: complexity exactly equal to the budget compiles |
| C-C3 | The geometric caps CLAMP rather than refuse, and record what they clamped in `caps_applied` |
| C-C4 | The FINAL extent of an expanding aura is capped, not merely its starting radius |
| C-C5 | Compilation never mutates `RuneLibrary.RUNES` — the shared content table |
| C-C6 | A spell requires a trigger, a shape and at least one catalyst, each with its own reason |
| C-C7 | A rune the caster has not learned is refused (`REASON_NOT_LEARNED`) |
| C-C8 | `Rune_Stability` is seeded at 10, so a new adventurer can compile the standard fireball |
| C-C9 | `spell_id` is a deterministic function of the runes (ADR-20) |
| C-C10 | `compile` is PURE — it is the Dry Run, and the panel calls it on every keystroke at zero cost |
| C-C11 | `bind` is the only mutating entry point, is reached only through an `ActionIntent`, and reports on the bus either way |
| C-C12 | Multiple triggers resolve by PRECEDENCE, not last-wins, so key-press order cannot change a spell |

### D. Casting and ephemerals (`ecs/systems/ephemeral_system.gd`, `action_resolution_system.gd`)

| ID | Claim |
|---|---|
| C-D1 | The TRIGGER decides when the payload fires; the SHAPE decides where |
| C-D2 | `On_Cast` applies continuously; `On_Impact` detonates on contact; `On_Timer` waits out its delay; `On_Proximity` waits for a non-caster |
| C-D3 | A one-shot that hits nothing still goes off on expiry rather than vanishing |
| C-D4 | A one-shot detonates exactly once |
| C-D5 | A Cone reads its angle: something behind the caster is inside the radius and outside the wedge |
| C-D6 | A projectile does not detonate on its own caster, nor on another ephemeral |
| C-D7 | A projectile that meets a wall detonates at the last OPEN position, not inside the rock |
| C-D8 | Every ephemeral dies on TTL; the suite asserts zero survive |
| C-D9 | Casting costs STAMINA, and a cast that cannot be paid for is refused without charging |
| C-D10 | Every refusal is announced on the bus with a reason (no bound spell, no stamina, fizzle) |
| C-D11 | `Absorb_Tag` consumes a QUANTIFIED resource atomically; two casters cannot spend one campfire (review D8) |
| C-D12 | The source tag is removed only when the underlying quantity is exhausted — a bonfire survives a draw |
| C-D13 | Absorb runs BEFORE strain is charged, so a fizzle costs the player nothing |
| C-D14 | Absorbed energy discounts strain and can never refund it |

### E. Mutation and the faction shift (`ecs/systems/mutation_system.gd`, `reputation_system.gd`)

| ID | Claim |
|---|---|
| C-E1 | Exposure accrues from the entity's own chemistry tags AND from `ChunkData.hazard_tags` |
| C-E2 | Exposure resets UNCONDITIONALLY at the threshold, so a capped body is never pinned |
| C-E3 | `MAX_MUTATIONS` is a hard cap |
| C-E4 | Every mutation in the table changes at least one real number, and every one is a TRADE |
| C-E5 | A granted resistance actually stops further exposure on that track |
| C-E6 | Lowering `max_health` clamps current health with it |
| C-E7 | The mutation roll uses the `mutation` RNG stream (ADR-8), never `randf()` |
| C-E8 | A mutation is queued as a WITNESSABLE act and routed through perception — not broadcast (review D3) |
| C-E9 | Mutation severity depends on the WITNESS faction's culture; crime severity does not |
| C-E10 | Every affinity entry names a culture tag `DAGGenerator.CULTURES` actually produces, enforced by test |
| C-E11 | Every mutation track has an affinity entry, enforced by test |
| C-E12 | Mutations reset on death; insight and runes carry via the Lineage Journal |
| C-E13 | `LineageJournal.apply_to` MERGES upward rather than replacing, so an empty journal cannot wipe the seeded field primer |

### F. Playability and the route in

| ID | Claim |
|---|---|
| C-F1 | Tab on a new target inspects; on the same target clears; on empty ground clears |
| C-F2 | Tab retargets directly, with no clearing press between two targets |
| C-F3 | The Grimoire never writes ECS state — binding is an `ActionIntent`, and the panel learns the result from a signal |
| C-F4 | The cast key holds no state: it reads `MindComponent.active_spell` |
| C-F5 | The arena contains a spore cloud, a volatile pocket and a lit brazier, placed apart so nothing fires on boot |
| C-F6 | `H` toggles a chunk hazard on and off, and standing in it actually accrues exposure |
| C-F7 | Both demos this manifest and RUNNING.md describe are executed end to end by `test_grimoire_ui.gd` |
| C-F8 | `--scenario=<name>` works both as `godot --scenario=x` and `godot -- --scenario=x`, and is NEVER written back to the config file |
| C-F9 | Every boot prints the active scenario and the globalized config path |

### G. Cross-cutting

| ID | Claim |
|---|---|
| C-G1 | 506 tests across 32 scripts, all passing |
| C-G2 | No Godot physics nodes anywhere in `ecs/`, `viewer/`, `ui/`, `singletons/` |
| C-G3 | `ecs/` reads no wall-clock; the mutation clock is derived from the frame count |
| C-G4 | Registry enums and components match the code, enforced by `tests/invariants` |
| C-G5 | Every new field is in `docs/component_and_field_registry.md` |
| C-G6 | The two new 60 Hz systems are benchmarked in `tests/perf` |

---

## 4. Findings the implementer already made against themselves

Recorded because an auditor should know what was already caught, and because the SHAPE of these
is the thing worth hunting for more of.

1. **Four trigger runes and a Cone that did nothing.** `trigger`, `delay_s` and `cone_angle_deg`
   were written by the compiler and read by nobody, so `On_Cast`, `On_Impact`, `On_Timer` and
   `On_Proximity` compiled, cost complexity, and produced identical behaviour — and a Cone was a
   sphere with a misleading name. Found by grepping for a second reference to each new symbol,
   not by any test. This is the fifth instance of this codebase's signature defect.
2. **`RuneLibrary.ids_of_kind` had exactly one reference.** Dead on arrival; deleted.
3. **The mutation affinity table named four cultures that do not exist.** `CULTURE_FUNGAL` and
   siblings appear in no `DAGGenerator.CULTURES` entry, so every affinity branch was unreachable
   and the mechanism was a constant revulsion wearing a lookup table. Now enforced by test.
4. **The flash-fire demo did not work.** The rule was INTER-only, and a fireball's catalyst leaves
   both tags on ONE entity, so the roadmap's own success state produced nothing — while every
   unit test passed, because they all arranged the tags across two neighbours. Found by running
   the documented play route end to end. `SCOPE_BOTH` fixes it; an INTRA reaction also released
   zero energy because it passed no owner map.
5. **A +48% regression in the hottest loop in the build.** The gas check was a function call plus
   two dictionary probes per CA cell. Caught by A/B benchmarking against `git stash`, not by any
   test. Now a table built once per tick; residual cost ~10%, and stated in RUNNING.md §6.
6. **`LineageJournal.apply_to` replaced insight rather than merging it.** Pre-existing, and
   harmless until Sprint 4 made insight load-bearing: a successor born with an empty journal
   would have had `Rune_Stability` wiped to 0 and been unable to compile any spell ever again,
   with no error to explain it.

7. **`--scenario=<name>` did not exist**, despite `scope_and_milestones.md` §7 naming it a
   Sprint 1 deliverable. Found by the owner failing to play Sprint 4 at all: the only route to
   the test arena was hand-written JSON in an OS-specific directory that RUNNING.md referenced
   eleven times before disclosing. Built, along with the guard that stops a one-run override
   persisting itself.

Every one of the above is covered by a test that fails when the fix is reverted — see §5.

---

## 5. How to audit this

**Pass 1 — reproduce.** §1. If the baseline disagrees, report that and stop.

**Pass 2 — falsify the ledger.** For each claim, find the code and try to break it. A claim
"proven" only by a test that calls a helper directly is NOT upheld: Sprint 3 shipped two false
claims of exactly that shape (`on_timeout` had no caller; `_convert_to_corpse` had a doc comment
and no guard). Check the PRODUCTION path.

**Pass 3 — hunt vacuous tests.** Mutate the implementation and confirm the test goes red. The
implementer ran 30 such mutations across the new code and all were killed, but that set was
chosen by the person who wrote the bugs. Two mutations initially "survived" and both turned out
to be bad mutations rather than weak tests — re-derive rather than trusting that.

**Pass 4 — the signature defect.** For every symbol added this sprint, grep for a SECOND
reference. A declared symbol with one reference is a claim with no implementation behind it. This
has now caught five instances across two sprints and is the single highest-yield check on this
codebase.

**Pass 5 — play it.** `"boot_scenario": "test_arena"` in `debug_config.json`, then follow the
Sprint 4 table in RUNNING.md §3a. A sprint is not done when the tests pass; it is done when
someone else can play it and knows what they are looking at.

**Pass 6 — the declared gaps.** §6. Confirm each is genuinely absent (an over-declared gap is a
lie in the other direction) and hunt for gaps that are NOT declared. Both previous audits found
undeclared gaps, which is a reason to trust the list below less, not more: it is written by the
same agent that wrote the code.

---

## 6. DECLARED GAPS — what Sprint 4 did NOT build

Stated here so an auditor does not have to discover them, and so "Sprint 4 complete" is not
claimed for things that are not.

| # | Gap | Why |
|---|---|---|
| G-1 | **The Grimoire node-graph editor, the 3D Dry Run hologram, and the translation-cipher minigame** | `inventory_and_grimoire_mechanics_specification.md` §2. The Dry Run's LOGIC is built and reachable; its wireframe SubViewport presentation is not. A UI sprint. |
| G-2 | **Overclocking and the mishap table** | Force-compiling an `[Unstable]` spell and rolling d100 on cast, with the Mercy Cap. Spec'd in the grimoire doc; not in the Sprint 4 roadmap. |
| G-3 | **No way to learn runes in play** | Ten of the seventeen runes are reachable only from tests. The DAG places ruined libraries; nothing makes them readable. |
| G-4 | **Spells have no visual** | A cast spawns a real entity that `ViewManager` draws as an ordinary box. No particles, light or trail. |
| G-5 | **NPCs never cast** | The compiler is mind-agnostic; only the player's mind is driven. |
| G-6 | **Four reaction rules** | Enough to prove the matrix. Not a content library. |
| G-7 | **No ignition-temperature model** | Heat alone does not set a flammable thing alight; a spell must say `Apply_Burning`. |
| G-8 | **Gas is temperature-driven only** | No emission, no pressure, no ventilation. |
| G-9 | **Four mutations, one per track** | A worked example, not a content set. |
| G-10 | **The mutation's BEHAVIOURAL consequence is not built** | The roadmap's success state says "the village guards refuse to let them into the tavern". Guards, arrest and gated access do not exist. What IS built is the reputation shift. |
| G-11 | **No naturally-occurring hazard zone** | World generation places none, so `H` is a debug key standing in for content — the same role `K` plays for death. |
| G-12 | **ADR-10 is still not met at 1,500 entities** | Unchanged by this sprint and verified so by A/B. The Rust/GDExtension port remains the agreed response. |
| G-13 | **Sprint 3.5's declared gaps are still open** | Schism, trade missions, brawls, loyalty, prestige, succession, ClaimTags, caravans. See the Sprint 3 manifest §4b; Sprint 4 did not touch them. |

**Ambiguities resolved by choosing.** Recorded so a reviewer can disagree with the choice rather
than discover it:

| Ambiguity | Chosen | Alternative |
|---|---|---|
| "No UI yet" (roadmap) vs "plus the Grimoire UI" (scope doc) | Build it, at debug-panel fidelity | Ship a compiler with no route in — the failure this project has hit four times |
| Gas: extend the CA, or a second grid | Extend the CA, keyed on ambient vs boiling point | A parallel gas grid with its own conservation contract |
| Gas from reactions | An expanding Ephemeral aura, the sanctioned primitive | Emitting into the CA |
| Who mutates | Any living body, not only row 0 | Player-only, per the scaffolding sketch |
| Reaction energy | Derived from material | The scaffolding's per-rule constant |
| Multiple triggers | Precedence | Last-wins |
| Mutation memory across death | Body resets, mind carries | Carrying the grimoire too — it is derivable from the runes |
