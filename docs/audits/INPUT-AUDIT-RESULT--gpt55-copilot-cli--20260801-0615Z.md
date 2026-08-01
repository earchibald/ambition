# Input Specification Audit — Sprint 3 & 3.5
Auditor: GPT-5.5 via GitHub Copilot CLI
Commit audited: 618271a
Date (UTC): 20260801-0615Z

## Verdict
Partially: the post-triage Sprint 3 roadmap is more testable than the original, but it still contains Tier-1 contradictions and several success states that cannot be falsified from the sprint spec alone. Sprint 3.5 remains not buildable from its input specification: it is still a single ownership-map row plus broad architecture prose, with no sprint roadmap, gate, or acceptance criteria. The strongest parts are the ADR/registry authority model, the memory decay/cap model, and the corrected RUNNING.md and Step 6 acceptance clauses.

## Severity summary
| Severity | Count |
|---|---:|
| BLOCKER | 3 |
| MAJOR | 7 |
| MINOR | 2 |

## Findings

### [BLOCKER] Sprint 3.5 still has no buildable sprint specification
- **Where:** `docs/scope_and_milestones.md:102-103`; absent from `docs/invariants_and_test_strategy.md:148-152`
- **Quote:** > `| **3.5 "The Body Politic"** | **Previously unowned.** Loyalty, schism, succession by prestige, ClaimTags, caravans, grievance accumulation, war-time job generation, Job_Chat gossip, profession assignment |`
- **Problem:** Sprint 3.5 is still a single ownership row naming nine features. There is no Sprint 3.5 roadmap, scaffolding, step order, gate, performance budget, or acceptance criterion.
- **Consequence:** Any subset can be implemented and called Sprint 3.5; the specs cannot determine pass/fail.
- **Suggested remedy:** Create a dedicated Sprint 3.5 roadmap/scaffolding pair and a Sprint 3.5 gate that enumerates each named item, required data structures, failure modes, and tests.

### [BLOCKER] ADR-5 is still contradicted by active Sprint 3/LLM spec text
- **Where:** `docs/architecture_decisions.md:114-124`; `docs/sprint_3_technical_scaffolding.md:6-8`; `docs/llm_reasoner_and_planning_architecture.md:77-81`
- **Quote:** > `NullLLMProvider is promoted from a test double to a shipped provider. It is selected automatically when no endpoint is configured, and it must produce play-viable behaviour, not a canned FORTIFY payload.`
- **Problem:** The scaffolding still says "Tests inject a NullLLMProvider stub", and the LLM architecture still says "Tests/CI inject a NullLLMProvider stub returning a canned valid FORTIFY payload." A later correction in the scaffolding supersedes one local line, but the contradictory Tier 3 architecture text remains active.
- **Consequence:** A future implementer can follow the LLM architecture and build the exact superseded behavior ADR-5 forbids: a canned fallback that passes CI but does not support the no-endpoint product mode.
- **Suggested remedy:** Replace all remaining "stub/canned FORTIFY" language with "shipped heuristic provider selected when no endpoint is configured; outputs are generated from real faction state and must satisfy the no-endpoint play-session acceptance test."

### [BLOCKER] Technical scaffolding still violates ADR-19's packed-handle and row-query contract
- **Where:** `docs/component_and_field_registry.md:12-22`; `docs/architecture_decisions.md:407-410`; `docs/sprint_3_technical_scaffolding.md:20-35`; `docs/sprint_3_technical_scaffolding.md:107-114`
- **Quote:** > `query(mask) -> PackedInt32Array of dense row indices, never handles.`
- **Problem:** The scaffold declares `Array[EntityHandle]` and `func request_reasoning(entity: EntityHandle)`, then iterates `ECSManager.query(...)` as `item_id` handles passed to `has_tag`, `has_component`, and `destroy_entity`.
- **Consequence:** The spec tells implementers to copy a pre-ADR-19 API shape that ADR-19 explicitly rejected for correctness and performance.
- **Suggested remedy:** Rewrite the example to use packed `int` handles only at cold boundaries and to iterate query row indices with column access plus explicit row-to-handle conversion only when destroying or emitting events.

### [MAJOR] Step 1's 60fps success state is not falsifiable
- **Where:** `docs/sprint_3_implementation_roadmap.md:13-17`; `docs/scope_and_milestones.md:109-115`
- **Quote:** > `Success State: 5 faction leaders request a thought. They enter the queue. The engine fires them one by one. The game continues running at 60fps.`
- **Problem:** The sentence does not define scenario size, provider mode, timeout behavior, measurement window, allowed frame drops, or whether "60fps" is wall-clock, headless tick cadence, or rendered frame rate.
- **Consequence:** Testers cannot distinguish a queue correctness pass from a performance pass, and implementers can satisfy the sentence with incomparable local measurements.
- **Suggested remedy:** Replace with a measurable gate: "Under the debug scenario with 5 leaders and the heuristic provider, all requests complete or fallback within N simulated seconds, max queue depth is bounded, and p95 frame/tick time stays under the relevant ADR-10/scope budget."

### [MAJOR] Reasoning queue limits and prioritization remain unspecified
- **Where:** `docs/sprint_3_implementation_roadmap.md:13-17`; `docs/llm_reasoner_and_planning_architecture.md:63-71`; `docs/architecture_decisions.md:145-146`
- **Quote:** > `keep the staggered queue + a per-session request budget`
- **Problem:** The docs require a queue and mention a budget, but never define max queue depth, timeout duration, per-session cap, stale-entry eviction, duplicate coalescing by faction vs leader, or priority among weekly, crisis, and diplomatic triggers.
- **Consequence:** One faction can flood the global queue; crisis requests can starve behind routine weekly work; rate-limit safety cannot be tested.
- **Suggested remedy:** Add queue constants and ordering rules: max depth, per-faction cap, priority order, timeout, stale-handle eviction, and exact requeue/fallback cadence.

### [MAJOR] Step 4's death success state depends on unscheduled NPC behavior
- **Where:** `docs/sprint_3_implementation_roadmap.md:56-75`; `docs/meta_progression_and_death_loop_architecture.md:17-26`
- **Quote:** > `Success State: The player dies, the camera detaches, and they watch their killer physically pick up their dropped Iron Sword.`
- **Problem:** Corpse creation and inventory spill are Sprint 3 work, but "killer physically pick up" requires an alive killer, pickup intent, inventory capacity, path/reach behavior, and item choice. The spec does not define fall/poison/starvation deaths, no-killer deaths, empty inventory, or a second death trigger during the transition.
- **Consequence:** Death can work while the success state fails for reasons outside Sprint 3, or creature/NPC behavior can be invented just to satisfy a prose example.
- **Suggested remedy:** Scope the success state to Sprint 3-owned outputs: input detaches once, corpse/remains entity exists at final tile, spilled items/manifests are reachable, old handle is stale, and no-killer deaths record a valid neutral death edge.

### [MAJOR] The player-death DAG edge uses a non-registry edge shape
- **Where:** `docs/sprint_3_implementation_roadmap.md:93-95`; `docs/sprint_3_technical_scaffolding.md:92-94`; `docs/component_and_field_registry.md:71-74`
- **Quote:** > `DAG.add_event_edge(0, "Killed_By", last_attacker_id)`
- **Problem:** The registry's `EdgeType` enum contains `FOUNDED, DESTROYED, CONQUERED, MIGRATED_TO, FORGED, ALLIED_WITH`; it does not include `KILLED_BY`/`Killed_By`. The roadmap says to add a Player Death Event Edge but does not define whether this is an enum edge, an `EVENT_ABSTRACT` node, or a payload on an existing edge.
- **Consequence:** Implementers must invent an unregistered edge type or overload an unrelated enum, creating registry drift in a persistence-critical structure.
- **Suggested remedy:** Add a canonical death-history representation, e.g. `NodeType.EVENT_ABSTRACT` with payload `{event_kind: PLAYER_DIED, killer, location, tick}` and a registered edge type, or add `KILLED_BY` to the registry.

### [MAJOR] Interregnum reputation decay is numerically ambiguous
- **Where:** `docs/meta_progression_and_death_loop_architecture.md:44-50`; `docs/architecture_decisions.md:194-197`
- **Quote:** > `on each Interregnum pass: - Decay every faction's diplomacy score toward Faction 0 by 60-75% toward neutral`
- **Problem:** Interregnum is 12 monthly passes. The spec does not say whether 60-75% is applied once across the year or once per monthly pass.
- **Consequence:** A hostile score can be partially softened or virtually erased depending on interpretation; both readings match the wording.
- **Suggested remedy:** State either the annual retained fraction and monthly multiplier, or explicitly state that each monthly pass applies the full decay.

### [MAJOR] Swarm cap is ambiguous between total chunk counter and per-species population
- **Where:** `docs/sprint_3_implementation_roadmap.md:87-91`; `docs/sprint_3_technical_scaffolding.md:115-119`; `docs/component_and_field_registry.md:122-125`
- **Quote:** > `cap all Tier 1 Swarm populations (Rats, Spiders) to a maximum of 10 per chunk`
- **Problem:** The registry defines `ChunkData.swarm_population:int` as one chunk counter and `ZonePopulationComponent.population_by_species` for species-specific abstraction. The Sprint 3 prose names species but the scaffold clamps only the single chunk counter.
- **Consequence:** Implementers can cap 10 rats+spiders total, 10 per species, or only the generic counter, with different ecology outcomes.
- **Suggested remedy:** Specify "10 total in `ChunkData.swarm_population`" or define a per-species cap using `ZonePopulationComponent.population_by_species`.

### [MAJOR] Sprint 3 performance budgets are named but not assigned to acceptance tests
- **Where:** `docs/scope_and_milestones.md:109-115`; `docs/architecture_decisions.md:199-225`; `docs/sprint_3_implementation_roadmap.md:17`; `docs/sprint_3_implementation_roadmap.md:95`
- **Quote:** > `Death -> respawn (Interregnum) | <= 5 s`
- **Problem:** The scope contract adds a death-to-respawn budget and ADR-10 gives frame/tick budgets, but Sprint 3 does not state which scenario, metric, hardware, provider mode, or assertion validates them.
- **Consequence:** Sprint 3 can add pathfinding, reasoning queue work, Interregnum passes, and GC without any sprint-owned performance failure signal.
- **Suggested remedy:** Add a Sprint 3 perf gate: seeded death loop completes in <=5s, no-endpoint queue scenario remains inside tick/frame budget, and no new broad scans are introduced in hot paths.

### [MAJOR] The salience correction defines deduplication but not stable ordering
- **Where:** `docs/sprint_3_implementation_roadmap.md:29-35`; `docs/invariants_and_test_strategy.md:148-151`
- **Quote:** > `Deduplicate the combined list by event_id. The filter therefore sends BETWEEN 3 AND 6 memories, not exactly 6.`
- **Problem:** The overlap defect is fixed, but ties and final ordering remain unspecified. There is no rule for equal weights, equal ticks, or whether output order is weight-first then recent, chronological, or original merged order.
- **Consequence:** Prompt output can still vary between implementations or dictionary iteration orders, making the salience test brittle.
- **Suggested remedy:** Define a stable ordering and tie-breaker, e.g. selected set sorted by `(weight desc, tick desc, event_id asc)`.

### [MINOR] Canonical enum examples still drift
- **Where:** `docs/sprint_3_implementation_roadmap.md:52`; `docs/factions_and_social_mechanics_architecture.md:28`; `docs/component_and_field_registry.md:61-68`
- **Quote:** > `Map valid JSON Objective (e.g., RAID)` and `status (Enum: War, Neutral, Trade, Allied)`
- **Problem:** The registry uses `RAID_FACTION` and uppercase `WAR, NEUTRAL, TRADE, ALLIED`.
- **Consequence:** Usually harmless prose, but these strings touch output schemas and content validators.
- **Suggested remedy:** Replace examples with exact registry literals.

### [MINOR] Rune_Stability has no numeric bootstrap value
- **Where:** `docs/sprint_4_implementation_roadmap.md:26-28`; `docs/world_bootstrapping_and_the_overworld_architecture.md:106-108`; `docs/component_and_field_registry.md:41`
- **Quote:** > `If the village is [Dwarven_Refugees], the player starts with Insight[MAT_IRON_SMELTING] and Insight[Rune_Stability].`
- **Problem:** Sprint 4's spell cap uses `MindComponent.insight.get(&"Rune_Stability", 0) * 1.5`, but the bootstrap doc never gives `Rune_Stability` a numeric value or a seed spell complexity that should compile.
- **Consequence:** At zero no spell compiles; at an invented value content authors get inconsistent early spell access.
- **Suggested remedy:** Define a numeric starting value and one minimum viable seed rune/spell complexity.

## Sprint 3.5 specification adequacy

Sprint 3.5 is still inadequate as a sprint specification. The supporting architecture defines several concepts, but the sprint itself is not scoped into steps, acceptance tests, data ownership, or failure policy.

| Named item | Where it is specified | Adequacy |
|---|---|---|
| Loyalty | `factions_and_social_mechanics_architecture.md:32`, `:40`; registry `SocialIdentityComponent.loyalty` | Field and inputs exist; formula, weights, clamps, cadence details, and tests are absent. |
| Schism | `factions_and_social_mechanics_architecture.md:42-48`, cap interaction at `:161-165` | Trigger and consequence exist; "large cluster", split percentage, stockpile selection, faction allocation, and idempotence are absent. |
| Succession by prestige | `factions_and_social_mechanics_architecture.md:50-56`; registry `SocialIdentityComponent.prestige` | More specified than most: highest-prestige Tier 2 gets `LLMPromptComponent` and a reasoning tick. Ties, no-candidate cases, abstracted factions, and inherited state remain absent. |
| ClaimTags | `factions_and_social_mechanics_architecture.md:68-74`, `:105-107`; registry convention `component_and_field_registry.md:133-134` | Defined as zone control distinct from item ownership; tag schema, contested claims, persistence, and query API are absent. |
| Caravans | `factions_and_social_mechanics_architecture.md:62-66`; identity rules in `invariants_and_test_strategy.md:45-48` | Conceptual behavior exists; route cadence, cargo accounting, interception resolution, and LoD manifest contract are not Sprint 3.5-scoped. |
| Grievance accumulation | `factions_and_social_mechanics_architecture.md:28`, `:72-79`, `:89-91`; memory model `:117-150` | Sources and storage exist; severity scale, decay/forgiveness, cap/eviction for grievances, and status thresholds are absent. |
| War-time job generation | `factions_and_social_mechanics_architecture.md:78-83`; template examples in `sprint_3_technical_scaffolding.md:136-145` | Prose names exist; concrete job records, target selectors, counts, preconditions, and tests are absent. |
| Job_Chat gossip | `factions_and_social_mechanics_architecture.md:152-159`; `entity_behavior_and_society_architecture.md:77-79`, `:115-116` | Memory propagation is well bounded by `event_id` and caps; Job_Chat intent schema, frequency, spatial constraints, and debug/test surfaces are absent. |
| Profession assignment | `entity_behavior_and_society_architecture.md:24-28`, `:85-90`; registry `ProfessionComponent` | Profession filtering and an example reassignment ratio exist; initial assignment, vocabulary, costs, invalid/no-worker behavior, and tests are absent. |

## Questions the specs cannot answer

1. Is Sprint 3.5 required to implement all nine named items, or is a declared subset acceptable?
2. What test proves the no-endpoint heuristic provider completes a viable play session?
3. What are the queue depth, timeout, per-session budget, and per-faction fairness rules?
4. What stable order should the salience filter use after deduplicating by `event_id`?
5. What exact records define each JobTemplate and target selector?
6. What happens if a faction leader dies with no eligible Tier 2 successor?
7. Is Interregnum reputation decay 60-75% per month or across the whole year?
8. Is the swarm cap 10 total per chunk or 10 per species?
9. What canonical DAG edge or event payload records player death?
10. What creates and validates the Adventurer's Residence, and what happens if it is missing?
11. What idempotence guard prevents duplicate corpse/interregnum/re-entry work?
12. What scenario proves `Death -> respawn <= 5s`?
13. What numeric `Rune_Stability` value should Day 0 grant?

## What the specs get RIGHT

1. The 2026-08-01 triage fixes several earlier traps directly in the Sprint 3 roadmap: salience overlap, Step 3's unowned equipment dependency, Step 6's missing success state, and the RUNNING.md requirement.
2. ADR-5 is the right product rule: a no-endpoint heuristic provider as a shipped mode removes paid-network dependency from correctness paths.
3. ADR-9 cleanly separates hourly macro ticks from the 12 monthly coarse Interregnum passes, so the month/hour arithmetic is coherent.
4. The memory model in the factions architecture is strong: `event_id`, half-life, core floor, caps, and dedup policy address runaway gossip.
5. The registry gives a useful canonical surface for Sprint 3/3.5 components and enums, especially `FactionCoreComponent`, `SocialIdentityComponent`, `ProfessionComponent`, `MemoryComponent`, `LLMPromptComponent`, `Objective`, and `RelationshipStatus`.
6. The invariant gates correctly identify Sprint 3 essentials: no network in CI, salience filtering, fallback handling, and ledger/counter Interregnum taxes.
