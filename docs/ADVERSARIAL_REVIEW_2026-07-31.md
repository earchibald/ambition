# Adversarial Specification Review - 2026-07-31

**Status:** Addressed in the owning specs on 2026-07-31. No gameplay code was written or changed.
**Scope:** Post-ADR, post-integration review of the current project specification,
implementation scaffolding, process documentation, and repo-facing documentation. This
review assumes `docs/architecture_decisions.md` wins over conflicts.

**Resolution:** The findings below are a historical pre-repair record. See §F for the repair
log. Do not treat sections A-E as current open blockers unless a newer targeted review says a
specific item regressed.

## 0. Executive finding

The original architecture-breaking paradoxes are mostly resolved at the ADR level. The
project is no longer blocked by "we do not know what to build" questions like 2.5D vs 3D,
determinism, player identity, or GOAP-vs-template planning.

The current risk has shifted: **the main specs say the right thing in correction
appendices, but many narrative passages and code scaffolds still teach future agents the
wrong thing.** A coding agent will copy the examples, not the footnotes. That makes the
remaining risk adversarially serious even when the underlying decision is settled.

At review time, I found a small set of engineering-spec gaps that could be drafted without
needing major product decisions:

1. Perception/hearing/witness rules are referenced everywhere but not specified.
2. Persistence is acknowledged as first-class, but it is not assigned to a real spec/sprint.
3. LoD de/materialization needs a non-fungible/equipped/artifact item policy.
4. Mutable tile maps need an AbstractGraph/NavServer invalidation policy.
5. Several core nouns are outside the canonical registry (`Container`, `EnergyComponent`,
   `PerceptionComponent`, `ProfessionTag`, `DiplomacyComponent`, etc.).

Everything else below is mechanical cleanup: update examples, remove stale wording, and make
the registry/ADR impossible to miss.

## Severity scale

- **P0 - Cannot implement safely.** A contradiction or missing system would make Sprint 1
  build the wrong foundation.
- **P1 - High rework/exploit risk.** Buildable, but likely to create bugs, exploits, or
  agent confusion if left in place.
- **P2 - Hygiene/clarity.** Does not block implementation, but wastes context and increases
  onboarding errors.

No new P0 product-decision blocker was found. There are P1 engineering gaps and many P1
copy/paste traps.

---

## A. Truly open engineering-spec items

### A1. Perception, hearing, stealth, and witness rules are load-bearing but unspecified

**Severity:** P1, should land before Sprint 1 AI/combat is implemented.

**Evidence:**
- `sprint_1_technical_scaffolding.md:183-191` spawns `[Ephemeral_Noise_Entity]` and checks
  whether the goblin has the player in its `VisionCone`.
- `the_first_hour_day_0_gameplay_and_transition.md:85` says the goblin's `VisionCone`
  intersects the player.
- `inventory_and_grimoire_mechanics_specification.md:44-52` defines acoustic encumbrance and
  a `StealthSystem`.
- `factions_and_social_mechanics_architecture.md:122-124` makes crime reputation depend on a
  witness perceiving the act.
- `world_bootstrapping_and_the_overworld_architecture.md:118-121` makes `[Guest_Status]`
  witness-gated.
- `material_crafting_and_economy_architecture.md:120` says steam blocks LoS.

**Problem:** The spec relies on perception for combat fairness, stealth, crime, gossip, and
alerts, but there is no `PerceptionComponent`, no hearing rule, no line-of-sight rule, no
awareness state machine, no witness-event record, and no sensory query cadence. Without this,
the implementation will either become omniscient again or create arbitrary one-off checks.

**Recommended repair:**
- Add a perception section to the ECS spec and Sprint 1 scaffolding.
- Add registry entries:
  - `PerceptionComponent { sight_range_m, fov_degrees, hearing_sensitivity, awareness_state,
    last_known_targets }`
  - `SensoryEmitterComponent { noise_radius_m, scent_tags, visibility_modifier }` or fold
    transient sound into `EphemeralComponent` with a typed noise payload.
  - `WitnessEvent { observer, subject, action, location, tick, confidence }`
- Define `PerceptionSystem`:
  - Sight: cone + DDA LoS against `tile_map` / steam / smoke blockers.
  - Hearing: radius from acoustic formula, occluded by walls/materials, emitted as ephemeral
    noise events with TTL.
  - Crime: witness event, then memory/gossip propagation; no global flag.
  - Combat: if target not perceived, investigate last-known/noise location, not direct aggro.
- Add tests later: "unseen crime does not revoke guest status"; "noise behind wall creates
  investigate, not combat"; "steam blocks LoS."

**Open decision needed from human?** No. I recommend the above default unless you object.

### A2. Persistence is first-class but unslotted

**Severity:** P1.

**Evidence:**
- `README.md` says a dedicated Persistence/Serialization workstream is required and not
  slotted into a numbered sprint.
- `architecture_decisions.md` ADR-6 defines full mid-run serialization.
- `ecs_architecture_and_data_layer_specification.md:193-199` lists save payload contents.
- `STATE.md` tracks Persistence implementation as deferred.

**Problem:** Persistence shapes component identity, handles, registry layout, RNG streams,
world-grid ownership, versioning, and save/load tests. If it remains "important but
unslotted," Sprint 2/3 systems will bake in assumptions that are painful to serialize.

**Recommended repair:**
- Create `docs/persistence_and_save_architecture.md`.
- Add a numbered or named workstream before the death loop depends on it. Recommended
  sequence: after Sprint 1 establishes handles/registries and before Sprint 3 death loop
  relies on save/Lineage behavior. Call it **Sprint 2.5: Persistence Contract** or
  **Sprint P: Persistence**.
- Specify:
  - Save root schema and `schema_version`.
  - EntityHandle serialization and entity-index reservation (`Entity 0`, generation values).
  - Component registry serialization order.
  - `WorldGrid`, `tile_map`, `height_map`, `volume_pools`, `wealth ledgers`.
  - DAG runtime edges and compaction state.
  - RNG stream states.
  - Lineage Journal vs run-save ownership.
  - Migration strategy for unknown/new components.

**Open decision needed from human?** Only placement/name if you care. I recommend Sprint 2.5
or Sprint P; the details are mechanical.

### A3. LoD de/materialization can destroy item identity

**Severity:** P1.

**Evidence:**
- `sprint_2_technical_scaffolding.md:146-172` correctly expands de/materialization to all
  faction-owned physical matter, including NPC inventories and loose owned items.
- Faction trade caravans, artifact placement, equipped weapons, player corpse loot, and the
  Residence stash all depend on item identity, not just commodity value.

**Problem:** The D1 fix closes the gold-duplication exploit by sweeping all faction-owned
physical matter into ledgers. But if applied indiscriminately, it can turn unique/equipped
items into fungible ledger entries:

- A named artifact in a leader inventory becomes "some MAT_IRON/MAT_GOLD."
- A guard's equipped sword can disappear into the faction ledger when the chunk downgrades.
- A caravan cargo manifest can be erased, making interception or theft incoherent.
- Containers/stashes can lose nested identity.

**Recommended repair:** Define a `MaterializationPolicy` table:

| Item class | Downgrade behavior |
|------------|--------------------|
| Fungible commodity stack | Convert to faction ledger, destroy physical entity. |
| Equipped item | Keep as serialized item handle attached to owner; do not ledgerize. |
| Unique/artifact/quest item | Keep entity identity in simulated manifest; never fungible. |
| Container/stash contents | Preserve container manifest; only ledgerize explicitly fungible sub-stacks. |
| Caravan cargo | Convert to route manifest with theft/interception hooks; reconstruct on promotion. |
| Unowned junk/filth | Entropy/GC policy. |

Add an `item_class` or `materialization_policy` field to the data model/Sprint 5 schemas and
teach LoD sync to branch on it.

**Open decision needed from human?** No. This is an engineering distinction between
commodities and identity-bearing objects.

### A4. Mutable terrain needs graph/nav invalidation

**Severity:** P1.

**Evidence:**
- `world_and_floor_generation_architecture.md:240-245` says the AbstractGraph built at
  generation is the ECS-owned source of truth for Simulated/Abstracted movement.
- `ecs_architecture_and_data_layer_specification.md:160-170` says Active steering uses
  `NavigationServer3D` baked per Active chunk, while collision/path truth remains in ECS.
- Day 0 mining removes walls; world generation includes collapses/rubble; magic can create
  explosions/fire; future building/barricade systems are implied.

**Problem:** The world is mutable, but the pathing graph and NavServer regions are described
as generation-time products. If a player mines a wall, collapses a tunnel, floods a route, or
creates rubble, Simulated pathing and Active steering can become stale. NPCs may route
through collapsed rock or fail to use newly opened paths.

**Recommended repair:**
- Add `TileMutationSystem` / `TopologyDirtySystem`.
- Any tile solidity/elevation change marks:
  - local chunk `tile_map_dirty`
  - affected AbstractGraph nodes/edges dirty
  - Active NavServer region dirty
  - cached paths invalid if they cross dirty edges
- Rebuild:
  - Micro/Active: collision uses current `tile_map` immediately.
  - Simulated: use old graph until the next safe graph rebuild, but reject dirty edges or
    increase hazard cost.
  - NavServer: asynchronous local rebake; fall back to grid A* until ready.
- Add tests later: "mined wall opens route"; "collapse invalidates route"; "dirty active
  NavServer falls back instead of blocking."

**Open decision needed from human?** No.

### A5. The canonical registry does not cover several core nouns

**Severity:** P1.

**Evidence:** `docs/component_and_field_registry.md` is authoritative, but current docs still
refer to unregistered or inconsistently modeled concepts:

| Concept | Evidence | Why it matters |
|---------|----------|----------------|
| `Container` / capacity | inventory spec, meta stash, fluid pickup | Inventory has `total_volume_used` but no canonical capacity/acceptance model. |
| `FilterTag` component | `inventory_and_grimoire...:32` | Sub-container sorting needs a real component or tag convention. |
| `EnergyComponent` | material forge/stations, world bootstrapping smithy | Heat model replaced ad-hoc energy, but stations still reference this component. |
| `PerceptionComponent` / `VisionCone` | Sprint 1, Day 0, crime witness | Load-bearing; see A1. |
| `DiplomacyComponent` | factions doc, Sprint 3, ADR-12 | Registry folds diplomacy into `FactionCoreComponent.diplomacy`; docs still name a separate component. |
| `PopulationComponent` | ECS tier 1, registry note | Registry has `ChunkData.swarm_population`, but zone population remains ambiguous. |
| `ProfessionTag` / `FactionTag` | behavior/ECS docs | Job filtering and faction membership should be either tags or components, not ad hoc strings. |
| `BestiaryComponent` / `InsightComponent` | magic/meta docs | Registry uses `MindComponent.insight`; old names should be voided. |

**Recommended repair:** Expand the registry or rewrite references. My recommended defaults:
- Add `ContainerComponent { capacity_cm3, accepts_tags, rejects_tags, allow_nested_container }`.
- Replace `FilterTag component` with `ContainerFilterComponent` or fold filters into
  `ContainerComponent`.
- Replace `EnergyComponent` with `HeatSourceComponent` / station thermal fields that use the
  material heat model.
- Keep diplomacy inside `FactionCoreComponent.diplomacy` unless a separate component is
  intentionally desired; update all docs to one name.
- Add `ProfessionComponent { profession:StringName }` and use `SocialIdentityComponent` for
  faction id, not `FactionTag`.

**Open decision needed from human?** No, unless you prefer tag-only profession modeling.

---

## B. High-risk copy/paste traps and contradictions

These are mostly settled decisions that have not been propagated into the main text or code
examples. They should be repaired before an implementation agent starts Sprint 0/1.

### B1. Correction appendices contradict main examples

**Severity:** P1.

**Problem:** Many files have an "Authoritative Corrections" block that says the right thing,
then code below it says the old thing. An agent under time pressure will copy the code.

| Area | Evidence | Required repair |
|------|----------|-----------------|
| Sim tick | `sprint_1_implementation_roadmap.md:29` still says 1Hz. | Change success criteria to 2Hz / `SIM_TICK_RATE = 0.5`. |
| Component examples | `sprint_1_technical_scaffolding.md:66` uses `phase: String = "Solid"`; `:78` uses `next_entity_id`; signals and action targets use bare `int` ids. | Update examples to enums and `EntityHandle`. |
| Grid dimensionality | Sprint 1 CA section says "2D/3D grids." | Say 2D 64x64 + height map only. |
| Active set | `sprint_2_technical_scaffolding.md:107` uses `_get_neighbors_3D()` and "Must account for Z-axis." | Rename to `_get_active_set_2_5d()` and implement ADR-3 active set. |
| Macro cadence | `sprint_2_implementation_roadmap.md:66` still says 60 real-world seconds. | Change to 10 real seconds = 1 in-game hour. |
| Interregnum | Sprint 2/3 roadmaps and scaffolds call ordinary `process_macro_tick()` 12 times. | Use a dedicated `process_interregnum_month()` / coarse pass; ordinary macro tick is hourly. |
| Planner | Multiple files still say GOAP (`game_vision`, ECS, LLM, Sprint 3). | Replace with JobTemplate expansion; mention GOAP only as future implementation behind `plan()`. |
| LLM salience | LLM/Sprint 3 say 5 recent + 3 core; factions/Sprint 6 say top-3 weight + 3 recent. | Standardize on top-3 by weight + 3 most recent. |
| LLM fallback | LLM/Sprint 3 invalid target -> FORTIFY; Sprint 6 hallucinated target -> GATHER_RESOURCES. | Pick one. Recommend FORTIFY for invalid target, keep current objective on timeout. |
| RNG | `sprint_3_technical_scaffolding.md:106` uses `randf()`. | Use `RNGService` stream (`economy`/`entropy`) everywhere. |
| Reaction data | Sprint 4 starts with flat `REACTION_MATRIX` unordered keys. | Replace example with data-driven sorted-pair rules with INTRA/INTER scope. |
| Cipher | `sprint_5_implementation_roadmap.md:80` says UI scrambles text. | Use semantic replacement only. |

### B2. Ownership/currency examples still violate the registry/economy

**Severity:** P1.

**Evidence:**
- `the_first_hour_day_0_gameplay_and_transition.md:45` says the ECS verifies gold's
  `mass_kg` equals required value and removes `[Owned_By_Faction: 12]`.
- `material_crafting_and_economy_architecture.md` clarifies coin value, but still says the
  player places coins "totaling the weight of the required value."
- `factions_and_social_mechanics_architecture.md:104-106` says ownership tag phrasing is void.

**Problem:** Mass and value are different axes. Ownership is a component, not a tag. These
examples will cause exactly the sort of economy exploit the docs are trying to prevent.

**Recommended repair:**
- Rewrite barter examples to:
  - Sum `coin_value`, not `mass_kg`, for payment.
  - Keep mass only for encumbrance/physical handling.
  - Transfer or update `OwnershipComponent{faction_id}`.
  - Use change-making rules from material spec.

### B3. LLM contract should not ask for `thought_process`

**Severity:** P1.

**Evidence:** `llm_reasoner_and_planning_architecture.md:39` and
`sprint_3_technical_scaffolding.md:53` include `"thought_process"`.

**Problem:** Asking for chain-of-thought-style output wastes tokens, creates brittle logs,
and risks exposing verbose reasoning the game does not need. The engine only needs a compact,
auditable rationale.

**Recommended repair:** Replace `thought_process` with `reason_summary` or
`decision_summary`, max 200 chars, explicitly "brief rationale for logs, not hidden
reasoning." Keep the public bark separate.

### B4. `NavigationServer3D.query_path_async()` may be an API fiction

**Severity:** P1 until verified against Godot 4.7.1.

**Evidence:** `sprint_1_technical_scaffolding.md:159` mandates
`NavigationServer3D.query_path_async()` and forbids `map_get_path()`.

**Problem:** If the named method does not exist in the pinned Godot version, Sprint 1 agents
will either fail or improvise around the ADR. The spec should reference the exact Godot
4.7.1 API shape.

**Recommended repair:** Verify the 4.7.1 `NavigationServer3D` API before implementation.
If async path query is not available as named, specify the real call pattern and keep the
architecture requirement: path requests are queued, bounded per frame, and fall back to grid
A* if unavailable.

### B5. Root instruction files are inconsistent and one symlink is dangling

**Severity:** P1 for agent onboarding.

**Evidence:**
- Active file read for this session is `.claude/CLAUDE.md`.
- `README.md:3` says read root `CLAUDE.md` or `.cursorrules`.
- `README.md:90-91` says `copilot-instructions.md` is a symlink to `CLAUDE.md`.
- On disk, `copilot-instructions.md -> CLAUDE.md`, but root `CLAUDE.md` does not exist, so
  the symlink is dangling.

**Problem:** The first onboarding instruction points to files that are absent or broken.
The session worked only because the user explicitly named `.claude/CLAUDE.md`.

**Recommended repair:** Choose one canonical layout. I recommend:
- Root `CLAUDE.md` is canonical for tools that expect it.
- `.claude/CLAUDE.md` and `copilot-instructions.md` point to root `CLAUDE.md`, or all docs
  explicitly name `.claude/CLAUDE.md` and the dangling symlink is removed.
- Update Sprint 0 scaffolding accordingly.

### B6. The historical adversarial review now misleads from the top

**Severity:** P2, but high onboarding impact.

**Evidence:** `docs/ADVERSARIAL_REVIEW.md` opens with the original P0 "not implementable"
findings, then only near the bottom says they were resolved in later integration passes.

**Problem:** A new agent reading top-down will spend context on stale P0s and may reopen
settled ADR decisions.

**Recommended repair:** Add a top banner:
"Historical review. Original sections A-M are resolved or superseded by ADR/integration
sections N+; read current dated review first." Alternatively split historical findings from
current review.

### B7. Narrative specs still use floor-level LoD language

**Severity:** P2.

**Evidence:** `game_vision_and_architecture_the_living_delve.md` uses "Active Floor,"
"Adjacent Floors," and "Distant Floors"; ADR-3/ECS use chunk active sets.

**Problem:** This is not technically blocking, but it trains agents to think floor-level
activation when the performance budget is chunk-level.

**Recommended repair:** Rewrite the vision doc to say Active chunk neighborhood, Simulated
nearby chunks/routes, Abstracted distant floors/factions.

### B8. World-history cadence is still 1,000 vs 500 years

**Severity:** P2.

**Evidence:** `game_vision_and_architecture_the_living_delve.md` says the pre-game simulates
1,000 years; `dag_history_generation_architecture.md` integrated defaults are 50 epochs /
~500 years.

**Recommended repair:** Standardize on "50 epochs (~500 years) by default; tunable per seed"
or change the DAG default to match the vision.

---

## C. Recommended mitigation plan

### Pass 1 - Mechanical propagation, no human decision needed

1. Make `architecture_decisions.md` and `component_and_field_registry.md` impossible to miss
   from every sprint scaffold.
2. Rewrite bad examples in Sprint 1-6 to match:
   - `EntityHandle`, not bare ids, except where deliberately using stable `faction_id`.
   - GDScript enums, not strings.
   - JobTemplates, not GOAP.
   - Macro = 10 real seconds / 1 in-game hour.
   - Interregnum = dedicated monthly coarse pass, not ordinary macro ticks.
   - `RNGService`, not `randf()`.
3. Rewrite Day 0 barter/ownership examples.
4. Fix instruction file docs/symlink mismatch.
5. Add a banner to the old adversarial review.

### Pass 2 - Add missing mini-specs

1. Add Perception/Hearing/Witness spec sections (A1).
2. Add Container/Station/Profession registry entries (A5).
3. Add LoD item materialization policy (A3).
4. Add topology/nav invalidation policy (A4).
5. Create Persistence workstream doc and slot it (A2).
6. Tighten LLM schema/config/fallback:
   - `reason_summary`, not `thought_process`.
   - exact env var names and config paths.
   - timeout/retry/cache policy.
   - one FallbackMatrix.

### Pass 3 - Add cheap doc guardrails

These can be plain scripts/tests later; no new tooling decision required.

- Broken doc path/symlink check.
- Grep guard for stale patterns:
  - `phase: String`
  - `next_entity_id`
  - `Owned_By_Faction`
  - `GOAP` outside ADR/future notes
  - `60 real-world seconds`
  - `randf(`
  - `thought_process`
  - `scrambles`
  - `_get_neighbors_3D`
- Registry drift check: any `*Component` named in docs must appear in the registry or be
  explicitly marked retired/historical.

---

## D. Items that were open at review time

| Item | Decision needed? | Recommended default |
|------|------------------|---------------------|
| Perception/hearing/witness system | No major product decision. | Add Sprint 1 `PerceptionSystem` with sight cone, DDA LoS, hearing/noise ephemerals, witness events. |
| Persistence workstream placement | Minor sequencing choice. | Create Sprint 2.5 / Sprint P before Sprint 3 death loop. |
| Non-fungible LoD item policy | No. | Ledgerize fungibles only; preserve equipped/unique/container/caravan manifests. |
| Mutable topology invalidation | No. | Dirty chunks/graph/nav on tile mutation; async rebuild; grid A* fallback. |
| Registry coverage for containers/stations/professions/perception | No, unless preferring tag-only professions. | Add explicit components/records to registry. |
| Exact LLM config names/budgets | No. | Agent can pick conventional env vars/config paths and document them. |
| Godot NavServer async API | Verification, not design. | Check pinned 4.7.1 API before implementation and update scaffold to the real call. |

## E. Bottom line

Do not reopen the settled ADR decisions. They are coherent.

Do not start implementation from scaffolding examples that predate the §F repair log. The
repair pass below integrated the missing perception/persistence/materialization/topology specs
and removed the identified copy/paste traps.

## F. Resolution log - applied 2026-07-31

The requested repair pass has been applied to the owning specifications and scaffolding:

- Added Perception/Hearing/Witness primitives to the registry, ECS spec, Sprint 1, factions,
  entity behavior, and world bootstrapping docs.
- Created `docs/persistence_and_save_architecture.md` and slotted it as Sprint P / Sprint 2.5
  in README and ADR-6.
- Added MaterializationPolicy and LoD identity-preservation rules for fungible commodities vs
  equipped/unique/container/caravan items.
- Added mutable topology/nav invalidation rules for tile changes, AbstractGraph dirty edges,
  NavServer rebake, and grid A* fallback.
- Expanded the registry for containers, heat sources, professions, perception, sensory
  emitters, materialization, and witness events.
- Repaired stale scaffold/narrative traps: 1Hz/60s macro wording, ordinary macro ticks during
  interregnum, GOAP wording, `randf()`, `thought_process`, ownership tags, mass-as-payment,
  text scrambling, floor-level LoD, and the fictional NavServer async method mandate.
- Created root `CLAUDE.md` so `copilot-instructions.md -> CLAUDE.md` resolves and README
  onboarding is accurate.
