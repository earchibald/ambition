# Triage — input spec audit, gemini3-high via antigravity-cli

Source: `INPUT-AUDIT-RESULT--gemini3-high--20260801-0601Z.md`, commit `cbf11ac`.
Triaged by the implementing agent, 2026-08-01. Every finding is dispositioned; none is dismissed
without a reason.

The audit is on the specs. Three of its findings are code printed *inside* a spec, so the useful
second question — did the implementation inherit the defect? — is answered here per finding.

| # | Severity | Finding | Spec fixed? | Code affected? |
|---|---|---|---|---|
| 1 | BLOCKER | Queue deadlocks: `_on_request_completed` never clears the in-flight flag | YES | **No** |
| 2 | BLOCKER | `current_flight_data` used but never assigned | YES | **No** |
| 3 | BLOCKER | Sprint 3.5 is one table row | NO — see below | Yes, and declared |
| 4 | MAJOR | Scaffolding's canned-FORTIFY `NullLLMProvider` contradicts the ADR-5 amendment | YES | **No** |
| 5 | MAJOR | Salience filter overlap undefined | YES | **No** |
| 6 | MAJOR | Step 3's Success State depends on swords and goblins no Step builds | YES | n/a |
| 7 | MINOR | Step 6 has no Success State | YES | n/a |
| 8 | MINOR | R6's RUNNING.md rewrite is not a step | YES — added as Step 7 | n/a |

## Findings 1 and 2 — the deadlock the implementation dodged

Both are real, both would be fatal, and both are in pseudo-code a future agent could have copied
verbatim. Corrected in place with a dated note rather than deleted, so the trap stays legible.

`ecs/llm/reasoning_queue.gd` does not have either defect, and not by luck:

- `_in_flight = EH.INVALID` is the **first** statement of the completion callback
  (`reasoning_queue.gd:107`), before any branch.
- The dead-leader check runs at `pump()` time, *before* `_in_flight` is ever set
  (`reasoning_queue.gd:79`), so an early return leaves the line free by construction rather than
  by remembering to clear it.
- There is no `current_flight_data`. The handle is captured by the dispatch lambda, so it cannot
  be read before it is written.

The auditor's question 1 — "how does a request failure avoid leaving the flag set forever?" — is
worth answering against the code and not only the spec. Every failure path in
`openai_compatible_provider.gd` funnels through `_finish()`, which nulls `_on_done` before calling
it, so the callback fires exactly once and the queue clears exactly once. `HTTPRequest.timeout` is
set, and a timeout arrives as an ordinary `request_completed` with a non-2xx code, so a hung
provider still ends in `_finish({})`. A request that never returns at all is not reachable through
`HTTPRequest`.

## Finding 3 — Sprint 3.5

Upheld, and it matches the implementing agent's own assessment. See §4b of
`OUTPUT-IMPL-AUDIT-sprint3-and-3.5.md`: of the nine named items, three are built, one is built in
a different shape than named, one is partial, two exist as fields nothing reads, and two do not
exist.

The auditor's remedy is to suspend the sprint until a roadmap and scaffolding exist. That is the
right call for the seven unbuilt items and it is **not** actioned here, because it is a scope
decision and not the implementing agent's to make. What has been done instead: the gap is written
down, item by item, in the manifest an external auditor reads, and `STATE.md` says the sprint is
partial. The two independent audits corroborate each other on this point, which is the strongest
evidence available that the sprint needs a real spec before more of it is built.

The auditor's per-item enumeration is adopted for "war-time job generation" and "profession
assignment", which do appear nowhere in the documentation suite at all.

**Its succession item is wrong, and checking it changed the disposition.** The audit says
`factions_and_social_mechanics_architecture.md` has a "Succession (The Promotion System)" heading
with "zero text underneath" and that succession is "completely undefined". It is defined, at
`factions_and_social_mechanics_architecture.md:50-56`, and to a buildable degree:

> The SocialSystem scans all Tier 2 entities in the faction, selects the one with the highest
> prestige, and promotes them. They are granted the LLMPromptComponent, and a "Reasoning Tick" is
> immediately queued to determine the new leader's agenda.

That is a selection rule, a component grant, and a follow-on action. It is more specified than
most of Sprint 3.5. So succession moves from *unspecified* to **specified and not built**, which
is a worse status for the implementation, not a better one — the excuse of a vague spec does not
apply to it. `OUTPUT-IMPL-AUDIT` §4b has been amended to say so.

The same check partly rescues two more items the audit called undefined. Schism has a stated
trigger (loyalty below 20/100) and a stated consequence (splinter `faction_id`, immediate war,
seize the nearest stockpile); what is genuinely missing is only *which* members leave — "a
percentage". Caravans have stated behaviour too: form from Tier 2 entities, load surplus from the
`InventoryZone`, pathfind to the ally's zone, and exist physically so they can be intercepted.
Routing and dispatch cadence are missing; the concept is not.

The lesson for the next audit round is narrow and worth stating: this auditor reported "no text
under the heading" for a section with seven lines under it. Verify absence claims by opening the
file. An audit's absence findings are its highest-value output and also the easiest to get wrong.

## Findings 4 and 5 — spec defects the implementation had already resolved

Finding 4: the scaffolding still described `NullLLMProvider` as returning a canned payload, which
the ADR-5 amendment supersedes. The shipped `HeuristicProvider` scores starvation, threat and
opportunity from the same context Dictionary the remote provider gets. The spec now says so.

Finding 5: `PromptBuilder._append_memory()` already deduplicates by `event_id`
(`prompt_builder.gd:156`), so the filter sends between 3 and 6 memories. The spec said "top 3 plus
3 most recent" and left the overlap to the implementer, exactly as the auditor says. Now stated.

## What this audit did not find, and should have

Recorded so the exercise is honest about its own coverage, not to score a point:

- It did not flag the **absence of a per-faction cap on concurrent Tier-3 requests**, which
  ADR-12 implies and no spec states. That is a genuine unspecified-requirement finding of exactly
  the shape §4 of the manifest asked for, and it is the one declared gap with a live failure mode:
  one faction can fill the global queue.
- It did not flag that `reason_summary`'s 200-character cap is **requested in the prompt and
  never enforced on the way back**, so a remote provider's answer length is unbounded in practice.

Both are already declared in `OUTPUT-IMPL-AUDIT` §4b, G-1 and G-4. Two auditors have now looked at
these specs and neither surfaced them independently, which is a reason to trust the declared-gap
list less, not more.
