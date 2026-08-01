# Implementation Audit — Sprint 3 & 3.5
Auditor: Gemini 3.1 Pro via Antigravity IDE
Commit audited: 5506479
Date (UTC): 2026-08-01T06:58Z

## Reproduction
| Check | Claimed | Observed |
|---|---|---|
| Test scripts | 28 | 28 |
| Tests passing | 375 | 375 |
| gdlint | clean | clean |
| Boot sentinel | present | present |

## Verdict
The Sprint 3 implementation successfully adds the core pathing, reasoning, and death-loop machinery required, and testing invariants are strictly upheld. However, the Sprint 3.5 "Consequences" implementation is vastly overstated, missing major mechanics (Schisms, Trade Missions, Brawls) specified in the architecture document without acknowledging the gaps. There are also several minor issues such as unbounded caches and unread objective targets.

## Claim ledger
| ID | Verdict | Evidence |
|---|---|---|
| C-A1 | UPHELD | `GridPathfinder.find_path()` checks `sampler.solid_at_world` |
| C-A2 | UPHELD | Tested by mutation on `grid_pathfinder.gd`; test robustly fails |
| C-A3 | UPHELD | `STEPS` is exactly the 4 orthogonal directions |
| C-A4 | UPHELD | `_steer_active` applies horizontal velocity, `_advance_simulated` advances analytically |
| C-A5 | UPHELD | `_steer_active` preserves `ECSManager.velocity_of(row).y` |
| C-A6 | UPHELD | `LocomotionSystem.run` tracks `budget = MAX_PATHS_PER_TICK` |
| C-A7 | UPHELD | Route state stored in `LocomotionComponent.waypoints` |
| C-B1 | UPHELD | `JOB_TEMPLATES.get(objective)` |
| C-B2 | UPHELD | Planner breaks assignment loop at `MAX_JOBS_PER_FACTION` |
| C-B3 | UPHELD | `job.is_latched()` continues loop |
| C-B4 | UPHELD | `_open_tile` bounds search up to 24 tries for walkable space |
| C-B5 | UPHELD | `body.is_alive()` check before assigning jobs |
| C-B6 | UPHELD | `GameLoopManager` line 215 passes `core.current_objective` |
| C-B7 | UPHELD | `_best_action_for` explicitly matches profession |
| C-C1 | UPHELD | Passed test `test_the_game_reasons_with_no_endpoint_configured` |
| C-C2 | UPHELD | Queue stores `int` handles, builds prompt in `pump()` |
| C-C3 | UPHELD | `_in_flight` tracks singular active request |
| C-C4 | UPHELD | bounded by `MAX_PENDING`, deduplicates via `_queued` |
| C-C5 | UPHELD | `pump()` skips dead leaders without hitting budget |
| C-C6 | UPHELD | `PromptBuilder.salient_memories` limits to 3 top weight, 3 top recent |
| C-C6b| UPHELD | Sort functions strictly use 3 fields, tiebreaking on `event_id` |
| C-C7 | UPHELD | `valid_targets` enumerates `PLAYER_FACTION_ID` explicitly |
| C-C8 | UPHELD | `LLMResolutionSystem.resolve` used identically across providers |
| C-C9 | UPHELD | `OpenAICompatibleProvider._finish({})` for all failures |
| C-C10| UPHELD | Manual analysis of `test_reasoning.gd` confirms test asserts target reset |
| C-C11| UPHELD | `on_timeout` returns `core.current_objective` |
| C-C12| UPHELD | `create_if_configured` ensures both env vars exist |
| C-D1 | UPHELD | Corpse is new row via `allocate_entity()` |
| C-D2 | UPHELD | Tested by manual analysis on `test_ecs_lifecycle.gd` |
| C-D3 | UPHELD | `PLAYER_INPUT` removed before emitting signals |
| C-D4 | UPHELD | `_spill_inventory` removes `OWNERSHIP` and assigns to corpse |
| C-D5 | UPHELD | `on_player_death` is single point of failure |
| C-D6 | UPHELD | `test_death_loop.gd` explicitly asserts taxes and caps |
| C-D7 | UPHELD | `RNGService.randf_in(&"economy")` used for junk sweep |
| C-D8 | UPHELD | Schema checks and explicit component capture via `capture()` |
| C-D9 | UPHELD | `DAGEdge` appended for player death |
| C-D9b| UPHELD | Corrected `KILLED_BY` edge properly set |
| C-D10| UPHELD | `paused = true` in `GameLoopManager` |
| C-D11| UPHELD | Grievance array preserved, score decays to 30% |
| C-S1 | UPHELD | Conditionally places stairs depending on bounds |
| C-S2 | UPHELD | Lands on opposite stair in `change_floor` |
| C-S3 | UPHELD | `current_floor`, `player_chunk_id`, `active_chunk` synchronized |
| C-S4 | UPHELD | Floor filter present in `test_stairs_and_floors.gd` |
| C-P1 | UPHELD | `ReputationSystem` runs off of `take_witness_events()` |
| C-P2 | UPHELD | `adjust` lowers score based on event severity |
| C-P3 | UPHELD | Constants reflect severe scale for murder |
| C-P4 | UPHELD | Scale multiplied by `event.confidence` |
| C-P5 | UPHELD | Verified via `test_reputation.gd` |
| C-P6 | UPHELD | Short circuits if `witness_faction == offender_faction` |
| C-P7 | UPHELD | Memory clamped to 24, grievances to 8 |
| C-P8 | UPHELD | `clampf` uses `SCORE_MIN`/`MAX` |
| C-P9 | UPHELD | Status check ensures single emit in `test_reputation.gd` |
| C-P10| UPHELD | Rate-limited spread uses event ID deduplication |
| C-P11| UPHELD | Reasoner tests assert FORTIFY on being wronged |
| C-X1 | UPHELD | 375 tests passing |
| C-X2 | UPHELD | `project.godot` specifies `window/size/mode=2` |
| C-X3 | UPHELD | No Godot physics nodes used in `ecs/` |
| C-X4 | UPHELD | No wall-clock APIs used in `ecs/` |
| C-X5 | UPHELD | `test_every_registry_enum_matches_the_code` enforces this |

## Findings
### [MAJOR] Unbounded cache dictionary causing memory leak
- **Claim affected:** NEW (C-C4 bounds queue, but cache is unbounded)
- **Where:** `ecs/llm/reasoning_queue.gd:40`
- **Evidence:** `ReasoningQueue._cache` is populated with `_cache[key] = response` but is never pruned. 
- **Failure scenario:** The game caches every unique LLM prompt response indefinitely "for the duration of a run (ADR-5 cost control)". Since new events continually alter prompts over 500 years of history, this cache will grow without bound, causing a memory leak.
- **Severity rationale:** Unbounded memory growth degrade a real session over time.

### [MAJOR] Faction targets ignored after LLM reasoning
- **Claim affected:** NEW
- **Where:** `ecs/components/faction_core_component.gd` and `ecs/systems/faction_planner.gd`
- **Evidence:** `objective_target` is declared in `FactionCoreComponent` and set by `LLMResolutionSystem`, but `FactionPlanner` never reads it. 
- **Failure scenario:** When the reasoner decides to `RAID_FACTION` against a specific target, the planner uses the objective but never uses the `objective_target`, making the faction marshal and march on a randomized arbitrary point instead.
- **Severity rationale:** Major mechanics are completely disconnected despite being "completed".

## Vacuous or weak tests
Tests were validated via manual source code analysis or manual background mutations, none were found to be completely vacuous. C-A2 failed appropriately when the pathfinder was mutated to return `[]` instead of a partial route on budget exhaustion. Other tested claims (C-C10, C-D2, C-D6, C-P5, C-P9, C-S4) appear correctly designed to test their claims and fail when the underlying logic is removed or inverted.

## Unbounded work
- `ReasoningQueue._cache` grows without bound indefinitely for every unique prompt.

## Declared-gap audit (§4b)
| Declared gap | Really absent? | Notes |
|---|---|---|
| G-1 to G-6 | yes | Confirmed absent |
| Grievance accumulation | NO - It exists | Implemented |
| Job_Chat gossip | NO - It exists | System pass |
| Profession assignment | NO - It exists | In planner |
| War-time job gen | yes | Partial only |
| Loyalty | yes | Field only |
| Prestige | yes | Field only |
| Succession by prestige | yes | Absent |
| ClaimTags | yes | Absent |
| Caravans | yes | Absent |

### Undeclared gaps found
- **The Schism Mechanic:** Listed in `scope_and_milestones.md` under Sprint 3.5, completely missing.
- **Trade Mission Jobs:** `JOB_TEMPLATES` lacks Trade Mission objectives, despite it being in the architectural docs for this sprint.
- **Brawls (Territorial Skirmishes):** Factions are supposed to brawl over neutral resource sources, completely missing from implementation.

### Dead code found
- `FactionCoreComponent.objective_target` is written but never read.
- `ReasoningQueue.budget_exhausted` is set but never read.

## Sprint 3.5 scope assessment
I strongly agree with the verdict that the commit message "implement Sprint 3.5" is overstated. The auditor's own assessment is actually too generous. The implementation missed several major features like Schisms, Trade Missions, and Brawls completely, while failing to declare them missing in the gap audit. "Consequences" is the only honest assessment of what was delivered.

## What is genuinely well built
1. The handling of the Player's death correctly updates the actual graph logic by generating a synthetic DAGEdge for history. This makes it part of the generated world without violating constraints.
2. Grid pathfinder cleanly returns partial paths to the closest heuristic node when max expansions are hit, avoiding stalling behavior.
3. Invariant test `test_forbidden_apis.gd` dynamically parsing the markdown registry to ensure `ECSEnums` is strictly conforming is a robust way to prevent doc drift.
