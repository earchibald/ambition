# Architecture Decision Record — "The Living Delve"

**Status:** Authoritative. This document is the single source of truth for the
cross-cutting decisions below. Where any older spec disagrees, **this document wins**
until that spec is edited to match. Items marked **[EXEC — FOR REVIEW]** are executive
calls the coding agent made on the human's delegation; the human may override them.

Derived from the human's answers to the 7 open questions in `docs/ADVERSARIAL_REVIEW.md`
(2026-07-30).

---

## ADR-1 — No determinism promise; serialization is the source of continuity
**Decision:** The world is **not** re-simulatable or deterministic. We explicitly rely on
inputs that cannot be reproduced (LLM responses, wall-clock-influenced pacing). World
*continuity* comes from **state serialization**, not from replaying a seed.

**Consequences:**
- Remove all language implying the world can be re-derived from a seed. "Seed continuity"
  means *the generation seed is stored and reused for lazy regeneration of not-yet-visited
  content*, not that visited/mutated state can be recomputed — mutated state is **saved**.
- A single master **world seed** still governs *initial* procedural generation (floors,
  DAG roll tables) for reproducibility of first-generation only.
- Float math and frame-timed ticks are acceptable (no fixed-point requirement).
- See ADR-8 for the RNG service (generation + gameplay rolls), which need not be
  cross-platform-identical, only *saveable*.

## ADR-2 — Physics model **[EXEC — FOR REVIEW]**
"Godot is a dumb viewer" stands. Concrete replacement for the banned physics/`move_and_slide`
stack:

1. **Movement & collision — ECS-owned.** Active entities integrate `velocity → exact_pos`
   each Micro tick, then a **`CollisionResolveSystem`** performs swept-AABB / grid-DDA
   against the chunk `tile_map` solid cells and slides/stops the entity. No
   `CharacterBody3D`, `RigidBody3D`, or `move_and_slide()`. Viewer nodes are plain
   `Node3D`/`MeshInstance3D` that lerp toward `exact_pos`.
2. **Spatial queries (melee overlap, interaction target, Tactical-Lens / mouse picking) —
   ECS-owned.** A **uniform spatial hash** (`{cell → [entity_id]}`) per Active chunk is
   rebuilt/updated each Micro tick. Crosshair & mouse picking cast a camera ray and march
   it (DDA) through the spatial hash + `tile_map` in pure math. **No Godot physics
   raycasts / `Area3D`.**
3. **Pathfinding — two tiers.**
   - **Abstract topological graph (ECS-owned, source of truth):** built from the
     `tile_map` at generation (nodes = room centroids / portals / stairs; edges weighted
     by distance + hazard). Drives Simulated/Abstracted movement and high-level Active
     routing. This is the pathfinder the older specs called "node-based graph."
   - **`NavigationServer3D` — SANCTIONED EXCEPTION, Active chunks only.** Used purely as a
     *local steering / path-smoothing accelerator* inside Active chunks (baked per Active
     chunk). It owns **no game state**; it is a query service, like the renderer. If its
     region isn't baked yet, fall back to grid A* on the `tile_map`. Rationale for the
     exception: it is viewer-adjacent and stateless; collision and truth remain in the ECS.
   - **Boundary hand-off:** when a mover crosses into a Simulated chunk mid-path, its
     remaining route converts to abstract-graph edge traversal (and vice-versa on
     promotion to Active).

**This supersedes** CLAUDE.md's blanket "no `Area3D`" *only* to the extent of sanctioning
`NavigationServer3D` for Active-chunk steering. Everything else in the Prime Directive
stands. (Human: override here if you want NavServer banned too — then local steering also
becomes grid A* in the ECS.)

## ADR-3 — World model: discrete 2.5D floors
**Decision:** Floors are **discrete 2.5D planes** (a 2D tile grid plus per-tile height /
elevation for fluid flow and drops). There is no single true-3D chunk volume.

**Consequences:**
- `chunk_id: Vector3i(x, y, floor)`. **This is the canonical chunk-id type everywhere**
  (replaces every `chunk_id: int`).
- **Active set** = the 3×3 same-floor neighborhood around the player's chunk (9 chunks)
  **plus** the single entry/landing chunk of the floor directly above and below (for
  stair/elevator transitions). Not a full 3×3×3.
- Cellular-Automata fluids run on a **2D grid per chunk with a heightmap** (fluid flows to
  lower-elevation neighbors), not a 3D voxel volume.
- The "8 immediate neighbors" language in the ECS/world-gen specs is corrected to the
  above.

## ADR-4 — AI backbone: deterministic objective→job-template expansion now; GOAP later
**Decision:** Do **not** build true GOAP yet. Each LLM/high-level `objective` maps to a
fixed, **data-driven Job Template** (an ordered set of job types with preconditions) that
the faction planner instantiates and profession-filters. Migrate to real GOAP later behind
the same `objective → jobs` interface if emergent planning is needed.

**Consequences:**
- Define a `JobTemplate` table: `objective → [ {job_type, count/ratio, preconditions,
  target_selector} ]` (e.g., `RAID_FACTION → [Equip@barracks, FormSquad, PathfindTo(target
  anchor), Siege]`). Data-driven so content is JSON, not code.
- Sprint 3's "translate objective to GOAP jobs" becomes "expand objective via JobTemplate."
- Keep the boundary clean: the planner exposes `plan(objective, faction) → jobs`; the
  implementation (templates vs GOAP) is swappable.

## ADR-5 — LLM: OpenAI-compatible endpoints; no offline gameplay mode required
**Decision:** Support **OpenAI-compatible chat/completions endpoints**. Required setup =
`{ endpoint_url, api_key, model }`. A fully-playable offline/mock mode is **not** required.

**Consequences:**
- `LLMProvider` interface with one production impl: OpenAI-compatible HTTP via
  `HTTPRequest`, using `response_format: {"type":"json_object"}` (or the provider's
  structured-output equivalent) + the strict schema.
- **Config & secrets:** `endpoint`/`model` live in a committed config file with an env-var
  override; **`api_key` is read from an environment variable or `user://` config and is
  NEVER committed**. Add the config path to `.gitignore` if it can contain a key.
- **Tests/CI:** a lightweight **`NullLLMProvider` stub** (returns a canned valid-JSON
  `FORTIFY` payload) is injected in headless tests so CI never makes network calls. This is
  a *test double*, not a shipped gameplay mode.
- **Cost control:** cache responses by prompt hash within a run; keep the staggered queue +
  a per-session request budget.

## ADR-6 — Save/serialization: both mid-run and between-run
**Decision:** Support **full mid-run serialization** ("Save & Quit / suspend") *and*
between-run persistence (Lineage Journal). Runs may be very long.

**Consequences:**
- A first-class **Persistence system** is required (promote to an explicit Sprint — see
  ADR-9 sequencing). Save payload is authoritative and versioned:
  - ECS: every component registry (design components to serialize cleanly — see ADR-7).
  - World: `DAG` (with runtime edges), `WorldGrid` (chunk states, tile_maps, ledgers,
    volume pools), lazy-gen status per floor, master seed + RNG stream states (ADR-8).
  - Meta: Lineage Journal JSON (survives death, already spec'd).
- Save format carries a **`schema_version`** for forward migration.
- Partially-generated lazy floors save their *seed + generation status* so they can be
  regenerated on load (consistent with ADR-1: unvisited = regenerate from seed; visited/
  mutated = saved explicitly).
- Serialization is a hot path candidate for the Rust escape hatch (ADR-10).

## ADR-7 — Entity lifecycle: canonical registry, atomic destroy, generational handles
**Decision (foundational, Sprint 1):**
- Maintain a **single canonical list of component registries** in `ECSManager`.
  `destroy_entity(id)` MUST remove the id from **every** registry + `action_queues` +
  spatial hash in one operation (or use a columnar/archetype store where destroy is one op).
- Entity references are **generational handles** (`{index, generation}`); a reused index
  with a bumped generation invalidates stale references (detect dangling reads).
- This shapes component/memory layout, so it is decided **before** any Sprint 1 code.

## ADR-8 — RNG service (saveable, not cross-platform-deterministic)
**Decision:** One `RNGService` with named, independently-seeded streams (`worldgen`, `dag`,
`combat`, `mutation`, `economy`, `loot`). Seeded from the master world seed. Stream states
are **serialized in saves** (ADR-6). No requirement that streams reproduce identically
across platforms — only that a loaded save continues from the saved stream state.

## ADR-9 — Canonical time / tick table
**Decision (supersedes all conflicting tick statements):**

| Tick | Rate (real time) | Drives | Notes |
|------|------------------|--------|-------|
| **Micro** | 60 Hz (Godot `_physics_process`) | Active-chunk physics, movement, collision, CA fluids, combat, ephemerals | Active LoD only |
| **Simulation** | **2 Hz** | Tier-2 needs, jobs, LoD state updates, utility AI | Active + Simulated |
| **Macro** | fires every **10 real seconds**, advancing **1 in-game hour** | economy/gray-box, climate/weather, LLM reasoning triggers, schedules' day-night | Game calendar derives from hour counts |

Derived game-time: 24 macro ticks = 1 day; 360 days = 1 year (existing calendar).
- LLM "weekly" strategy re-eval = every 24×7 = 168 macro ticks (or crisis-triggered).
- Weather is evaluated per macro tick (hourly) — fine granularity for rain→puddles.
- **Interregnum (1-year skip)** does NOT run 8,640 hourly macro ticks. It runs a dedicated
  **coarse interregnum pass**: 12 **monthly** coarse macro-ticks operating purely on
  ledgers / abstract populations / DAG (see ADR-11). This reconciles Sprint 3's "12
  monthly ticks" with the hourly macro tick — they are different tick *classes*.

## ADR-10 — Performance targets & budgets **[EXEC — FOR REVIEW]**
Reference hardware: mid-range desktop (≈ Apple M1 / Ryzen 5). Targets:

- **Frame:** 60 FPS / 16.6 ms. Combined ECS Micro-tick systems budget **≤ 8 ms/frame**;
  the rest for rendering/UI.
- **Active entities** (fully physical, in the Active neighborhood): target **≤ 1,500**;
  **hard cap 3,000** before the LoD system forces excess to Simulated.
- **Total individual entities** (Tier 2/3 across all LoD): soft target **≤ 10,000**;
  enforced by faction caps (ADR-12) + swarm caps. Tier 1 swarms are integers, not entities.
- **CA fluids:** 2D-per-floor, per-chunk 64×64 grid. Simulate only **active (dirty) fluid
  cells** via a sparse set — never full-grid scans. Budget **≤ 20,000 active fluid
  cell-updates / Micro tick** across all Active chunks; overflow routes to
  `VolumePool`/flood buffer.
- **Queries:** systems iterate an **archetype/query cache** (entities grouped by component
  mask), not linear `get_all_entities_with_component` scans (see ADR-13).

**Rust/GDExtension escape hatch: APPROVED**, behind stable ECS interfaces, for hotspots:
(1) Cellular Automata, (2) spatial hash / grid raycast, (3) serialization. Start in
GDScript, profile against the budgets above, port hotspots without touching game logic.
Component hot data uses `PackedInt32Array`/`PackedFloat32Array` to ease porting.

## ADR-11 — Interregnum operates on ledgers, not physical entities
**Decision (fixes review §C2):** During the interregnum time-skip the world is Abstracted,
so wealth lives in **integer ledgers** and swarms in **population counters**. The Entropy
Tax and Swarm Tax therefore operate on **ledgers and counters**, not on
`PhysicalPropertyComponent` entities (which barely exist during the skip). Physical-entity
GC still runs to clear any residual loose items, but the *economic* tax is applied to
`abstract_wealth_ledger` values and abstract populations.

## ADR-12 — Bounded factions & runtime DAG
**Decision (fixes review §D4/D5):**
- Hard cap on simultaneous factions / Tier-3 LLM agents (**default 24**, tunable). When
  exceeded, merge or abstract the weakest into gray-box pools. `DiplomacyComponent` keeps
  only the top-K (**default 12**) relationships.
- The runtime **DAG is periodically compacted**: prune edges/nodes with no live
  descendants, artifacts, or physical ruins, on a slow cadence and at each interregnum.

## ADR-13 — Query acceleration & canonical component identity
- Add an **archetype/query index** (entities grouped by component mask) so per-tick systems
  iterate only matching entities.
- Maintain a **canonical component/field registry** doc that all sprints reference; fix
  drift (`swarm_population`, ownership representation, `phase` enum vs string) against it.

## ADR-14 — Canonical player identity
**Decision (fixes review §A4):** `Player = Entity 0 = Faction 0`, and a synthetic
**Faction-0 DAG node** is registered at world gen so LLM targeting / the Validation Gate
resolve. Purge the "Faction 14" example. Provide `is_player(faction_id)` in the spec.

---

## Cross-reference: which review items each ADR resolves
- ADR-1 → A5 (determinism), partially B2/B3.
- ADR-2 → A1 (spatial/collision/picking), A2 (pathfinding), B4-adjacent.
- ADR-3 → A3 (world model), C4 (chunk_id type).
- ADR-4 → B1 (GOAP).
- ADR-5 → B7 (LLM provider/secrets), F1-adjacent.
- ADR-6 → B2 (serialization).
- ADR-7 → B5 (entity lifecycle).
- ADR-8 → B3 (RNG).
- ADR-9 → C1 (tick table), C2/C3 (macro cadence, clock).
- ADR-10 → E1/E2 (perf, queries).
- ADR-11 → C2 (interregnum tax).
- ADR-12 → D4/D5 (caps, DAG compaction).
- ADR-13 → E2/H3 (queries, schema drift).
- ADR-14 → A4 (player identity).

**Still open (not covered by the 7 questions — will address during spec edits):**
D1 (wealth-sync all-owned + transactional), D2 (boundary combat), D3 (crime vs gossip),
D6/D7 (currency granularity, stack split/merge), D8 (absorb energy), B4 (loose-item
motion), B6 (abstract-faction memory), F2/F3 (reaction keys, memory weights), G-series
(UI/accessibility), H1/H2 (combat stats, thermodynamics), I-series (repo/CI), J-series
(doc hygiene). These are engineering fixes consistent with the ADRs above; they'll be
edited into the relevant specs next.
