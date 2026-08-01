# INPUT SPECIFICATION AUDIT — Sprint 3 & Sprint 3.5

**You are an adversarial auditor. You have not written any of this code and you owe it nothing.**

This document is self-bootstrapping. Read it top to bottom, follow the procedure, write the output
file. Do not ask for further instructions.

---

## 0. What you are auditing, and what you are NOT

You are auditing the **INPUT SPECIFICATIONS** — the documents that told an implementer what to
build. You are judging the *specs*, not the code.

**IN SCOPE:** ambiguity, contradiction, unfalsifiable success criteria, missing constraints,
under-specified failure modes, arithmetic that does not work, requirements that cannot be tested,
and — most importantly — **requirements that are absent entirely**.

**OUT OF SCOPE:** whether the code matches the spec. A separate auditor has that job, driven by
`OUTPUT-IMPL-AUDIT-sprint3-and-3.5.md` in this same directory. Do not read the implementation
except where §4 explicitly directs you to, and when you do, read it only to answer "was this
specified?", never "is this correct?".

A finding of the form *"the spec says X and the code does Y"* is out of scope. A finding of the
form *"the spec never says what should happen when X"* is exactly what is wanted.

---

## 1. Environment

| Item | Value |
|---|---|
| Repository | `https://github.com/earchibald/ambition` |
| Local path | `/Users/earchibald/Code/ambition` |
| Branch to read | `feature/sprint3.5-body-politic` |
| Base branch | `dev` |
| Open PRs | #7 (`feature/sprint3-world-inspector`), #8 (`feature/sprint3.5-body-politic`, stacked on #7) |
| Engine | Godot 4.7.1 |
| Language | GDScript |

```bash
cd /Users/earchibald/Code/ambition
git fetch --all
git checkout feature/sprint3.5-body-politic
git log --oneline dev..HEAD          # the change set under audit
```

You do **not** need to run Godot for this audit. It is a document review.

---

## 2. The specifications under audit

Read these in this order. The first two are **authoritative and override everything else**.

### Tier 1 — Authority (a contradiction with these is automatically a defect in the other document)

| File | What it governs |
|---|---|
| `docs/architecture_decisions.md` | The ADR. Cross-cutting decisions, numbered ADR-1..ADR-21. |
| `docs/component_and_field_registry.md` | Canonical names and types for every component, field, enum, tag. |

### Tier 2 — The sprint specs actually being audited

| File | Sprint |
|---|---|
| `docs/sprint_3_implementation_roadmap.md` | Sprint 3 — six numbered Steps with "Success State" claims |
| `docs/sprint_3_technical_scaffolding.md` | Sprint 3 — code structures, §1–§7 |
| `docs/scope_and_milestones.md` | Where Sprint 3.5 is defined. **See the warning in §3.** |

### Tier 3 — Supporting architecture the sprint specs lean on

| File | Relevance |
|---|---|
| `docs/llm_reasoner_and_planning_architecture.md` | Sprint 3 Steps 1–3 |
| `docs/meta_progression_and_death_loop_architecture.md` | Sprint 3 Steps 4–6 |
| `docs/factions_and_social_mechanics_architecture.md` | Sprint 3.5 |
| `docs/entity_behavior_and_society_architecture.md` | Job/needs/AI backbone |
| `docs/invariants_and_test_strategy.md` | What "done" is supposed to mean |
| `CLAUDE.md` | The Prime Directive and the workflow rules |

### Tier 4 — Historical, NON-binding

`docs/ADVERSARIAL_REVIEW*.md` are prior repair logs. Useful for "why is it like this", but they
carry no authority and nothing in them is an open issue unless `STATE.md` says so.

---

## 3. Known asymmetry you must confront

**Sprint 3 has a roadmap and a technical scaffolding document. Sprint 3.5 has neither.**

Sprint 3.5 exists as a single table row in `docs/scope_and_milestones.md` (~line 103) reading:

> **3.5 "The Body Politic"** | **Previously unowned.** Loyalty, schism, succession by prestige,
> ClaimTags, caravans, grievance accumulation, war-time job generation, Job_Chat gossip,
> profession assignment

That is the entire specification. Nine noun phrases, no acceptance criteria, no data structures,
no numbers, no failure modes.

**Do not treat this as a formatting quirk.** Assess directly:

- Is one table row a sufficient specification for a sprint? What can and cannot be built from it?
- Which of those nine items are even *defined* anywhere else in `docs/`? Grep for each.
- Which are defined only in Tier 3 architecture docs, i.e. described but never scoped?
- If an implementer built only a subset, does anything in the specs say which subset is correct?
- Is there an acceptance criterion anywhere by which Sprint 3.5 could be called done or not done?

This is likely the single largest finding available. Give it proportionate weight, and be
specific: enumerate which of the nine are specified, where, and to what depth.

---

## 4. Procedure

Work through all six passes. Record findings as you go.

### Pass 1 — Falsifiability of the Success States

`sprint_3_implementation_roadmap.md` states a "Success State" for each of six Steps. For each:

1. Quote it.
2. Ask: **could a competent tester determine pass/fail from this sentence alone?**
3. If not, name precisely what is missing — a number, a threshold, an observable, a time bound.
4. Note any Success State that depends on something no Step in the sprint builds.

That last check matters. At least one Success State describes behaviour requiring a capability
that no Step in Sprint 3 specifies as a deliverable. Find it and name it rather than taking this
claim on trust — and if you conclude there is no such gap, say so and show your reasoning.

### Pass 2 — Contradictions against Tier 1

Grep the sprint specs for every ADR reference and every component/field name. For each:

- Does the referenced ADR say what the sprint doc claims it says?
- Does every named component and field exist in the registry, spelled and typed identically?
- Does any sprint instruction require violating an ADR or the Prime Directive?

Pay attention to **ADR-5**. It carries an amendment recorded partway through the project. Check
whether the Sprint 3 documents were updated to match it, or whether they still describe the
superseded position. A spec that contradicts its own governing ADR is a defect in the spec.

### Pass 3 — Arithmetic and physical plausibility

The specs assert numbers. Check them:

- Interregnum: 12 monthly passes. Is the relationship between months, hours, and the Macro tick
  stated consistently everywhere it appears?
- Entropy tax: 40%. Is the retained fraction stated unambiguously, and is it applied to a defined
  quantity?
- Swarm cap: 10 per chunk. Cap on what, exactly — a counter or entities? Is that consistent
  between roadmap and scaffolding?
- Spell complexity: `insight.get(&"Rune_Stability", 0) * 1.5` (this appears in the Sprint 4 spec
  but is cross-referenced). Does an insight value exist that makes any spell compilable at all?
- The salience filter: "top 3 by weight plus 3 most recent". Is the overlap case defined?

Recompute anything computable. Report any number that does not survive contact with arithmetic.

### Pass 4 — Absent failure modes

For each Step, list the failure modes the spec does NOT address. Specifically hunt for:

- What happens when a required precondition is absent (no factions, no grid, empty world)?
- What is bounded and what is not? Name every unbounded loop, queue, or list the spec implies.
- What happens on the *second* invocation of anything the spec describes once?
- Which operations must be idempotent, and does the spec say so?
- Where does the spec assume a thing exists without saying who creates it?

### Pass 5 — Testability and the definition of done

- `docs/invariants_and_test_strategy.md` defines gates. Do Sprint 3 and 3.5 have gates there?
- `docs/scope_and_milestones.md` states rules R1–R6. Do the sprint specs comply with their own
  project's rules?
- Does any spec state a *performance* budget for what it adds? Sprint 3 adds pathfinding and a
  per-tick reasoning queue to a project whose ADR-10 budget is already documented as missed
  (see `STATE.md`). Is that addressed anywhere?

### Pass 6 — What a competent implementer would have to invent

This is the highest-value pass. For each sprint, list decisions an implementer is *forced* to make
because the spec is silent. Examples of the shape wanted:

> "The spec says grievances accumulate. It never states a severity scale, a decay rate, whether
> reputation is global or per-faction-pair, or what threshold constitutes hostility. An
> implementer must invent all four, and any two implementers would invent different ones."

You may open the implementation **only** to identify what was invented — never to judge it. If
you use it this way, mark the finding `[inferred-from-impl]`.

---

## 5. Output

Write **one Markdown file** to:

```
docs/audits/INPUT-AUDIT-RESULT--<AGENT_SLUG>--<UTC_TIMESTAMP>.md
```

- `<AGENT_SLUG>`: lowercase, hyphenated, identifying model **and** harness, e.g.
  `gpt5-codex`, `gemini3-aider`, `opus5-cursor`. Invent one if unsure; do not leave it blank.
- `<UTC_TIMESTAMP>`: `YYYYMMDD-HHMMZ`, e.g. `20260801-0630Z`.

Full example: `docs/audits/INPUT-AUDIT-RESULT--gpt5-codex--20260801-0630Z.md`

**The timestamp and slug exist to prevent collisions between parallel auditors. Do not omit them,
and do not overwrite an existing file — if your exact filename is taken, increment the minutes.**

### Required structure

```markdown
# Input Specification Audit — Sprint 3 & 3.5
Auditor: <model> via <harness>
Commit audited: <output of `git rev-parse --short HEAD`>
Date (UTC): <timestamp>

## Verdict
<Three sentences maximum. Are these specs sufficient to build from? Yes / No / Partially, and why.>

## Severity summary
| Severity | Count |
|---|---|
| BLOCKER | n |
| MAJOR | n |
| MINOR | n |

## Findings
### [SEVERITY] <short title>
- **Where:** `<file>:<line or section>`
- **Quote:** > <the exact text at fault, or "ABSENT — nothing in any spec covers this">
- **Problem:** <what is wrong, in one or two sentences>
- **Consequence:** <what an implementer does wrong because of it>
- **Suggested remedy:** <a concrete sentence or clause that would fix it>

## Sprint 3.5 specification adequacy
<Your §3 assessment. Enumerate the nine named items and where, if anywhere, each is specified.>

## Questions the specs cannot answer
<Numbered list. Things you could not determine from the documents at all.>

## What the specs get RIGHT
<Required. At least three items. An audit that finds only faults is not calibrated, and I will
weight your findings by whether this section is substantive.>
```

### Severity definitions

- **BLOCKER** — an implementer cannot proceed correctly; or the spec mandates something that
  violates Tier 1 authority; or two specs give irreconcilable instructions.
- **MAJOR** — an implementer will proceed, and will probably build the wrong thing, or will be
  unable to prove they built the right thing.
- **MINOR** — friction, ambiguity resolvable by inspection, or cosmetic inconsistency.

---

## 6. Rules of engagement

1. **Quote or it did not happen.** Every finding cites a file and a line/section, and quotes the
   text — or explicitly states `ABSENT` and names where it should have been.
2. **Do not report style.** Prose quality, heading levels and tone are not defects.
3. **Do not repeat the historical review logs.** The `ADVERSARIAL_REVIEW*` files already list
   prior findings. If you rediscover one, say so and state whether the fix is reflected in the
   current specs. Rediscovery presented as novel wastes the exercise.
4. **Absence is the highest-value finding.** Anyone can spot a contradiction; the expensive
   defects are requirements nobody wrote down.
5. **Disagree with the specs where you think they are wrong.** They were written by a fallible
   agent. If ADR-N is itself a bad decision, say so under MAJOR and argue it.
6. **Do not fix anything.** No code changes, no doc edits. Write your output file and stop.
