# Triage — implementation audits, Sprint 3 & 3.5

Sources, both against commit `5506479`:

- `OUTPUT-AUDIT-RESULT--gemini-3.1-pro--20260731-2357Z.md` — Gemini 3.1 Pro via Antigravity IDE
- `OUTPUT-AUDIT-RESULT--gpt55-copilot-cli--20260801-0638Z.md` — GPT-5.5 via Copilot CLI

Triaged by the implementing agent, 2026-08-01. Result: **10 defects fixed, 1 finding rejected as a
false positive caused by the auditor's own tooling, and 2 of my §4 claims were flatly FALSE.**

Both audits independently reproduced the baseline (28 scripts, 375 tests, gdlint clean,
`ECS_BOOT_OK`), and both ran real mutation tests rather than reading code and guessing. Nine
mutations were reported killed across the two reports. That is the difference between an audit and
a code review.

## The two false claims

I claimed these in §4 and they were not true. Both were covered by tests that passed, which is the
part worth dwelling on.

### C-C11 — "a timeout preserves the current objective rather than changing it"

FALSE. `LLMResolutionSystem.resolve()` forced `FORTIFY` on any empty response, and every failure
arrives as an empty response by design (C-C9). `on_timeout()`, which implements the rule I claimed,
**had no caller** — `rg on_timeout` found the method and its own unit test and nothing else.

So a faction mid-raid abandoned it because a network call timed out. The network decided strategy.

The claim was "proven" by a test that called the helper directly. That is a test of a function, not
of a behaviour, and the two claims either side of it were in tension all along: you cannot both
make every failure indistinguishable *and* treat timeouts differently from malformed answers. The
tension is now resolved in the honest direction — **no answer changes nothing**. `FORTIFY` remains
the fallback for a leader who *did* answer and named a faction that does not exist, which is a
different failure with a different right response.

`test_a_malformed_answer_falls_back_to_fortify` asserted the old behaviour and has been rewritten,
and the timeout test now goes through `resolve()`, the path the queue actually calls.

### C-D1 / C-D3 / C-D5 — the player row could become a corpse

FALSE. `ActionResolutionSystem._convert_to_corpse()` carried this doc comment:

> Death converts the entity into a corpse IN PLACE for non-player entities.

and then converted whatever row it was handed. A fatal fall tagged **row 0** `Corpse`/`Filth` and
stripped its behaviour bits; `GameLoopManager._check_player_death()` then ran `DeathLoopSystem`,
which built a second corpse out of already-mutated row-0 state. Two corpses, the reserved player
row wearing corpse tags, and ADR-14 broken for the width of a frame.

This is the *third* instance this sprint of a doc comment describing behaviour the code did not
have — after `PREFERRED_PROFESSION` and `on_timeout`. The pattern is now explicit in `STATE.md`.

No test caught it because every death-loop test called `on_player_death()` directly and none went
through a damage path a player actually dies from. Three regression tests now do.

## Everything else that was fixed

| Finding | Source | Was it real? |
|---|---|---|
| `ReasoningQueue._cache` unbounded | **both** | Yes. Capped at `MAX_CACHED`, oldest-first. A prompt changes whenever the world does, so distinct-prompt cardinality is unbounded and the "cost control" was a slow leak. |
| `FactionCoreComponent.objective_target` written, never read | Gemini | Yes, and the consequence is bigger than "dead code": a faction that decided to raid faction 9 sent its soldiers wandering its **own** village. `MarchToTarget` now routes to the target's anchor chunk. |
| Reasoning runs hourly, not weekly | GPT-5.5 | Yes. ADR-9 says every 168 macro ticks or crisis-triggered; `_think()` submitted every faction every hour — 168× the rate, burning a 200-call session budget in a day of in-game time. Now weekly, with a crisis path so a faction under attack does not wait six days. |
| Registry component drift | GPT-5.5 | Yes, and worse than reported. `FloodSourceComponent`, `ZonePopulationComponent`, `LLMPromptComponent` have no class; `LooseItemComponent` has no row. Fixing it revealed **two more** the audit missed: `PositionComponent` (deliberately stored as columns) and `LocomotionComponent` (my own Sprint 3A class, never documented). |
| `was_recently_attacked` never checked *when* | mine, found while fixing the above | Yes. It returned true if any violent memory existed anywhere in the capped list, so "recently" did no work. Harmless while it only coloured a prompt; not harmless once it became the crisis trigger, where a permanent crisis means a permanently elevated request rate. Now a 336-hour window. |

## The finding I reject

### "Configured remote LLM requests cannot authenticate" — MAJOR, GPT-5.5

Rejected. The report quotes the header as `"Authorization: ******" % _api_key` and runs a Godot
format check against that string, which of course errors. The file does not contain that string.
Raw bytes:

```
$ grep -n "Authorization" ecs/llm/openai_compatible_provider.gd | od -c
0000000  7  2  :  \t \t  "  A  u  t  h  o  r  i  z  a  t
0000020  i  o  n  :     B  e  a  r  e  r     %  s  "
0000040  %     _  a  p  i  _  k  e  y  ,  \n
```

The literal is `"Authorization: Bearer %s" % _api_key`, with its placeholder intact. **The
auditor's own harness masked the credential-shaped token, and the auditor then analysed its
redacted output as if it were the source.** The bug is in the reading, not the code.

Worth recording rather than quietly dropping, because it is a failure mode specific to auditing
security-adjacent code with a tool that redacts secrets: the redaction is invisible in the
transcript and looks exactly like a finding. An auditor working on auth code should read the file
with `od`, `xxd`, or a checksum before reporting the literal as wrong.

Everything else in that report held up.

## Disagreements between the two audits

Gemini marked **every one of the 60+ claims UPHELD**, including C-C11 and C-D1, which GPT-5.5
disproved with executable repros. It found two real defects (the cache and `objective_target`) but
its ledger was too generous, and its own summary says it validated most claims by "manual source
code analysis" rather than by running anything. GPT-5.5 wrote temporary GUT tests that failed, and
quoted the failures.

That is the whole argument for running more than one auditor, and for weighting them by method
rather than by verdict count. An audit that upholds everything is data about the audit.

## Undeclared gaps both audits found, not yet fixed

Now declared in §4b as G-7..G-9 rather than fixed, because each needs a design decision:

- **Schism, Trade Missions, Brawls** (Gemini). Named in the Sprint 3.5 scope row or the factions
  architecture, absent from `JOB_TEMPLATES` and from any system. Gemini is right that §4b's
  nine-item table was drawn from the scope row and missed mechanics the architecture doc adds.
- **`PromptBuilder` ignores active `MemoryComponent`s** (GPT-5.5). The roadmap Step 2 asks for
  faction memory *and* relevant active memories; only the first is read.
- **`public_declaration` is never written to a `MemoryComponent`** (GPT-5.5), so a leader's
  declaration cannot be repeated by gossip, which is the point of having one.

Also confirmed dead by GPT-5.5 and left alone deliberately: `MemoryComponent.most_salient()`. It is
unused because `PromptBuilder` does its own selection; it should be deleted or become the one
implementation, and that is a Sprint 4 decision.

## Both audits agree on Sprint 3.5

Overstated. So does §4b, so does the first input audit, so does the second. Four independent
assessments, one conclusion: "Sprint 3.5: consequences" is fair, "Sprint 3.5 complete" is not.
