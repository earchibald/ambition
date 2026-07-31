# Adversarial Review & Recommendations — "The Living Delve"

**Reviewer:** Lead Systems Coding Agent
**Date:** 2026-07-30
**Scope:** End-to-end review of all specification, architecture, sprint, and process
documents *before any implementation code is written*. This is a spec-only project;
`ecs/`, `viewer/`, `ui/`, `singletons/`, `tests/`, `addons/`, `assets/` are all empty.

**How to read this:** Every item has a **Severity**, the **Evidence** (which doc/line of
reasoning), the **Problem**, and a concrete **Recommendation**. Nothing here is
implemented yet, so *all* of these are cheap to fix now and expensive to fix later.

- **P0 — Blocking paradox / must resolve before Sprint 1.** The architecture cannot be
  built as written; two specs actively contradict, or a load-bearing system is undefined.
- **P1 — Major gap / high risk.** Buildable, but will cause rework, exploits, or
  crashes if not pinned down.
- **P2 — Consistency / polish / hygiene.** Won't block, but erodes trust in the spec
  and wastes agent time.

---

## 0. Executive Summary

The vision is coherent and genuinely ambitious, and the "Godot is a dumb viewer /
ECS is ground truth" spine is the right call. However, the spec set is **not yet
implementable end-to-end** because several *load-bearing systems are named but never
designed*, several *core identifiers and time units contradict each other across
documents*, and the **hardest technical problem the architecture creates for itself —
doing 3D spatial queries and solid-body movement without Godot physics — is never
solved.**

The five things that must be resolved before writing Sprint 1 code (all P0):

1. **Spatial queries & collision without physics nodes** (§A1). The Prime Directive
   bans `Area3D`/`move_and_slide()`/raycasts-on-bodies, but movement, melee targeting,
   interaction ("context-sensitive E"), and the Tactical Lens all require spatial
   queries and wall collision. No replacement system exists.
2. **The definition of a "tick" is inconsistent** (§C1). Simulation Tick is 1Hz vs 2Hz;
   the Macro Tick is simultaneously "hourly," "60 real seconds," "one month," and
   "one week" across four documents.
3. **Player identity is triple-defined** (§A4): Entity 0 vs Faction 0 vs Faction 14 vs
   "not a DAG node." The LLM validation gate depends on resolving this.
4. **GOAP is the backbone of LLM→action translation but is entirely unspecified** (§B1).
5. **No save/serialization or RNG-seeding architecture exists** (§B2, §B3) despite the
   game promising a persistent world, "Save & Quit," and deterministic seed continuity.

The good news: the *anti-exploit instincts* in the sprint scaffolding (flood buffer,
wealth ledger sync, TTL on ephemerals, anti-recursion cooldowns, lazy LLM prompts) are
excellent and show the author already thinks adversarially. The gaps below are about
finishing that thinking, not redirecting it.

---

## A. Critical Architectural Paradoxes (P0)

### A1. Spatial queries & solid-body movement without physics nodes — UNSOLVED
**Severity: P0** · **Evidence:** CLAUDE.md Prime Directive (no `CharacterBody3D`,
`RigidBody3D`, `Area3D`, `move_and_slide()`); Sprint 1 combat & input steps; day-0
melee ("swing at the rat"), mining, "context-sensitive E," Tactical Lens mouse-over.
**Problem:** Nearly every interactive loop needs one of: (a) *wall/floor collision*
during movement, (b) *"what is under my crosshair / mouse"* picking, (c) *melee/AoE
overlap* tests. In Godot these normally come from the physics server (raycasts,
`Area3D`, `move_and_slide`) — all banned. The specs never define what replaces them.
`velocity` is applied to `exact_pos` with nothing stopping the player walking through
solid rock. Combat "hits the rat" with no defined hit-detection. The Tactical Lens
"mouse over an entity" has no defined picking.
**Recommendation:** Specify an **ECS-owned spatial layer** as a Sprint 1 deliverable:
- A per-chunk **uniform spatial hash / grid index** (`{cell -> [entity_ids]}`) rebuilt
  or incrementally updated each Micro Tick for Active chunks.
- An **ECS collision resolver** for movement against the `tile_map` (grid raycast /
  swept-AABB against solid tiles) to replace `move_and_slide`. This is the single most
  important missing system; add it as Sprint 1 Step 3.5.
- A **crosshair/mouse pick** that projects a ray in pure math against the spatial hash
  (screen ray from camera → grid DDA), *not* against Godot colliders. The camera is a
  viewer node; the ray math lives in the ECS/bridge.
- Explicitly state whether `NavigationServer3D` (which *is* a physics-server-adjacent
  Godot subsystem) is a sanctioned exception or also banned (see A2).

### A2. Pathfinding ownership is split and half-undefined
**Severity: P0** · **Evidence:** Sprint 1 §6 mandates `NavigationServer3D.query_path_async`;
ECS arch §3 says Simulated entities "traverse a node-based pathfinding graph … position
interpolated mathematically"; Sprint 2 says Simulated entities "drop their Vector3
positions and are tracked as Node_IDs on a topological graph."
**Problem:** There are two pathfinders — Godot NavServer (Active) and an abstract
topological graph (Simulated) — and (1) the abstract graph pathfinder is *never
specified* (no graph construction, no algorithm, no edge weights), (2) using NavServer
contradicts "pure-data ECS is source of truth" since navmeshes are baked from viewer
geometry that only exists for Active chunks, and (3) the handshake when an entity
crosses an Active↔Simulated boundary *mid-path* is undefined.
**Recommendation:** Decide the ownership model explicitly:
- Make the **abstract topological graph the source of truth** (owned by the ECS/WorldGrid,
  built from the tile_map at generation time, independent of viewer nodes). Specify nodes
  (portals, room centroids, stairs), edges, and weights.
- Use `NavigationServer3D` *only* as an optional Active-chunk refinement for smooth local
  steering, sanctioned as an explicit, documented exception to the Prime Directive — or
  drop it and do local steering in the ECS grid too.
- Define the boundary hand-off: when an entity's path crosses into a Simulated chunk,
  convert remaining path to abstract-graph traversal and vice-versa.

### A3. Is the world 2D-per-floor or true 3D-chunked? (LoD neighbor count contradiction)
**Severity: P0** · **Evidence:** ECS arch §3 and world-gen §5 say "the chunk the player
is in **plus its 8 immediate neighbors**" (a 3×3 = 9-chunk 2D neighborhood). Sprint 2
scaffolding uses `Vector3i` chunk ids and `_get_neighbors_3D()` with the comment "Must
account for Z-axis" (a 3×3×3 = 27-chunk 3D neighborhood).
**Problem:** These are different memory models. Floors are stacked on Z (elevator), so
"neighbors" could mean same-floor 8 or full-3D 26. This directly sizes the Active
working set, CA cost, and streaming.
**Recommendation:** State the canonical model. Recommended: **floors are discrete
2.5D planes**; chunk id is `Vector3i(x, y, floor)`; the Active set is the 3×3 same-floor
neighborhood **plus** the entry chunks of the floor directly above/below (for stair
transitions). Fix the "8 neighbors" language and the `Vector3i`/`int` chunk-id type
mismatch (see C4) everywhere.

### A4. Player identity is defined three different ways
**Severity: P0** · **Evidence:** ECS/day-0 use **Entity 0** for the player; factions doc
says the player is **Faction ID: 0**; LLM doc example enumerates targets as
"`[12: Dwarven Outpost, 14: The Player]`" (**Faction 14**); the Validation Gate checks
`DAG.has_active_faction(target_id)`.
**Problem:** The LLM can output "raid the player." Resolution requires a single, stable
mapping from *the player* to a faction id and (maybe) a DAG node id. Right now Entity 0,
Faction 0, and Faction 14 all refer to the player in different docs, and it's unstated
whether the player is a DAG node at all — so `has_active_faction(player)` may always fail
and silently reject every "attack the player" objective.
**Recommendation:** Define one canonical identity table in the ECS arch doc:
`Player = Entity 0 = Faction 0`, and register a synthetic **Faction-0 DAG node** at world
gen so validation and targeting resolve. Purge the "Faction 14" example. Add a
`is_player(faction_id)` helper to the spec.

### A5. Determinism is promised but the architecture is non-deterministic
**Severity: P0** · **Evidence:** Meta-progression "Seed Continuity" (floors/seeds must not
change; mined walls stay mined); Interregnum replays; "Save & Quit (Suspends run)".
Sprint 1 drives ticks from `_physics_process(delta)` and accumulates `Vector3` (float)
positions; multiple systems call `randf()` (mutation, DAG, rupture, loot).
**Problem:** Float accumulation + frame-timed ticks + Godot's global RNG are **not
reproducible** across platforms or save/load. A "persistent, re-simulatable world" and a
"suspend/resume run" require deterministic evolution or full state capture.
**Recommendation:** Either (a) drop the determinism promise and lean fully on
**state serialization** (see B2), or (b) commit to determinism: fixed-`dt` integer or
fixed-point tick math, a **central seeded RNG service with per-system streams**, and
tick counts rather than wall-clock. Given the scope, recommend (a) + seeded RNG for
*generation only*. Make the choice explicit; it changes everything downstream.

---

## B. Missing Load-Bearing Systems / Pipelines (P0–P1)

### B1. GOAP is the backbone of "LLM objective → jobs" but is never designed
**Severity: P0** · **Evidence:** Vision §4, LLM doc §1/§4, factions, entity-behavior all
say "GOAP or Utility AI" translates objectives (RAID → jobs). Sprint 1 only implements a
hardcoded `if hunger > threshold` utility check.
**Problem:** GOAP (actions with preconditions/effects + a planner search) is a substantial
subsystem and the *only* specified bridge from Tier-3 objectives to Tier-2 jobs. It is a
buzzword everywhere and a design nowhere. "RAID_FACTION → pathfind + equip + siege jobs"
is hand-waved.
**Recommendation:** Either commit to **true GOAP** (define the action library,
world-state predicates, planner, replanning cadence) *or* — recommended for scope —
specify a simpler, deterministic **objective→job-template expansion** (each LLM objective
maps to a fixed, data-driven Job DAG that the faction planner instantiates and
profession-filters). Pick one and write it before Sprint 3. Stop saying "GOAP or Utility
AI" as if interchangeable — they have very different costs.

### B2. No serialization / save-game architecture exists
**Severity: P0** · **Evidence:** HUD doc "Save & Quit (Suspends current run)";
persistent world; Lineage Journal JSON; Interregnum is in-memory.
**Problem:** Suspending a run and the persistent world both require serializing the entire
ECS (all component registries), the DAG (now growing at runtime), the WorldGrid + tile
maps + ledgers + volume pools, and RNG state. There is **no save format, no versioning, no
migration story**. This is arguably a whole sprint of work with zero current spec.
**Recommendation:** Add a first-class **Persistence spec** (and probably a Sprint 2.5 or
explicit Sprint 5 task): define a versioned save schema, what is authoritative (ECS +
DAG + grid + RNG), how partially-generated lazy floors are saved, and a schema-version
field for forward migration. Design components as serialization-friendly from day one
(this affects Sprint 1 component design — cheap now, painful later).

### B3. No central RNG / seed management
**Severity: P1** · **Evidence:** Many `randf()` call sites; "procedural noise seeds must
not change."
**Problem:** Ungoverned global RNG makes generation non-reproducible and save/load lossy,
and makes bugs non-repeatable in tests/CI.
**Recommendation:** A `RNGService` with named, independently-seeded streams
(worldgen, dag, combat, mutation, economy). Seed from a single master world seed. Persist
stream states in saves. Tests seed deterministically.

### B4. No ECS collision / solid-item physics (gravity, throwing, scatter, settling)
**Severity: P1** · **Evidence:** Backpack **rupture** spawns items "with outward velocity
vectors"; mining "yields nuggets"; corpses spill loot; Sprint 2 pre-warm "items skip
gravity … snap to tables … prevent Day-0 collision explosions" — implying a gravity/
collision system exists.
**Problem:** Fluids have Cellular Automata, but **solid loose items have no defined
motion/settling model**. Yet multiple mechanics fling solids around and the pre-warm
explicitly guards against a gravity system that is never specified. Without it, scattered
loot has undefined resting positions and "collision explosions" are undefined.
**Recommendation:** Specify a minimal **ballistic/settling model** in the ECS (simple
per-item integrator + grid collision + sleep-on-rest), or explicitly forbid loose-item
ballistics and make rupture/drop *teleport* items to nearest valid floor cells. Decide
before Sprint 1 combat/inventory, since rupture and drop are Sprint 1/data-adjacent.

### B5. Entity lifecycle: no id recycling, no atomic destroy across registries
**Severity: P1** · **Evidence:** Sprint 1 `next_entity_id: int` monotonic; components live
in many parallel Dictionaries (`positions`, `physicals`, `needs`, `action_queues`, …);
Interregnum GC destroys "thousands of orphaned items" repeatedly across deaths.
**Problem:** (1) `destroy_entity` must remove the id from *every* registry/queue or you
get dangling-id reads (a class of bug that will be endemic with this sparse-set-in-many-
dicts layout). No spec guarantees exhaustive removal. (2) Monotonic ids never recycle →
across many death loops the id space and dict key churn grow unbounded; stale references
to reused-meaning ids can't be detected.
**Recommendation:** Specify (a) a **single authoritative component-registry list** and a
`destroy_entity` contract that iterates all registries (or an archetype/columnar store so
destroy is one operation), and (b) **generational entity handles** (`id + generation`) so
stale references are detectable. This is a Sprint 1 foundational decision.

### B6. Abstract-faction memory pipeline breaks for the LLM
**Severity: P1** · **Evidence:** LLM reasons on Macro Tick for *all* active factions incl.
Abstracted ones; MemoryComponent is filled by *individual* events + gossip that only
occur in Active/Simulated chunks; Abstracted factions are "Faction Pools" with no
individuals.
**Problem:** The factions the LLM most needs to drive at range (Abstracted) accrue **no
new memories**, so their prompt context is permanently stale — undermining "emergent,
historically aware" leaders exactly where abstraction is heaviest.
**Recommendation:** Give the **FactionCoreComponent its own abstract memory/event log**
that macro-level systems (gray-box, DAG edges, war resolution) write to directly, so a
leader's salient context exists independent of individual Tier-2 gossip.

### B7. No LLM provider / config / secret / offline story
**Severity: P1** · **Evidence:** LLM docs describe schema and flow but never name a
provider, auth, key storage, cost budget, caching, or an offline/dev path; CI is headless.
**Problem:** Tier-3 cannot run in CI, offline, or without a committed decision on where the
API key lives (and CLAUDE.md forbids committing secrets — correct, but no positive
guidance). Identical prompts aren't cached ("without breaking the bank" is asserted, not
engineered).
**Recommendation:** Define an `LLMProvider` **interface** with: a production HTTP impl,
a **deterministic mock** used in tests/CI/offline, key loaded from env/`user://` (never
committed), a response cache keyed by prompt hash, and a hard monthly/again rate budget.
Make the mock the default so the game is fully playable with zero API access.

---

## C. Cross-Document Consistency & Timing (P1–P2)

### C1. The "tick" is defined inconsistently everywhere
**Severity: P1** · **Evidence:** Sim Tick: ECS arch "1Hz–2Hz", vision "2 TPS", Sprint 1
`SIM_TICK_RATE = 1.0` (1Hz). Macro Tick: ECS arch "Daily/Hourly", Sprint 2 "every 60 real
seconds", Sprint 3 Interregnum "12 monthly macro-ticks = 1 year" (⇒ 1 macro tick = 1
month), LLM doc "re-evaluate once every in-game week", climate "360-day year / weather
events per macro tick".
**Problem:** If 1 Macro Tick = 1 month, you *cannot* trigger "weekly" LLM re-evaluation,
and weather granularity is monthly (contradicting rain→puddles gameplay). The fundamental
game-time↔real-time↔tick mapping is undefined.
**Recommendation:** Publish one **canonical time table**: real seconds per Micro/Sim/Macro
tick, and game-time per Macro tick, in a single authoritative section of the ECS arch doc.
Recommended: Micro 60Hz; Sim 2Hz; **Macro = 1 in-game hour**, fired every N real seconds;
derive day/week/month/season as counts of macro ticks. Update Interregnum (should be
~8,640 hourly macro-ticks or a dedicated *coarse* interregnum tick — see C2) and climate
accordingly.

### C2. Interregnum granularity contradicts its own entropy tax
**Severity: P1** · **Evidence:** Interregnum = "12 monthly macro-ticks"; Entropy Tax
"destroy 100% of [Filth], [Ephemeral_Noise], 40% of standard faction wealth."
**Problem:** During the skip the world is Abstracted, so **wealth lives in integer
ledgers, not physical entities** (per Sprint 2's own dematerialization rule). The tax
iterates *physical* `PhysicalPropertyComponent` entities and deletes non-owned ones — but
almost no physical entities exist during the skip. So the tax **barely touches the actual
(ledger) wealth**, and the world may exit the skip *richer* than intended. Also the swarm
tax references `chunk.swarm_population`, a field not defined in Sprint 2's `ChunkData`.
**Recommendation:** Make the Entropy/Swarm tax operate on **ledgers and abstract
population counters**, not physical entities (which are the wrong representation during a
time-skip). Add `swarm_population` to `ChunkData` (or the Tier-1 PopulationComponent) and
reconcile "Tier 1 lives on chunk/zone population" vs "per-chunk swarm cap".

### C3. Sprint 1 needs a game clock that doesn't arrive until Sprint 2
**Severity: P1** · **Evidence:** Sprint 1 Step 5 implements `ScheduleComponent`
(sleep/work/leisure keyed to a 24h cycle) and success requires need-interrupts; but Sprint
1's `GameLoopManager` only drives Micro + Sim ticks. The Macro tick / day-night clock is a
Sprint 2 deliverable.
**Problem:** Schedules and morale leisure blocks have no time-of-day source in Sprint 1.
**Recommendation:** Move a **minimal game-clock** (time-of-day counter advanced by the Sim
or Macro tick) into Sprint 1, or descope `ScheduleComponent` to Sprint 2. Recommend
introducing the clock in Sprint 1 since so much AI depends on it.

### C4. `chunk_id` type: `int` vs `Vector3i`
**Severity: P1** · **Evidence:** ECS arch & Sprint 1 `PositionComponent.chunk_id: int`;
Sprint 2 `ChunkData.chunk_id: Vector3i`, `anchor_chunk_id: Vector3i`.
**Problem:** Core identifier type mismatch; also Sprint 1 `PositionComponent` omits
`floor_id` and `current_node_id` that the ECS arch doc lists.
**Recommendation:** Standardize `chunk_id: Vector3i` (x, y, floor) across all docs and
align `PositionComponent` fields (add `floor_id`/`current_node_id` or fold floor into the
Vector3i). Fix in Sprint 1 scaffolding.

### C5. Redundant physical fields with no source of truth
**Severity: P1** · **Evidence:** `PhysicalPropertyComponent` has independent `mass_kg` and
`volume_cm3`; `MaterialCompositionComponent` has material percentages; Sprint 5 material
dict has `density_kg_per_cm3`.
**Problem:** `mass` can be derived from `volume × Σ(composition × density)`. Storing mass,
volume, composition, and density independently guarantees desync (e.g., after alloying or
partial consumption).
**Recommendation:** Declare **composition + volume authoritative**; derive mass (and
value) via helpers. Or clearly document mass as a cache with an invalidation rule.

### C6. `phase` and other enums: String vs Enum
**Severity: P2** · **Evidence:** ECS arch `phase: Enum(Solid, Liquid, Gas)`; Sprint 1
`phase: String = "Solid"`. Similar for LoD state (`Enum` vs string "ACTIVE").
**Recommendation:** Use GDScript `enum`s consistently for closed sets (perf + typo
safety); reserve strings for open tag vocabularies.

### C7. Ownership represented three ways
**Severity: P2** · **Evidence:** `[Owned_By_Faction: 12]` tag (day-0); `ClaimTags`
(factions); `has_component("OwnedByFaction")` (Sprint 3 GC).
**Recommendation:** Pick one canonical ownership representation (recommend a component
`OwnershipComponent{faction_id}`), and define how zone `ClaimTags` relate to item
ownership.

---

## D. Simulation Integrity & Exploit Surfaces (P1)

### D1. Wealth LoD-sync only covers stockpile-zone items; loose/carried wealth leaks or dupes
**Severity: P1** · **Evidence:** Sprint 2 `_materialize` (ledger→physical, set ledger 0)
and `_dematerialize` (sum `[Zone_Stockpile]` physical items → ledger, destroy).
**Problem:** Dematerialization only scans the **stockpile zone**. Wealth that is
NPC-carried (`InventoryComponent`), mid-haul, or dropped on the floor outside the stockpile
is **not** counted back — it's either destroyed (leak) or, on the next materialize, the
ledger re-spawns stockpile wealth while loose items still exist (dupe). Because LoDSystem
runs on the 1Hz Sim tick, there's a **sub-second boundary-crossing window** to grab
materialized gold and re-cross before dematerialization — a classic duplication exploit.
**Recommendation:** (1) Dematerialize **all** faction-owned physical matter in the chunk
(stockpile + NPC inventories + owned loose items), not just the stockpile zone.
(2) Make materialize/dematerialize **transactional and idempotent** (guard tag so a chunk
can't double-materialize), and consider hysteresis / a debounce so rapid boundary
oscillation can't be farmed. Add a property test: *cross a boundary N times → total
faction value invariant.*

### D2. Boundary combat / cross-LoD interactions undefined
**Severity: P1** · **Evidence:** Micro tick runs only for Active chunks; projectiles resolve
on downgrade (good); but an entity in a Simulated chunk attacking into an Active chunk (or
melee exactly on the seam) is undefined.
**Recommendation:** Define seam rules: attacks originate/resolve in the attacker's LoD;
cross-boundary hostile actions either force-promote the target chunk to Active or resolve
abstractly. State it.

### D3. Guest-Status crime detection is instant & global, contradicting gossip reputation
**Severity: P1** · **Evidence:** world-bootstrap: `[Guest_Status]` "permanently revoked if
the player commits an act with the `[Crime]` tag" (instant); factions doc: reputation must
propagate via **gossip**, "rather than instantaneously via a global hivemind."
**Problem:** Direct contradiction for the village's reaction to player crime.
**Recommendation:** Route crime through the same **witness + gossip** pipeline (a guard
must witness, or a victim must report) so reputation stays emergent; keep an explicit
"caught red-handed by a witness" fast path rather than an omniscient global flag.

### D4. Unbounded factions → cost/perf blowup
**Severity: P1** · **Evidence:** Schism spins up **splinter factions** (each needs an
LLM-driven leader); gray-box migration fills vacuums with **new** factions; no cap.
**Problem:** Faction count (hence Tier-3 LLM agents, DAG nodes, diplomacy matrix which is
O(n²)) can grow without bound. The staggered queue smooths *rate*, not *total*.
**Recommendation:** Hard-cap simultaneous factions/Tier-3 agents; when exceeded, merge or
abstract the weakest into gray-box pools. Cap DiplomacyComponent to top-K relationships.

### D5. Runtime DAG grows unbounded across death loops
**Severity: P1** · **Evidence:** Pruning specified only at gen end; Interregnum + gameplay
**add** edges (player death, wars) forever.
**Recommendation:** Define **runtime DAG compaction** (periodic pruning of edges/nodes with
no live descendants, artifacts, or ruins), plus a cap keyed to the "history relevance"
rule already described for gen-time pruning.

### D6. Physical currency math vs. discrete coins vs. gold base_value=50
**Severity: P1** · **Evidence:** Prices are `base × (1 + D/(Q+1)) × quality` → **floats**
(e.g., 14.7); payment is "place coins totaling the required weight/value"; material table
lists `MAT_GOLD base_value = 50`.
**Problem:** Discrete gold coins can't represent fractional prices, and if one coin is
worth 50, a 15-value sword is unpayable in whole coins. No change-making, no denomination,
no rounding rule.
**Recommendation:** Define currency granularity: either coins are 1-value units (drop the
50), or introduce denominations + a change/rounding rule. Specify how the barter resolver
rounds float prices to payable coin sets and returns change.

### D7. `quantity`-stacking vs. physical spill/scatter interaction
**Severity: P2** · **Evidence:** `quantity` lets 10,000 gold be one entity; rupture spills
"10–20% of volume as individual physical entities."
**Problem:** Splitting a stacked entity on partial spill/drop is undefined (does it clone,
decrement, re-stack on pickup?).
**Recommendation:** Specify stack **split/merge** semantics (decrement source quantity,
spawn N loose singles or a smaller stack; auto-merge on pickup by material+quality+tags).

### D8. Absorb_Tag conflates tags with conserved energy
**Severity: P2** · **Evidence:** Grimoire `Absorb_Tag` rips `[Heat]` from a campfire
"extinguishing it" and "forwards the energy."
**Problem:** Tags aren't quantities; two casters absorbing the same `[Heat]` is a
double-spend, and "energy" isn't a modeled resource.
**Recommendation:** Model absorb as consuming a **quantified** environmental resource
(e.g., the campfire's temperature/fuel value), removing the tag only when it crosses a
threshold; reject concurrent absorbs atomically.

---

## E. Performance & Scale Feasibility (P1)

### E1. Pure-GDScript at the stated scale is a hard risk
**Severity: P1** · **Evidence:** Vision "10,000 independent entities"; CA fluids on
64×64 grids across the Active neighborhood at 60Hz; docs *suggest* Rust/GDExtension "where
possible" but **all** scaffolding is GDScript Dictionaries with linear
`get_all_entities_with_component` scans.
**Problem:** 64×64 = 4,096 cells × (9–27 active chunks) × 60Hz ≈ 2–7M cell-updates/sec for
fluids alone, in GDScript, plus multi-system dictionary iteration over up to 10k entities.
This is very likely infeasible at frame budget.
**Recommendation:** (1) Set **explicit budgets** (max active entities, max active CA
cells, target frame time) and a measurement harness early. (2) Design the CA and hot
Micro-tick loops around `PackedInt32Array`/`PackedFloat32Array` (already hinted) and plan a
**GDExtension/Rust escape hatch** for CA and spatial hashing behind a stable ECS interface
so it can be swapped without touching game logic. Decide the boundary now; it shapes the
component memory layout.

### E2. No archetype/query acceleration
**Severity: P1** · **Evidence:** Systems iterate component dictionaries / do
`get_all_entities_with_component` (linear).
**Recommendation:** Add a **query cache / archetype index** (entities grouped by component
mask) so per-tick systems iterate only matching entities. Foundational; cheap to design
into Sprint 1.

### E3. CA dimensionality unspecified (2D grid vs 3D volume)
**Severity: P2** · **Evidence:** `FluidGridComponent.grid_size = 64` with a `volume_map`
that isn't sized to 64² or 64³; fluids "spread to lower elevations" implies height.
**Recommendation:** State whether fluid CA is 2D-per-floor with a heightmap or true 3D, and
size the packed arrays accordingly (`grid_size²` or `grid_size³`). This drives E1's budget.

---

## F. LLM Subsystem Details (P1–P2)

### F1. "Never block" vs. face-to-face player conversation
**Severity: P1** · **Evidence:** "ECS must never wait on the LLM"; but "player speaking to a
Tier 3 entity triggers a localized conversational prompt."
**Problem:** During a live conversation the player *is* waiting on the API. The
non-blocking rule and the conversational feature need a defined UX (typing indicator,
pre-canned holding barks, timeout fallback).
**Recommendation:** Specify conversational UX: immediate diegetic "thinking" bark from a
local table, async fill-in when the response lands, and a timeout → fallback line.

### F2. Reaction matrix key ordering & multi-tag combinatorics
**Severity: P2** · **Evidence:** `REACTION_MATRIX["Volatile_Gas+Burning"]` string keys.
**Problem:** `"Burning+Volatile_Gas"` won't match; only pairwise; ambiguous whether tags
are on one entity or two overlapping entities; O(tags²) matrix authoring doesn't scale.
**Recommendation:** Normalize keys (sort tag pair), define whether reactions are
intra-entity or inter-entity (or both), and move to a **data-driven rule list** with
predicates rather than a flat pair-string dict.

### F3. Salience "top 3 by weight + 3 recent" needs a decay/weight model
**Severity: P2** · **Evidence:** Sprint 6 sorts by a `Weight` float; no spec for how weight
is assigned or decays.
**Recommendation:** Define memory weighting (emotional weight tags, recency decay,
event-type base weights) so salience is reproducible.

---

## G. UI/UX & Accessibility (P2)

### G1. `ui_ux_qol_review.md` is stale, self-contradicting feedback left in the repo
**Severity: P2** · **Evidence:** The QoL review still quotes the **old** letter-scrambling
cipher ("The #$%&@ hoard bread…") and the old backpack/grimoire text as *open questions*,
but the main UI doc has **already** adopted semantic replacement, the Blueprint Library,
sub-containers, and a toggle inspect.
**Problem:** An onboarding agent can't tell resolved feedback from open work.
**Recommendation:** Either delete `ui_ux_qol_review.md` or convert it to a "Resolved
Feedback Log" clearly marking each item **DONE** with a pointer to where it was addressed.

### G2. Info design over-relies on hue (and sound) as the primary channel
**Severity: P2** · **Evidence:** Universal tag **colors** ([Toxic]=purple, [Volatile]=
orange) are the passive "read the sim at a glance" language that experts use *instead of*
the Tactical Lens; acoustic mnemonics carry material identity.
**Problem:** Colorblind players lose the expert real-time channel; deaf/HoH players lose
the acoustic channel. "Colorblind filters exist" doesn't fix a hue-primary language.
**Recommendation:** Mandate **redundant encoding** (shape + icon + motion + text), not just
color/sound, for any information the game expects the player to act on in real time. Make
this an explicit UI rule, since Sprint-4/5 VFX and Sprint-5 acoustic data are built on it.

### G3. Aura mechanic (Sprint 4) is required by earlier social/alert systems
**Severity: P2** · **Evidence:** Bard morale auras and `[Alert]` auras (entity-behavior,
Sprint 1 acoustic fix) are described as "the same mechanics as magic," but the
Ephemeral/Aura entity system ships in **Sprint 4**.
**Problem:** Sprint-1/2 features depend on a Sprint-4 primitive.
**Recommendation:** Pull a **minimal expanding-aura/ephemeral primitive** forward into
Sprint 1 (noise/alert already needs `[Ephemeral_Noise_Entity]`), and have Sprint 4 magic
build on it rather than introduce it.

### G4. Interception/Simulated-progress representation missing
**Severity: P2** · **Evidence:** Vision "intercept caravans" needs interpolated Simulated
positions; Sprint 2 sets Simulated `velocity = 0` and drops `Vector3`, tracking only
`Node_Id`.
**Problem:** With velocity zeroed and position dropped, there's no stored "progress along
edge" to interpolate an interception coordinate.
**Recommendation:** Store `current_edge`, `edge_progress (0..1)`, and `edge_speed` on
Simulated movers so a world coordinate can be reconstructed on demand for interception and
promotion to Active.

---

## H. Content & Data Model (P2)

### H1. Undefined stats referenced by Sprint 1 combat
**Severity: P1** · **Evidence:** Combat uses `Player_Strength`, `Biomass_Density`,
`Kinetic_Impact` force units; `BodyComponent` defines only `max_health, stamina, mutations,
skills` — no Strength, and no force/units convention.
**Recommendation:** Add the attributes combat depends on (e.g., `strength`), define the
**force unit** and the kinetic formula's inputs/outputs, and put creature `density`/mass in
the Sprint 5 bestiary schema.
### H2. Thermodynamics has no consistent model
**Severity: P2** · **Evidence:** Freeze/boil thresholds + forge temps + `Add_Temperature
(1000)` + "temperature propagation expanding radii," but no heat capacity, conduction, mass
weighting, or equilibrium — temperature is sometimes per-entity, sometimes per-grid-cell.
**Recommendation:** Define a minimal but consistent heat model (heat capacity per material,
conduction rule between adjacent cells/entities, how a fixed `Add_Temperature` distributes
over mass/volume). Decide the single representation of temperature.

### H3. Schema drift between sprints
**Severity: P2** · **Evidence:** `swarm_population` (Sprint 3) absent from `ChunkData`
(Sprint 2); `OwnedByFaction` component (Sprint 3) vs tag (day-0); Tier-1 "lives on chunk/
zone PopulationComponent" vs per-chunk swarm cap.
**Recommendation:** Maintain a single **canonical component/field registry** doc that all
sprints reference, and reconcile these fields.

---

## I. Process, Repo, CI & Workflow (P1–P2)

### I1. STATE.md is inaccurate; the committed project is currently unloadable
**Severity: P1** · **Evidence:** STATE.md: "Last Completed: Repository bootstrapping via
build_repo.py." On disk, `ecs/ viewer/ ui/ singletons/ tests/ addons/ assets/` are **empty
or absent**, and `project.godot` autoloads `res://singletons/ECSEvents.gd` etc. and sets
`run/main_scene="res://viewer/Main.tscn"` and `config/icon="res://icon.svg"` — **none of
which exist**. Opening/running the project fails to load autoloads and has no main scene.
**Problem:** The handoff protocol's single source of truth is wrong, and the project won't
launch, contradicting "main must always run flawlessly."
**Recommendation:** Either actually run `build_repo.py` and commit the scaffolding (empty
`.gd` autoload stubs + a placeholder `Main.tscn` + an `icon.svg`), *or* comment out the
autoloads/main-scene until Sprint 0 creates them. Update STATE.md to reflect true state.
Make **"project boots headlessly"** a CI gate (see I3).

### I2. CI will fail on `gdlint .` over third-party GUT, and uses unpinned gdtoolkit
**Severity: P1** · **Evidence:** `godot_ci.yml` runs `gdlint .` at repo root before GUT is
even guaranteed present; `pip3 install gdtoolkit` is unpinned.
**Problem:** `gdlint .` will lint `addons/gut` (third-party, not lint-clean) and fail the
pipeline; an unpinned linter can change rules under you and break CI nondeterministically.
Also the committed workflow has drifted from `sprint_0_technical_scaffolding.md` (adds
`apt-get`, `submodules: recursive`) so the scaffolding doc is already stale.
**Recommendation:** Scope lint to first-party dirs (`gdlint ecs singletons ui viewer
tests`) or add a `.gdlintrc` exclude for `addons/`; **pin** `gdtoolkit==<version>`; add
`gdformat --check`; and re-sync the scaffolding doc with the real workflow (or delete the
duplicated YAML from the doc and point at the file).

### I3. CI validates lint+tests but never verifies the game boots
**Severity: P2** · **Evidence:** CI runs pre-import + GUT; nothing runs `Main.tscn`.
**Problem:** "`main` must always run flawlessly" is unenforced.
**Recommendation:** Add a headless **smoke test** that boots the main scene for N frames
and exits 0 (a GUT test or a `--headless` scene run with a self-quit timer).

### I4. Godot version pinning
**Severity: P2** · **Evidence:** `project.godot` features `"4.2"`; CI image `4.2.1`. Local
toolchain is whatever `/opt/homebrew/bin/godot` is.
**Recommendation:** Pin one Godot 4.x across `project.godot`, CI image, and a documented
local version; record it in README. (Consider 4.3/4.4 for nav + typed-array improvements,
but pin *something* explicitly.)

### I5. Branch protection can't enforce "no self-merge" by policy alone
**Severity: P2** · **Evidence:** CLAUDE.md "NEVER auto-merge your own PR" is honor-system.
Now that `origin` exists, this is enforceable.
**Recommendation:** Configure GitHub **branch protection** on `main` and `dev` (require PR,
require CI green, require review, disallow force-push) so the rule is mechanical, not just
prompt-based. Create the `dev` branch now so the documented flow is real.

### I6. `build_repo.py` as generator is a source-of-truth hazard
**Severity: P2** · **Evidence:** A Python script fabricates the tree and files (CLAUDE.md,
project.godot, CI, etc.).
**Problem:** If it's ever re-run it can overwrite hand-edited files (e.g., the CI workflow
that has *already* diverged from what the script/scaffolding would emit).
**Recommendation:** Decide whether `build_repo.py` is a **one-shot** (then retire/delete it)
or the **canonical generator** (then hand-edits are forbidden and it must be updated
instead). Document which. Given the CI drift, it looks one-shot — recommend retiring it.

### I7. `copilot-instructions.md` → `CLAUDE.md` symlink
**Severity: P2 (note)** · **Evidence:** `copilot-instructions.md` is a symlink to
`CLAUDE.md`. Fine on macOS/Linux; **symlinks can break on Windows checkouts / some CI**.
**Recommendation:** Acceptable, but note the Windows risk; if cross-platform contributors
are expected, consider a committed copy or a generation step instead of a symlink.

---

## J. Documentation Hygiene (P2)

### J1. README and every sprint doc reference filenames that don't exist
**Severity: P1 (for agent onboarding)** · **Evidence:** CLAUDE.md Step 4 tells the agent to
"read README.md to locate the documentation," but README links point to non-existent
names, e.g. `ecs_architecture_spec.md` (actual `ecs_architecture_and_data_layer_
specification.md`), `economy_ecology_spec.md` (actual `material_crafting_and_economy_
architecture.md`), `day_zero_gameplay_spec.md` (actual `the_first_hour_day_0_gameplay_and_
transition.md`), `world_generation_spec.md`, `world_bootstrap_spec.md`,
`llm_reasoner_spec.md`, `meta_progression_spec.md`, `dag_history_gen.md`,
`ui_ux_architecture_spec.md`, `hud_interface_spec.md`, `inventory_grimoire_mechanics.md`,
`player_interactivity_spec.md` (no such file — folded into the UI doc), plus the vision,
entity-behavior, factions, and magic docs. **Sprint roadmaps** likewise reference
`sprint_1_roadmap.md` / `economy_ecology_spec.md` / `ecs_architecture_spec.md` etc.
**Problem:** The very first onboarding step — following README links — 404s on nearly every
document. This is the highest-friction, lowest-effort fix in the whole review.
**Recommendation:** Make README (and sprint cross-refs) point to the **actual** filenames,
or rename the files to the short names README already uses. Pick one naming scheme and make
links resolve. Add a CI/link-check or a simple test that every referenced doc path exists.

### J2. Mangled inline math/markdown throughout
**Severity: P2** · **Evidence:** `List$$String$$`, `Tags: List$$String$$`,
"Pin: High concentration of $$Acid$$", `[Player killed 2 guards]` rendered as
`$$Player killed 2 guards$$`, LaTeX `$T > 1700^\circ$` inside prose tables.
**Recommendation:** Normalize to plain Markdown (code spans / backticks for tags, real
tables), so specs are unambiguous to both humans and agents.

### J3. Filename typo `meta-progresion_...`
**Severity: P2** · **Recommendation:** Rename to `meta_progression_and_death_loop_
architecture.md` and update links.

---

## K. Prioritized Action List (recommended order)

**Resolve before writing ANY Sprint 1 code (P0):**
1. A1 — Specify the ECS spatial index + collision resolver + math picking (replaces
   physics/nav for movement, melee, interaction, Tactical Lens).
2. A4 — Canonical player identity (Entity 0 = Faction 0, synthetic DAG node).
3. C1 — Canonical tick/time table (Micro/Sim/Macro real-time + game-time).
4. A3/C4 — 2.5D-per-floor model + `chunk_id: Vector3i` everywhere.
5. A5/B2/B3 — Decide determinism-vs-serialization; add RNG service + save spec stubs
   (they shape Sprint 1 component design).
6. B1 — Pin down objective→job translation (true GOAP vs data-driven expansion).
7. B5 — Entity lifecycle: canonical registry list, atomic destroy, generational handles.

**Before the sprint that needs them (P1):**
8. B4 (loose-item motion) — before Sprint 1 inventory/combat.
9. C3 (game clock) — before Sprint 1 schedules.
10. H1 (combat stats/units) — before Sprint 1 combat.
11. D1 (wealth sync all-owned + transactional) — before Sprint 2 LoD.
12. C2 (interregnum tax on ledgers) — before Sprint 3.
13. B6/B7/F1 (abstract memory, LLM provider+mock, conversation UX) — before Sprint 3.
14. E1/E2/E3 (perf budgets, query cache, CA dimensionality) — design into Sprint 1.
15. D4/D5 (faction & DAG caps) — before Sprint 2/3.

**Cheap, do-now hygiene (P1/P2):**
16. J1 — fix every broken doc link (highest ROI).
17. I1 — make the project actually boot; correct STATE.md.
18. I2/I3/I5 — scope+pin lint, add boot smoke test, enable branch protection + `dev`.
19. G1/J2/J3 — retire/relabel the QoL review, normalize markdown, fix the filename typo.

---

## L. Open Questions For You (need decisions before I update specs)

1. **Determinism:** Do we *promise* a re-simulatable/deterministic world, or do we lean on
   full state serialization and treat generation-only as seeded? (Drives A5/B2/B3.)
No, we do not promise a re-simulatable world. In fact, we are in some cases relying on things that cannot be simulated (like LLM inputs.)
2. **Physics exceptions:** Is `NavigationServer3D` a sanctioned exception to "no physics
   nodes," or must pathfinding + steering + collision *all* be ECS-owned math? (Drives
   A1/A2.)
Make all the executive decisions about physics you require and we will review.
3. **World model:** Confirm floors are discrete 2.5D planes (recommended) vs a single true-
   3D chunk volume. (Drives A3/C4/E3.)
2.5d is approved
4. **AI backbone:** True GOAP, or deterministic objective→job-template expansion
   (recommended for scope)? (Drives B1.)
I guess we can go with deterministic for now and migrate later. yes?
5. **LLM reality:** Which provider, and do we require a fully-playable **offline/mock**
   mode as the default? (Drives B7/F1 and CI.)
LLMs: we'll start with supporting openai-compatible endpoints (endpoint, API key as required setup to use). No fully-playable offline/mock is required.
6. **Performance ceiling:** What are the target numbers (max active entities, CA cell
   budget, target FPS/frame-ms) and is a Rust/GDExtension escape hatch on the table?
   (Drives E1.)
I dunno man, you tell me
7. **Scope of "Save & Quit":** Full mid-run serialization, or only between runs via the
   Lineage Journal? (Drives B2.)
mmmmm we should have a mid-run serialization as well as in between runs, a run could be LONG


Once you pick on these seven, I can turn this review into concrete edits across the ECS
arch doc, the sprint scaffolding, README, CI, and STATE.md — still without writing a line
of gameplay code.

---

## M. Resolution Log (post-decision spec edits, 2026-07-30)

The human answered §L. Decisions are recorded in `docs/architecture_decisions.md` (ADR) and
propagated into the specs. Status of each finding:

**RESOLVED / propagated into specs:**
- A1 spatial+collision+picking → ECS spec §7; Sprint 1 scaffolding §9. (ADR-2)
- A2 pathfinding ownership → ECS spec §7 (AbstractGraph truth + NavServer exception). (ADR-2)
- A3 world model + A4-adjacent neighbor count → ECS spec §3; 2.5D. (ADR-3)
- A4 player identity → ECS spec §9; Sprint 3 banner. (ADR-14)
- A5 determinism → ECS banner; meta-progression banner. (ADR-1)
- B1 AI backbone → Sprint 3 §6 JobTemplate expansion. (ADR-4)
- B2 serialization → ECS spec §8; meta-progression banner; Sprint 0 persistence dir. (ADR-6)
- B3 RNG → ECS spec §8 RNGService. (ADR-8)
- B4 loose-item motion → ECS spec §7; Sprint 1 §9 (integrator + grid collision + sleep).
- B5 entity lifecycle → ECS spec §8; Sprint 1 banner (generational handles, atomic destroy).
- B7 LLM provider/secrets → Sprint 3 §5; `.gitignore` secrets. (ADR-5)
- C1 tick table → ECS spec §2; Sprint 1 loop (2Hz sim, hourly macro). (ADR-9)
- C2 interregnum tax on ledgers → Sprint 3 GC. (ADR-11)
- C3 game clock in Sprint 1 → Sprint 1 §8. (ADR-9)
- C4 chunk_id Vector3i → ECS spec + Sprint 1 PositionComponent. (ADR-3)
- C5 mass source of truth → ECS spec §5; material doc. 
- C6 enums not strings → ECS spec §5; Sprint 1 banner. (ADR-13)
- C7 ownership one representation → OwnershipComponent (Sprint 2/3 edits).
- D1 wealth-sync all-owned + transactional → Sprint 2 de/materialize + idempotency guard.
- D4/D5 faction & DAG caps → ADR-12 (to be enforced in Sprint 2/3 code).
- D6 currency granularity → material doc.
- D7 stack split/merge → ECS spec §7 note (loose-item rule); to detail in Sprint 5 data.
- E1/E2/E3 perf budgets, query cache, CA dimensionality → ECS spec §10; ADR-10/ADR-13.
- H1 combat stats/units → Sprint 1 §10 (strength/density/force).
- I1 project boots → project.godot autoloads/scene/icon commented until Sprint 0; STATE fixed.
- I2 CI lint scope + pin + boot smoke → `.github/workflows/godot_ci.yml`.
- I3 boot smoke → CI (guarded). I5 branch protection → to configure on origin.
- J1 doc links → README rewritten. J3 filename typo → file renamed.

**STILL OPEN (engineering fixes, consistent with the ADRs — to address in the owning sprint):**
- D2 boundary combat resolution rules (state seam behavior in Sprint 2).
- D3 crime-vs-gossip (route crime through witness+gossip; edit Sprint 4/social).
- D8 absorb-energy conservation (quantify environmental resource; Sprint 4).
- B6 abstract-faction memory log on FactionCore (Sprint 3).
- F2 reaction-matrix key normalization + intra/inter-entity semantics (Sprint 4).
- F3 memory weight/decay model (Sprint 6).
- G1 relabel/retire `ui_ux_qol_review.md`; G2 redundant (non-color/sound) encoding rule;
  G3 pull aura/ephemeral primitive into Sprint 1; G4 store edge_progress on Simulated movers
  (noted in ECS spec §7).
- H2 consistent thermodynamics model (Sprint 4).
- H3 canonical component/field registry doc (ADR-13; create alongside Sprint 1).
- I4 pin one Godot version across project/CI/local; I6 retire build_repo.py; I7 symlink note.
- J2 normalize mangled markdown/LaTeX across docs.
- D4/D5/C7 need enforcement in code when the owning sprint lands.

---

## N. Full Integration Pass (2026-07-31)

The human signed off on the [EXEC — FOR REVIEW] items (ADR-2 physics exception, ADR-10 perf
targets) and pinned Godot 4.7.1 (ADR-15). The previously "STILL OPEN" §M items have now been
integrated into their owning specs so a fresh adversarial pass reviews one coherent doc set:

- Created docs/component_and_field_registry.md (H3) — canonical components/fields/enums/tags.
- D2 boundary combat -> sprint_2_technical_scaffolding §7.
- D3 crime vs gossip -> factions §6 + world_bootstrap §7.
- D4/D5 caps + DAG compaction -> factions §6, dag §6, sprint_2 §7, sprint_3 §7 (ADR-12).
- D7 stack split/merge -> inventory_and_grimoire §3 + sprint_5.
- D8 absorb conservation -> magic §6, inventory_and_grimoire §3, sprint_4 §5.
- B6 abstract-faction memory -> factions §6, llm §6, sprint_3 §7 (FactionCore.faction_memory).
- F1 conversation UX -> llm §6, sprint_3 §7.
- F2 reaction keys/scope -> material §7, sprint_4 §5.
- F3 memory weight/decay -> factions §6, sprint_6.
- G1 QoL review relabeled as Resolved Feedback Log.
- G2 redundant (non-color/sound) encoding rule -> hud §5, ui_ux §8.
- G3 aura/ephemeral primitive pulled into Sprint 1 -> entity_behavior §6, magic §6.
- G4 Simulated mover edge_progress -> worldgen §6, sprint_2 §7, ecs §7, day_zero.
- H1 combat stats/units -> sprint_1 §10 + registry + sprint_5 bestiary.
- H2 thermodynamics model -> material §7, sprint_4 §5.
- I4 Godot 4.7.1 pin -> project.godot, CI, README §5, ADR-15.
- I6 build_repo.py retired (header note). I7 symlink note -> README §5.
- J2 mangled markdown/LaTeX normalized across docs; stray rendered-preview artifact removed
  and gitignored.
- World scale concretized (12 floors + surface, 8x8 chunks/floor, 64x64 tiles) -> dag §6,
  worldgen §6.

Remaining truly-deferred (correctly, to implementation time, not spec gaps): enforcement of
ADR-12 caps in code; the Persistence system implementation (ADR-6, spec'd but unslotted);
property/integration tests for the exploit-prone sync (to be written with the code). These are
tracked in STATE.md, not as open spec contradictions.
