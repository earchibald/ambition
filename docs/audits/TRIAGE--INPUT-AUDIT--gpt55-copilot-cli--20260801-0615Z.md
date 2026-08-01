# Triage — input spec audit, GPT-5.5 via GitHub Copilot CLI

Source: `INPUT-AUDIT-RESULT--gpt55-copilot-cli--20260801-0615Z.md`, commit `618271a`.
Triaged by the implementing agent, 2026-08-01.

This is the stronger of the two input audits. It read the post-triage state rather than the
original, so it found what the first round's fixes left behind, and **three of its findings turned
out to be live defects in the shipped code**, not only in the specs. An audit scoped to documents
found real bugs because the documents described the bugs accurately.

| # | Severity | Finding | Spec fixed? | Code fixed? |
|---|---|---|---|---|
| 1 | BLOCKER | Sprint 3.5 has no buildable spec | NO — owner's call | n/a |
| 2 | BLOCKER | ADR-5 still contradicted in active Tier-3 text | YES | Already correct |
| 3 | BLOCKER | Scaffolding violates ADR-19's handle/row contract | YES | Already correct |
| 4 | MAJOR | Step 1's "60fps" success state is not falsifiable | Declared as G-6 | n/a |
| 5 | MAJOR | Queue limits and prioritisation unspecified | YES | **NO** — G-1, G-5 |
| 6 | MAJOR | Step 4's success state needs unscheduled NPC behaviour | Declared | n/a |
| 7 | MAJOR | Player-death DAG edge uses a non-registry edge shape | YES | **YES — real bug** |
| 8 | MAJOR | Interregnum reputation decay numerically ambiguous | YES | **YES — never built** |
| 9 | MAJOR | Swarm cap ambiguous: total vs per-species | YES | Already correct |
| 10 | MAJOR | Perf budgets named but not assigned to tests | Declared as G-6 | n/a |
| 11 | MAJOR | Salience dedup defined, ordering not | YES | **YES — real bug** |
| 12 | MINOR | Enum examples drift (`RAID` vs `RAID_FACTION`) | Noted | Already correct |
| 13 | MINOR | `Rune_Stability` has no bootstrap value | Sprint 4's problem | n/a |

## The three that were real code defects

### 7 — the death edge pointed the wrong way

The audit says the roadmap names a `Killed_By` edge type that is not in the registry's `EdgeType`
enum, and predicts an implementer will "invent an unregistered edge type or overload an unrelated
enum". The implementation overloaded `DESTROYED`, exactly as predicted, and worse than predicted:

```gdscript
DAGEdge.create(WorldConstants.PLAYER_FACTION_ID, killer_faction, ECSEnums.EdgeType.DESTROYED, ...)
```

This graph's own convention is `CONQUERED(aggressor, victim)` — source acts on target. So the
death of the player was recorded as **the player having destroyed the killer's faction**. Anyone
reading that faction's history would find a destruction it never suffered, in the only record of
why the world looks the way it does. `DESTROYED` is also written elsewhere as a self-loop meaning
"this node ceased to exist", which a faction that just won a fight plainly has not.

Fixed: `KILLED_BY` added to `ECSEnums.EdgeType` and to the registry with the direction convention
stated. A death with no killer is a self-loop, not an edge to faction `-1` — there is no node
`-1`, and an edge to one is a dangling reference.

**Why the tests did not catch it:** `test_the_death_is_written_into_history` asserted the edge
count and `source_id` and nothing else. It never checked the type or the target, so it passed
against an edge that said the opposite of what happened. That is a vacuous-test finding against my
own work, of the exact kind §5 Pass 2 of the output manifest asks an auditor to hunt. Three tests
now cover it, and all three fail when the fix is reverted.

### 11 — the salience filter was not deterministic

The audit calls the missing tie-break rule a brittleness problem. It is worse than that. Both
sorts compared a single field and `sort_custom` is not stable, so ties changed **which memories
were selected**, not merely their order:

- It violates ADR-20, which requires the simulation to be reproducible from seeds.
- It silently defeats the response cache in `ReasoningQueue`, which keys on the prompt hash. A
  cache that misses on identical world state is a paid API call that should never have happened —
  the cost control quietly not working, with no symptom.

Fixed with a total order: `(weight, tick, event_id)` for the weight pass, `(tick, weight,
event_id)` for recency. `event_id` is globally unique, so no tie survives.
`FactionCoreComponent.prune_diplomacy()` had the identical defect — an unstable sort deciding
which relationships a faction *keeps* — and is fixed the same way. Both were found by taking the
finding seriously enough to grep for the pattern rather than fixing the one instance named.

### 8 — Interregnum reputation decay was never implemented

The audit asks whether "60-75% toward neutral" applies per monthly pass or across the year. The
real answer was neither: **grep found no decay at all.** Reputation was permanent. Sprint 3.5 gave
factions a reason to hate the player and Sprint 3D gave the player a way to die, and nothing
connected them, so a hostile village stayed hostile across every future life. That makes the death
loop a respawn rather than a fresh start, which is the one thing the meta-progression architecture
is for.

Implemented, and the ambiguity resolved by arithmetic rather than preference: per-month compounds
to `0.4^12 = 1.7e-5` at the gentle end of the band, which erases the grudge completely and makes
the whole consequence layer reset on death. Annual it is, retaining 30%. The score decays and the
**grievance list does not** — they stop acting on it and still remember, which also gives a second
offence more weight than the first without a special case.

## Findings 2 and 3 — specs corrected, code was already right

The ADR-5 contradiction survived my first triage: I fixed the scaffolding's §5 line and missed the
same claim in the header block *and* in `llm_reasoner_and_planning_architecture.md`. Both now
carry the amendment. `HeuristicProvider` has always decided from real faction state, so no code
changed — but the audit is right that a future implementer following the architecture doc would
have built the superseded canned-FORTIFY behaviour.

The ADR-19 finding is correct about the scaffolding: `Array[EntityHandle]`,
`request_reasoning(entity: EntityHandle)`, and query results passed to `has_tag`/`destroy_entity`
as though rows were handles. All corrected with the reason spelled out, because the row/handle
distinction is what stops a queued leader silently becoming whoever recycled its slot.
`reasoning_queue.gd` uses `Array[int]` and converts explicitly, so no code changed.

## Finding 1 — Sprint 3.5

Both auditors independently reach the same conclusion, and it matches §4b of the output manifest.
Not actioned, because suspending a sprint is a scope decision and the owner's to make. What is
actioned: it is written down where the next agent will see it, in `STATE.md` and in §4b.

The GPT-5.5 enumeration of the nine items is the better one and supersedes the first audit's. It
correctly identifies succession as *more specified than most* — the first audit called it
"completely undefined" on the basis of a heading it appears not to have read past.

## Findings the audit got wrong or overstated

- **12, enum drift.** Correct about the prose, and it uncovered something worse than it claimed.
  The code does use `RAID_FACTION` and the uppercase `RelationshipStatus` literals throughout — but
  **nothing enforced that**. The registry is declared canonical and was kept in step with
  `ECSEnums` by hand, which is to say by luck, which is exactly how finding 7 happened. Closed by
  `test_every_registry_enum_matches_the_code`, which parses the registry and compares all twelve
  enums member-for-member. Adding a member to any enum without documenting it now fails CI.
- **9, swarm cap.** The registry defines exactly one counter, so the "10 total" reading was
  already forced; the implementation clamps `ChunkData.swarm_population` and matches. The prose
  naming two species is the ambiguity, and it is now disambiguated in the scaffolding.

## What both audits missed

Neither surfaced the **per-faction reasoning cap** (G-1) or the **unenforced `reason_summary`
cap** (G-4) independently, though GPT-5.5's finding 5 covers the first as part of a broader point
about queue rules. Both are declared in §4b. Two audits finding neither is a reason to trust the
declared-gap list less, not more — it is a list written by the same agent that wrote the bugs.
