# Implementation Audit - Sprint 3 & 3.5
Auditor: GPT-5.5 via Copilot CLI
Commit audited: 5506479
Date (UTC): 20260801-0638Z

Disclosure: I accidentally saw one `rg` result line from an existing input-audit result while
searching `docs/` broadly. I did not open any `INPUT-AUDIT-RESULT`, `OUTPUT-AUDIT-RESULT`, or
`TRIAGE` file, and no finding below relies on that accidental line.

## Reproduction

| Check | Claimed | Observed |
|---|---|---|
| Test scripts | 28 | 28 |
| Tests passing | 375 | 375 passing, 9184 asserts, 4.889s |
| gdlint | clean | clean for `ecs singletons ui viewer tests` |
| Boot sentinel | present | `ECS_BOOT_OK` printed |
| Render smoke | not in table, required by procedure | `godot --write-movie /tmp/ambition_audit_frame.png --fixed-fps 10 --quit-after 30 res://viewer/Main.tscn` wrote 30 PNG frames and printed `ECS_BOOT_OK` |

Baseline command:

```bash
godot --headless --import
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
for d in ecs singletons ui viewer tests; do gdlint "$d"; done
godot --headless --quit-after 120 res://viewer/Main.tscn 2>&1 | grep ECS_BOOT_OK
```

## Verdict

The baseline is green, but two implementation claims are false in production paths: timeout/refusal responses change objectives to `FORTIFY`, and fatal generic damage can turn row 0 into a corpse before `DeathLoopSystem` runs. Sprint 3.5 is still accurately described as overstated, and I found additional undeclared Sprint 3 gaps around active memories, declaration gossip, weekly cadence, remote authentication, and registry component drift. The high-risk mutation tests mostly caught their targets, but several tests prove isolated helpers rather than the wired behaviour.

## Claim ledger

| ID | Verdict | Evidence |
|---|---|---|
| C-A1 | UPHELD | `ecs/systems/grid_pathfinder.gd:35-82`; `tests/test_pathfinding_and_movement.gd` passed. |
| C-A2 | UPHELD | `grid_pathfinder.gd:18,52,82`; mutation returning `[]` for partial paths failed `test_a_search_is_bounded_and_degrades_to_a_partial_route`. |
| C-A3 | UPHELD | `grid_pathfinder.gd:23-25` has only four cardinal steps. |
| C-A4 | UPHELD | `locomotion_system.gd:61-82`; Active writes velocity, Simulated advances position. |
| C-A5 | UPHELD | `locomotion_system.gd:76` preserves existing `velocity.y`. |
| C-A6 | UPHELD | `locomotion_system.gd:23,45,103-121`; test passed. |
| C-A7 | UPHELD | `ecs/components/locomotion_component.gd:13-22,31-34` stores route state on the component. |
| C-B1 | UPHELD | `faction_planner.gd:15-20,54`. |
| C-B2 | UPHELD | `faction_planner.gd:39,65`. |
| C-B3 | UPHELD | `faction_planner.gd:99-100`; test passed. |
| C-B4 | UPHELD | `faction_planner.gd:131-154`; test passed for walkable assigned destinations. |
| C-B5 | UPHELD | `faction_planner.gd:114-124`. |
| C-B6 | UPHELD | `singletons/GameLoopManager.gd:214-215`; objective is passed into `planner.plan`. |
| C-B7 | UPHELD | `faction_planner.gd:25-34,84-88`; tests passed. |
| C-C1 | UPHELD | `ecs/llm/reasoning_queue.gd:43-44`; `tests/test_reasoning.gd:test_the_game_reasons_with_no_endpoint_configured` passed. |
| C-C2 | UPHELD | `reasoning_queue.gd:36-37,73-91` stores handles and builds prompt in `pump`. |
| C-C3 | UPHELD | `reasoning_queue.gd:64-73,102-108`; stalling-provider test passed. |
| C-C4 | UPHELD | `reasoning_queue.gd:19,49-57`; queue is capped and duplicate handles are skipped. |
| C-C5 | UPHELD | `reasoning_queue.gd:77-80`; dead-queued leader test passed. |
| C-C6 | UPHELD | `prompt_builder.gd:96-109,184-189`; applies to `FactionCoreComponent.faction_memory` only; see undeclared gap for active `MemoryComponent`. |
| C-C6b | UPHELD | `prompt_builder.gd:114-136` and `faction_core_component.gd:86-101` use total tie-breaks. Third single-field candidates are reported below. |
| C-C7 | UPHELD | `prompt_builder.gd:141-166`; player target inserted first. |
| C-C8 | UPHELD | `reasoning_queue.gd:106-111` routes every provider response to the same callback; `llm_resolution_system.gd:36-76` does not branch by provider. |
| C-C9 | UPHELD | `LLMProvider.request` contract says empty dictionary on failure; `openai_compatible_provider.gd:83,97,101,105` returns `{}` on request/HTTP/parse failures. |
| C-C10 | UPHELD | `llm_resolution_system.gd:56-67`; mutation making every target valid failed hallucinated/destroyed target tests. |
| C-C11 | FALSE | `llm_resolution_system.gd:46-47` applies `FORTIFY` to an empty response; `on_timeout` exists at line 80 but `rg on_timeout` finds only the unit test. Temporary queue-path repro failed: `[0] expected to equal [1]`, proving `RAID_FACTION` became `FORTIFY`. |
| C-C12 | UPHELD | `openai_compatible_provider.gd:34-45,51`; endpoint+key gate and key-free `describe()`. The configured remote path is nevertheless broken; see findings. |
| C-D1 | FALSE | `action_resolution_system.gd:118-135,158-168` converts any fatal fall row into a corpse in place. Temporary GUT repro failed: `row 0 should not become a corpse before DeathLoopSystem runs`. |
| C-D2 | UPHELD | `death_loop_system.gd:231-235`; mutation removing `bump_generation` failed stale-handle tests. |
| C-D3 | OVERSTATED | `death_loop_system.gd:59-63` severs control first when `on_player_death` is called directly, but fatal generic damage reaches `_convert_to_corpse` first; see C-D1/C-D5. |
| C-D4 | UPHELD | `death_loop_system.gd:129-145`. |
| C-D5 | FALSE | Player death is checked in `GameLoopManager.gd:166-179`, but generic fatal melee/fall also converts corpses in `action_resolution_system.gd:113,135,158`. |
| C-D6 | UPHELD | `death_loop_system.gd:162-180`; mutation `WEALTH_RETAINED = 1.00` failed the entropy-tax test. |
| C-D7 | UPHELD | `death_loop_system.gd:220-223`; seeded RNG test passed. |
| C-D8 | UPHELD | `lineage_journal.gd:21-112`; death-loop journal tests passed. |
| C-D9 | UPHELD | `death_loop_system.gd:253-269`; tests passed. |
| C-D9b | UPHELD | `ecs_enums.gd:36-41`, `component_and_field_registry.md:74-80`, `death_loop_system.gd:262-268`; tests passed. |
| C-D11 | UPHELD | `death_loop_system.gd:194-205`; tests passed for decay, status update, and non-player relationships untouched. |
| C-D10 | UPHELD | `GameLoopManager.gd:166-179` sets `paused = true` after `on_player_death`. |
| C-S1 | UPHELD | `floor_generator.gd:196-207`; tests passed. |
| C-S2 | UPHELD | `World.gd:105-124`; tests passed. |
| C-S3 | UPHELD | `World.gd:114-133`; tests passed. |
| C-S4 | UPHELD | `ECSManager.gd:330-335`, `GameLoopManager.gd:129-133`; mutation removing floor filter failed two floor tests. |
| C-P1 | UPHELD | `action_resolution_system.gd:101-105`, `GameLoopManager.gd:147-153`, `perception_system.gd:223-256`; combat-report tests passed. |
| C-P2 | UPHELD | `reputation_system.gd:60-82`; test passed. |
| C-P3 | UPHELD | `reputation_system.gd:18-23`; test passed. |
| C-P4 | UPHELD | `reputation_system.gd:68`; test passed. |
| C-P5 | UPHELD | `reputation_system.gd:73-80`; mutation spreading grievances to all faction cores failed `test_one_factions_grudge_is_not_anothers`. |
| C-P6 | UPHELD | `reputation_system.gd:73-75`; test passed. |
| C-P7 | UPHELD | `reputation_system.gd:110-113,190-204`; tests passed for grievance/gossip bounds. |
| C-P8 | UPHELD | `reputation_system.gd:26-27,105`; test passed. |
| C-P9 | UPHELD | `reputation_system.gd:81-86`; mutation removing the crossing guard failed repeated-hostility tests. |
| C-P10 | UPHELD | `reputation_system.gd:42,146-180`; gossip tests passed. |
| C-P11 | UPHELD | `prompt_builder.gd:176-181`, `heuristic_provider.gd:62-70`; test passed. |
| C-X1 | UPHELD | Baseline: 28 scripts, 375 passing tests, gdlint clean, `ECS_BOOT_OK`. |
| C-X2 | UPHELD | `project.godot:44` has `window/size/mode=2` (maximized window). |
| C-X3 | UPHELD | `rg` found banned physics strings only in comments/tests; mutation adding a real `move_and_slide` string failed `test_no_godot_physics_nodes_in_first_party_code`. |
| C-X4 | UPHELD | `rg "Time\\.get_ticks|OS\\.get_ticks|Time\\.get_unix|DateTime|Engine\\.get_frames" ecs` found no matches. |
| C-X5 | UPHELD | `tests/invariants/test_forbidden_apis.gd:160-191`; mutation adding `PLASMA` to registry `Phase` failed the invariant. Component drift is not covered; see findings. |

## Findings

### [BLOCKER] Timeout/refusal path changes the current objective instead of preserving it
- **Claim affected:** C-C11
- **Where:** `ecs/systems/llm_resolution_system.gd:46-47`, `ecs/systems/llm_resolution_system.gd:80`, `tests/test_reasoning.gd:221-228`
- **Evidence:** `rg on_timeout` returns only the method and its unit test. Temporary GUT repro through `ReasoningQueue` with an empty provider response failed:

  ```text
  [Failed]: [0] expected to equal [1]: timeout/refusal path should preserve the current objective
  ```

- **Failure scenario:** A faction currently executing `RAID_FACTION` uses a configured remote provider. The provider times out or refuses, `OpenAICompatibleProvider` returns `{}`, `LLMResolutionSystem.resolve()` treats it as malformed, and the faction silently switches to `FORTIFY`.
- **Severity rationale:** A claim in section 4 is false, and the failure is on the production queue path, not a missing edge-case test.

### [BLOCKER] Fatal player damage can make row 0 a corpse before the death loop
- **Claim affected:** C-D1, C-D3, C-D5
- **Where:** `ecs/systems/action_resolution_system.gd:113,118-135,158-168`, `singletons/GameLoopManager.gd:166-179`, `ecs/systems/death_loop_system.gd:54-66`
- **Evidence:** Temporary GUT repro calling `GameLoopManager.combat.resolve_fall(0, 100.0)` failed:

  ```text
  [Failed]: row 0 should not become a corpse before DeathLoopSystem runs
  ```

- **Failure scenario:** The player dies from a high fall, or from any future NPC melee path using the shared combat system. `ActionResolutionSystem` converts row 0 in place with the `Corpse`/`Filth` tags before `GameLoopManager._check_player_death()` runs, so the reserved player row temporarily is a corpse and `DeathLoopSystem` then creates a second corpse from already-mutated row-0 state.
- **Severity rationale:** This violates the row-0/player identity rule and falsifies the "death detected in exactly one place" claim.

### [BLOCKER] Component registry drift is not enforced and already exists
- **Claim affected:** NEW
- **Where:** `docs/component_and_field_registry.md:53,57-58`, `ecs/components/loose_item_component.gd:4`, `ecs/data_models/component_mask.gd:31,82`
- **Evidence:** The registry lists `FloodSourceComponent`, `ZonePopulationComponent`, and `LLMPromptComponent`, but no matching `ecs/components/*` class exists. Conversely, `LooseItemComponent` is a real component with a query mask bit and runtime storage but is absent from the registry.
- **Failure scenario:** A later sprint implements succession against the registry's `LLMPromptComponent` and cannot attach it; meanwhile save/load, validators, and docs cannot know about `LooseItemComponent` because the canonical registry omits it.
- **Severity rationale:** The audit's architectural constraints say registry violations are automatic blockers. C-X5 protects enum drift only, not component/field drift.

### [MAJOR] Configured remote LLM requests cannot authenticate
- **Claim affected:** NEW
- **Where:** `ecs/llm/openai_compatible_provider.gd:60-76`
- **Evidence:** The request header is built as `"Authorization: ******" % _api_key`. A Godot 4.7.1 formatting check produced:

  ```text
  ERROR: String formatting error: not all arguments converted during string formatting.
  Authorization: ******
  ```

- **Failure scenario:** A user sets both `DELVE_LLM_ENDPOINT` and `DELVE_LLM_API_KEY`. The remote provider is selected, but every HTTP request sends a literal masked header instead of a bearer token, so the configured LLM path fails with 401/error and falls into the malformed-output fallback.
- **Severity rationale:** The no-endpoint mode works, so this is not a local-play blocker, but ADR-5 and Sprint 3 still require a working OpenAI-compatible bridge when configured.

### [MAJOR] Strategy reasoning runs hourly instead of weekly
- **Claim affected:** NEW
- **Where:** `docs/architecture_decisions.md:192`, `docs/llm_reasoner_and_planning_architecture.md:67`, `singletons/GameLoopManager.gd:184-201`
- **Evidence:** ADR-9 says weekly strategy re-evaluation is every 168 macro ticks, and the LLM architecture says time-based reasoning is once per in-game week. `_run_macro_tick()` calls `_think()` every macro tick, and `_think()` submits every faction each hour.
- **Failure scenario:** A remote-enabled game with 14 factions asks for one decision per hour instead of weekly cadence. This burns the 200-call session budget and churns objectives about 168x faster than specified.
- **Severity rationale:** This is an undeclared spec-conformance gap with direct cost and behaviour consequences.

### [MAJOR] PromptBuilder ignores relevant active MemoryComponents
- **Claim affected:** NEW
- **Where:** `docs/sprint_3_implementation_roadmap.md:27`, `docs/llm_reasoner_and_planning_architecture.md:29`, `ecs/llm/prompt_builder.gd:66-81,96-109`
- **Evidence:** Temporary GUT repro gave a same-faction active entity a `MemoryComponent` event `"active member saw the murder"` and called `PromptBuilder.build_context(core, null)`. It failed:

  ```text
  [Failed]: PromptBuilder should include relevant active MemoryComponents
  ```

- **Failure scenario:** A Tier-2 member has a significant active memory that was not summarized into `FactionCoreComponent.faction_memory`. The leader prompt omits it entirely, so the reasoner makes decisions from stale or incomplete context while the active ECS has the information.
- **Severity rationale:** The Sprint 3 roadmap explicitly requires querying `FactionCoreComponent.faction_memory` and relevant active `MemoryComponents`; only the first source is implemented.

### [MAJOR] public_declaration is not stored for gossip
- **Claim affected:** NEW
- **Where:** `docs/llm_reasoner_and_planning_architecture.md:61`, `ecs/systems/llm_resolution_system.gd:74,105`, `ecs/components/faction_core_component.gd:37`
- **Evidence:** The spec says `public_declaration` is stored in the leader's `MemoryComponent` to be repeated via gossip. The resolver writes only `core.last_declaration` and emits `faction_decided`; no `ECSManager.memories` write exists on that path.
- **Failure scenario:** A leader produces a declaration, the overlay can show it immediately, but NPC memory/gossip cannot repeat it later because it never entered the memory system.
- **Severity rationale:** This is a declared LLM architecture behaviour with user-visible narrative consequences, and it is neither claimed nor declared missing in section 4b.

## Vacuous or weak tests

- `tests/test_reasoning.gd:test_a_timeout_keeps_the_current_objective` proves only that the isolated `LLMResolutionSystem.on_timeout()` helper returns the current objective. It does not prove any provider or queue path calls that helper; the temporary queue-path repro failed.
- `tests/test_death_loop.gd` exercises `DeathLoopSystem.on_player_death()` directly but not the actual fatal damage paths that can set player health to zero. `tests/test_playtest_regressions.gd:test_death_is_announced_before_the_body_becomes_a_corpse` covers a non-player target only; the row-0 fatal-fall repro failed.
- Prompt salience tests populate only `FactionCoreComponent.faction_memory`. They do not cover the Sprint 3 requirement to include relevant active `MemoryComponents`; the temporary active-memory repro failed.
- C-X5 is strong for enums but weak as a registry-drift guard overall: it never parses the component table, so missing registry components and extra implementation components pass.

Mutation checks that did fail as intended:

| Claim | Mutation | Result |
|---|---|---|
| C-A2 | returned empty partial paths | `test_a_search_is_bounded_and_degrades_to_a_partial_route` failed |
| C-C10 | made every target valid | hallucinated/destroyed target tests failed |
| C-D2 | removed `ECSManager.bump_generation(row)` | stale player handle test failed |
| C-D6 | changed `WEALTH_RETAINED` to `1.00` | entropy-tax test failed |
| C-P5 | applied witness grievance to all faction cores | per-faction-pair test failed |
| C-P9 | removed hostility crossing guard | repeated-hostility tests failed |
| C-S4 | removed `rows_on_floor` filter | floor-stacking tests failed |
| C-X3 | added a real `move_and_slide` string in `ecs/` | forbidden-API invariant failed |
| C-X5 | added `PLASMA` to registry `Phase` | registry enum invariant failed |

## Unbounded work

- `ReasoningQueue._cache` is an unbounded dictionary (`ecs/llm/reasoning_queue.gd:40,95-110`). A long run with changing prompts can grow it for the entire session. Queue depth and remote session budget are bounded, but cache cardinality is not.
- `GameLoopManager._think()` submits every faction every macro tick (`singletons/GameLoopManager.gd:197-201`), so even with queue caps it creates hourly churn instead of the specified weekly cadence.
- Most other Sprint 3/3.5 loops inspected have explicit caps or are bounded by existing entity/faction caps: A* `MAX_EXPANSIONS`, locomotion `MAX_PATHS_PER_TICK`, planner `MAX_JOBS_PER_FACTION`, gossip `MAX_GOSSIP_PER_TICK`, grievance list cap 8, faction memory cap 24, diplomacy top-K 12, and spatial/perception candidate budgets.

## Declared-gap audit (section 4b)

| Declared gap | Really absent? | Notes |
|---|---|---|
| G-1 per-faction concurrent reasoning cap | yes | `ReasoningQueue.submit()` checks only duplicate handle/in-flight and global `MAX_PENDING`; no per-faction counter. |
| G-2 thinking bark / Diplomatic Ping UX | yes | There is an after-answer feed line (`DebugOverlay._on_faction_decided`) but no pending/thinking bark. |
| G-3 Adventurer's Residence spawn | yes | `DeathLoopSystem.spawn_successor()` calls `World._spawn_player(chunk)`; no residence entity/zone exists. |
| G-4 `reason_summary` capped at 200 chars | yes | Prompt requests it; resolver never reads or clamps `reason_summary`. |
| G-5 priority among weekly/crisis/diplomatic triggers | yes | No trigger type or priority queue exists. Additionally, the weekly cadence itself is not implemented. |
| G-6 Sprint 3 performance gate for death -> respawn and queue budget | yes | Perf tests cover micro tick/cold boot, not the death-respawn 5s budget. |
| Grievance accumulation | NO | Implemented in `ReputationSystem._record()` and `adjust()`. |
| Job_Chat gossip | partial | Gossip exists as `ReputationSystem.spread_gossip()`, not as an NPC job named `Job_Chat`. |
| Profession assignment | NO | Implemented in `FactionPlanner._best_action_for()` and tests. |
| War-time job generation | partial | Hostile objectives map to templates, but there is no wartime state/mobilisation/draft. |
| Loyalty | yes, behaviour absent | `SocialIdentityComponent.loyalty` exists but is not read by systems. |
| Prestige | yes, behaviour absent | `SocialIdentityComponent.prestige` exists but is not read by systems. |
| Succession by prestige | yes | No `SocialSystem`, promotion path, or `LLMPromptComponent` implementation exists. |
| ClaimTags | yes | No claim tag/component/field implementation found. |
| Caravans | yes | Only `MaterializationPolicy.CARAVAN_MANIFEST` / comments exist; no caravan entity/route/trade loop. |

### Undeclared gaps found

- PromptBuilder omits relevant active `MemoryComponents`, despite Sprint 3 roadmap Step 2.
- `public_declaration` is not stored into a leader `MemoryComponent`, despite the LLM architecture's gossip contract.
- Time-based reasoning runs hourly, not weekly.
- Configured remote LLM requests cannot authenticate because the Authorization header is the literal masked string.
- Registry component drift exists and is not covered by C-X5: missing registry components (`FloodSourceComponent`, `ZonePopulationComponent`, `LLMPromptComponent`) and extra runtime component (`LooseItemComponent`).
- ADR-5 still says endpoint/model live in a committed config file with env overrides, while implementation reads endpoint/model only from environment variables (`OpenAICompatibleProvider.gd:35-41`). I did not elevate this separately because the same ADR's "AS IMPLEMENTED" note emphasizes env-gated construction.

### Dead code found

- `LLMResolutionSystem.on_timeout()` is production-dead: `rg on_timeout` finds only the method and `tests/test_reasoning.gd`.
- `MemoryComponent.most_salient()` is production-dead: `rg most_salient\\(` finds only its own declaration. Its comment says it is for the LLM salience filter and gossip picker, but both use other paths.
- Single-field `sort_custom` candidates beyond the fixed prompt/diplomacy sorts: `MemoryComponent.most_salient()` sorts only by weight, and `PerceptionSystem._evaluate_sight()` sorts only by distance. The former is currently dead; the latter is bounded by `MAX_CANDIDATES_PER_OBSERVER` and could select a different equal-distance subset if tie order changes.

## Sprint 3.5 scope assessment

I agree with section 4b's "overstated" verdict. The implemented consequence layer is real and useful - grievances, per-pair reputation, bounded gossip, profession-aware planning - but it is not the full Sprint 3.5 scope named in `scope_and_milestones.md`. Loyalty, schism, succession by prestige, ClaimTags, and caravans are either field-only or absent, so "Sprint 3.5: consequences" is fair while "Sprint 3.5 complete" is not.

## What is genuinely well built

- The high-risk pathfinding, stale-handle, floor-filter, reputation-pair, and registry-enum tests all failed under targeted mutation, which is the right failure mode for the bugs they defend.
- The no-endpoint reasoner path is not a stub: `HeuristicProvider` uses population, food, strength, recent attack state, and valid targets, and the full baseline suite runs through that default.
- The death-loop journal boundary is clean when entered through `DeathLoopSystem`: insight/runes merge forward, inventory does not, corrupt journals start fresh, and newer schemas are refused.
- The floor transition implementation is coherent: generated stair placement, opposite-stair landing, sampler floor, player chunk id, active chunk, and floor-filtered spatial query all move together and are well covered.
- The consequence chain is connected for melee crimes: combat reports witnessable acts, perception filters witnesses by LoS/confidence, reputation records bounded per-pair grievances, gossip is deduped/rate-limited, and the heuristic reasoner reacts to recent attack memory.
