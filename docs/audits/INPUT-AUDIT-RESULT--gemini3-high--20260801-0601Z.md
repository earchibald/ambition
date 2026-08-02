# Input Specification Audit — Sprint 3 & 3.5
Auditor: gemini3-high via antigravity-cli
Commit audited: cbf11ac
Date (UTC): 20260801-0601Z

## Verdict
No, these specifications are not sufficient to build from. Sprint 3 contains explicit code defects in its technical scaffolding that will deadlock the core asynchronous loop, and it blatantly contradicts the authoritative ADR-5. Sprint 3.5 is entirely unspecified, consisting of nine nouns with no mechanics, formulas, or acceptance criteria.

## Severity summary
| Severity | Count |
|---|---|
| BLOCKER | 3 |
| MAJOR | 3 |
| MINOR | 2 |

## Findings

### [BLOCKER] Queue Deadlock in LLMBridge
- **Where:** `docs/sprint_3_technical_scaffolding.md:64`
- **Quote:** `if not ECSManager.is_alive(entity): return`
- **Problem:** The `_on_request_completed` callback never sets `is_request_in_flight = false`. Furthermore, if the leader is dead, it returns early. 
- **Consequence:** The queue permanently deadlocks on the very first request, halting all Tier 3 LLM reasoning for the rest of the game session.
- **Suggested remedy:** Add `is_request_in_flight = false` as the first line of `_on_request_completed`, before any early returns.

### [BLOCKER] Undefined Variable in Scaffolding
- **Where:** `docs/sprint_3_technical_scaffolding.md:66`
- **Quote:** `var entity = current_flight_data.entity`
- **Problem:** `current_flight_data` is never assigned in `_dispatch_next_request()`. It pops `var entity = request_queue.pop_front()` but doesn't store it in `current_flight_data`.
- **Consequence:** The script crashes with a null reference error on the very first LLM callback, breaking the game.
- **Suggested remedy:** Add `current_flight_data = { "entity": entity }` in `_dispatch_next_request()`.

### [BLOCKER] Sprint 3.5 is Completely Unspecified
- **Where:** `docs/scope_and_milestones.md:103`
- **Quote:** `3.5 "The Body Politic" | Previously unowned. Loyalty, schism, succession by prestige, ClaimTags, caravans, grievance accumulation, war-time job generation, Job_Chat gossip, profession assignment`
- **Problem:** A single table row is the entire specification for a sprint. No acceptance criteria, no mechanics, and no numbers are provided.
- **Consequence:** An implementer has to invent an entire game's political and social systems from nine noun phrases.
- **Suggested remedy:** Suspend Sprint 3.5 until a dedicated implementation roadmap and technical scaffolding document are written for it, fulfilling Rule 1.

### [MAJOR] Contradiction of ADR-5 Amendment
- **Where:** `docs/sprint_3_technical_scaffolding.md:121`
- **Quote:** `NullLLMProvider (tests/CI): immediately returns a canned valid {"objective":"FORTIFY",...}.`
- **Problem:** The amendment to ADR-5 in `architecture_decisions.md` explicitly promotes `NullLLMProvider` to a shipped product mode and requires it to "decide from real faction state rather than returning a canned payload".
- **Consequence:** The implementer will build a `NullLLMProvider` that always returns FORTIFY, breaking the requirement for a fully playable offline mode and violating the ADR.
- **Suggested remedy:** Update the scaffolding to match ADR-5: "NullLLMProvider uses local utility-AI scoring to return play-viable objectives based on faction state, starvation, and opportunity."

### [MAJOR] Salience Filter Overlap Undefined
- **Where:** `docs/sprint_3_implementation_roadmap.md:29`
- **Quote:** `CRITICAL - The Salience Filter: send only the top 3 memories by decayed weight plus the 3 most recent events.`
- **Problem:** The spec doesn't define what happens when the 3 most recent events overlap with the top 3 by weight.
- **Consequence:** Implementers will diverge: some will deduplicate (sending 3-6 items), others will blindly append (sending 6 items, potentially duplicating memories in the LLM context).
- **Suggested remedy:** Specify "deduplicated by event_id" for the final combined list in the prompt builder.

### [MAJOR] Unfalsifiable Success State (Step 3)
- **Where:** `docs/sprint_3_implementation_roadmap.md:49`
- **Quote:** `Success State: The LLM decides to attack the Spiders (Target 15). 10 seconds later, 5 Tier 2 Goblins equip swords and pathfind toward the spider cavern.`
- **Problem:** This success state asserts behaviors (equipping swords, goblin NPCs) that Sprint 3 doesn't build and that may not exist in the test environment yet. 
- **Consequence:** A tester cannot strictly pass Sprint 3 without also implicitly requiring a fully populated world with items and job paths that belong to other sprints.
- **Suggested remedy:** Scope the success state to the exact outputs of Sprint 3: "The LLM sets objective to RAID, and the Job_Queue correctly populates with corresponding JobTemplates for the target."

### [MINOR] Missing Success State for Step 6
- **Where:** `docs/sprint_3_implementation_roadmap.md:87`
- **Quote:** `ABSENT — nothing in any spec covers this`
- **Problem:** Step 6 has an Objective and Required Implementation, but completely lacks a "Success State" claim.
- **Consequence:** Testers have no defined acceptance criteria for the Lineage Journal & Re-Entry step.
- **Suggested remedy:** Add a Success State: "Success State: Player dies, restarts, and their MindComponent correctly initializes with previous insight and known_runes."

### [MINOR] R6 RUNNING.md Rewrite Ignored
- **Where:** `docs/sprint_3_implementation_roadmap.md`
- **Quote:** `ABSENT — nothing in any spec covers this`
- **Problem:** Rule R6 states that `RUNNING.md` must be rewritten at the end of every sprint, but Sprint 3's roadmap does not list this as a required step or success state.
- **Consequence:** The implementer will likely forget to update `RUNNING.md`, violating the scope rules.
- **Suggested remedy:** Add a Step 7 explicitly requiring rewriting `RUNNING.md` to reflect Sprint 3's completion.

## Sprint 3.5 specification adequacy

1. **Loyalty**: Defined as a field in `SocialIdentityComponent` and mentioned conceptually in `factions_and_social_mechanics_architecture.md`, but calculation specifics (decay, thresholds) are absent.
2. **Schism**: Described conceptually in factions architecture, but the exact mechanism for splitting a faction (who leaves, who stays, who leads) is unspecified.
3. **Succession by prestige**: `factions_and_social_mechanics_architecture.md` has a heading for "Succession (The Promotion System):", but zero text underneath. It is completely undefined.
4. **ClaimTags**: Mentioned as distinct from item ownership and used for zone control, but the mechanics for placing, validating, or challenging them are undefined.
5. **Caravans**: Exists in the content catalog and `ecs_architecture`, but their routing, dispatch logic, and actual movement behaviors are undefined.
6. **Grievance accumulation**: Defined as a list on the RelationshipState, but there is no severity scale, decay rate, or threshold for war.
7. **War-time job generation**: Nowhere defined in the entire documentation suite.
8. **Job_Chat gossip**: Mentioned as a diegetic bark and memory propagator, but the unioning of memory lists has no performance bounds defined (only noted as a flaw in reviews).
9. **Profession assignment**: Nowhere defined in the entire documentation suite.

## Questions the specs cannot answer
1. How does a single LLM request failure (e.g., timeout) get handled without permanently leaving `is_request_in_flight` as true?
2. If the 3 most recent events are identical to the top 3 most heavily weighted events, should the prompt builder deduplicate them or send duplicates?
3. How is a `Schism` physically executed? Do entities instantly change colors? Do they fight their former friends immediately?
4. What is the criteria for a "war-time job" versus a normal job, and how are they generated?
5. Who or what decides to assign a profession to a Tier-2 entity, and what does it cost?

## What the specs get RIGHT
1. **Centralized Authority**: The `architecture_decisions.md` cleanly centralizes cross-cutting concerns, and `component_and_field_registry.md` provides a rigorous, single source of truth for data structures (like standardizing `EntityHandle` to a 64-bit int), preventing drift.
2. **Garbage Collection (The Taxes)**: The conceptual design of the Interregnum Entropy and Swarm Taxes smartly addresses long-horizon simulation bloat by operating on ledgers and abstract hard caps rather than simulating decay for every physical entity.
3. **Strict Validation**: Step 3's Validation Gate correctly isolates the simulation from the LLM's non-determinism and hallucinations, ensuring the game falls back to a safe, defensible state (`FORTIFY`) when given garbage or missing targets.
