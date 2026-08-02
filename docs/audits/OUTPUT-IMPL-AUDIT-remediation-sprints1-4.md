# Implementation Audit Manifest — the Sprints 1–4 Remediation Pass (2026-08-01)

For an external auditor. The change set under audit is branch `fix/sprints1-4-remediation`
(stacked on `feature/sprint4-the-crucible`). The claim ledger is
`REMEDIATION-LEDGER-sprints1-4.md` in this directory — 56 items, each marked FIXED with the
finding it answers, plus the declared-not-built list. **Your job is to prove the ledger wrong:
a FIXED item that is not fixed, or an omission that is not on the declared list.**

## 0. IGNORE OTHER AUDITORS' RESULTS

Mandatory, as in every manifest here: do not read `*AUDIT-RESULT*` or `TRIAGE*` files before
forming your own findings.

## 1. Reproduce the baseline first

```bash
godot --headless --import
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
# Expected: 37 scripts, 585 tests, 585 passing.
gdlint ecs singletons ui viewer tests           # clean
godot --headless --scenario=world --soak=600 res://viewer/Main.tscn   # SOAK_OK, 10 metrics
```

## 2. What this pass was

Not a sprint. A full audit of Sprints 1–4 (four sweeps: Sprints 1–2 spec-vs-code, Sprint 3/3.5
beyond its declared §4b, Sprint 4 beyond its declared §6, and a dead-symbol sweep), followed by
remediation of every declared gap and every sweep finding that was buildable, and declaration of
the rest. The recurring defect class across all four sweeps was the codebase's signature one:
**machinery built and tested in isolation with the production wire missing** — the Pre-Warm that
never ran, the WAR status nothing consumed, the seven systems missing from `counters()`, the
`conduct_pair` that never conducted, `spawn_noise` with zero callers, professions never
attached, planner jobs preempted in half a second, faction memory that never decayed.

## 3. Highest-value attack surfaces

1. **The production wires.** Every FIXED item in the ledger names a wire. Grep each new symbol
   for its second reference IN A PRODUCTION PATH (a test calling a helper does not count):
   `SocialSystem.run` from `GameLoopManager._run_sim_tick`, `run_trade` from the Macro tick,
   `_burn_tick` from `ReactionSystem.run`, the Pre-Warm callable in
   `World._boot_generated_world`, `EventTrace` connections in `GameLoopManager._ready`.
2. **The mutation-test record.** 27 mutations, 27 killed — but three needed a second round, and
   the ledger records a Godot cyclic-parse quirk that silently SKIPS dependent test files when
   an autoload is edited without re-import ("nothing ran" reads as "all green"). Re-run any
   mutation you distrust WITH an `--import` between edit and test, and confirm the file ran.
3. **The declared list.** Prove it incomplete, as ever: an absence not on it is a finding.
4. **Determinism.** The soak gate asserts 10 integer metrics reproduce exactly from the seed.
   Run it twice; then attack ADR-20 — any wall-clock read in `ecs/`, any bare `randf`, any
   unstable single-field `sort_custom` (three were fixed across two sprints; find a fourth).
5. **The social layer's edges.** Succession with zero members; schism at exactly the ADR-12
   cap; caravan carrier dying mid-walk with the cargo stack; trespass while at WAR (should not
   double-file); the brawl health floor under repeated rounds; loyalty at the clamp boundaries.
6. **The fire model's conservation.** Burning adds energy to bodies and air and consumes
   heat-source fuel; quench absorbs. Check the ambient arithmetic against
   `ReactionSystem._heat_the_air`'s stated numbers, and that the burn budget
   (`MAX_BURNING_PER_TICK`) cannot starve the reaction matcher.

## 4. Ambiguities resolved by choosing (attack the choice, not the concealment)

| Ambiguity | Chosen |
|---|---|
| "Rest in a safe zone" (magic doc) | Rest = standing still, anywhere; safe-zone distinction declared not built |
| Overclock trigger (spec: strain > max stamina) | The compiler's complexity refusal is the forceable gate; strain interacts at cast |
| One word for water | `Wet` everywhere; the `Water` tag deleted from the vocabulary |
| TRADE band | 40–75 TRADE, ≥75 ALLIED (TRADE was unreachable by construction before) |
| Faction cap vs queue bound | One constant: `MAX_PENDING = 24`; dedup makes pending = distinct factions |
| Trespass cadence | One grievance per in-game hour; territory is pressure, not a mugging |
| Caravan conscription | Routine WORK is interruptible, meals and sleep are not |
| Loyalty arithmetic | Doc names inputs, no numbers; constants recorded in `SocialSystem` |

## 5. Output

Same required structure as `OUTPUT-IMPL-AUDIT-sprint3-and-3.5.md` §6: reproduction results,
findings with file:line and severity, verdict per ledger wave, and an explicit statement on
whether the declared list concealed anything.
