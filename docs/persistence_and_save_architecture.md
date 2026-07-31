# Persistence & Save Architecture

**Status:** Authoritative workstream spec for ADR-6. This document defines the contract for
mid-run "Save & Quit" and between-run persistence. It is documentation only; implementation
lands in the dedicated Persistence workstream before the Sprint 3 death loop depends on it.

## 1. Scope and sequencing

Persistence is a first-class deliverable, not an afterthought. It should land after Sprint 1
establishes the ECS manager, generational handles, component registries, RNGService, and
GameClock, and before Sprint 3 relies on death-loop / Lineage behavior.

Recommended slot: **Sprint P / Sprint 2.5: Persistence Contract**.
This document is the complete roadmap/scaffold for Sprint P unless future work deliberately
splits it into separate `sprint_p_*` files.

Deliverables:
- Versioned run-save schema.
- Save/load of all ECS registries.
- Save/load of WorldGrid, DAG, RNG streams, GameClock, and Lineage Journal.
- Load-time validation and schema migration hooks.
- Targeted save/load tests for identity, ledgers, and RNG continuation.

## 2. Save root schema

Every save file has one root object:

```json
{
  "schema_version": 1,
  "created_at_utc": "2026-07-31T00:00:00Z",
  "godot_version": "4.7.1",
  "world_seed": 123456789,
  "game_clock": {},
  "rng_streams": {},
  "entities": {},
  "components": {},
  "world_grid": {},
  "dag": {},
  "lineage_journal": {},
  "manifests": {}
}
```

The save payload is authoritative for visited/mutated state. Seeds are only used to lazily
regenerate unvisited content, consistent with ADR-1.

**CRITICAL (ADR-21) — a plain JSON root cannot hold this payload.** Godot's JSON parses every
number as a double, so 64-bit integers are silently corrupted. Verified on 4.7.1: an RNG stream
state of `-5247995915623386297` round-trips to `-5247995915623386112.0`, and the restored stream
then produces a different sequence (`0.94077587` instead of `0.93109381`). That silently breaks
ADR-8's only promise. Therefore:
- Any 64-bit integer — **RNG stream state (§8) and packed EntityHandles (ADR-19)** — is stored as
  a hi/lo pair of sub-2^32 integers, or via `var_to_str`. Never as a bare JSON number.
- Bulk `Packed*Array` grids are stored as binary blobs via `var_to_bytes`; the JSON carries only
  offsets and a checksum. Measured 218x faster to decode (0.02 ms vs 4.1 ms for 262,144 ints).
- `float` fields are fine in JSON. Only integers wider than 2^53 are at risk.

## 3. Entity handles and registries

Entity references serialize as `{ "index": int, "generation": int }`. Entity index `0` is
reserved for the current player entity, and Faction `0` is the player faction per ADR-14.

The ECSManager serializes:
- Free-list / next reusable index state.
- Generation counters.
- Alive/dead handle set.
- Every component registry named in `component_and_field_registry.md`.
- Action queues, pending path requests, and other transient queues only if they are needed
  for a correct mid-run resume. Otherwise, resume should rebuild safe queues from component
  state and document the rebuild rule.

`destroy_entity(handle)` must be atomic before save begins; saves must not capture entities
partially removed from registries.

## 4. Component serialization rules

Components must be plain data (`RefCounted`/`Resource` with serializable fields). No `Node`
references, callables, live HTTPRequest objects, or NavigationServer handles may appear in
save data.

Rules:
- `mass_kg` may be saved as a cache but is recomputed/validated on load from volume and
  composition.
- `MaterializationComponent` controls whether an item appears in a ledger or identity
  manifest at lower LoD.
- `PerceptionComponent.last_known_targets` may be saved for mid-run continuity.
- `EphemeralComponent` TTL is saved, but expired ephemerals are discarded during load
  validation.

Unknown component types in newer saves must fail loudly unless a migration exists.

## 5. WorldGrid and lazy generation

Save `WorldGrid`:
- `ChunkData.chunk_id`, `state`, `biome_tag`.
- `tile_map`, `height_map`, `volume_pools`, `swarm_population`, `wealth_materialized`.
- Dirty flags: `tile_map_dirty`, `topology_dirty`, `nav_region_dirty`.
- Lazy generation status per floor/chunk.

Visited or mutated chunks save their tile and height data explicitly. Unvisited chunks save
seed plus generation status and may regenerate from the worldgen/dag RNG streams on load.

Active NavigationServer data is never authoritative. On load, active chunks rebuild or fall
back to grid A* until steering regions are ready.

## 6. Ledgers, manifests, and LoD identity

Fungible commodity stacks can serialize into `FactionCoreComponent.abstract_wealth_ledger`.
Identity-bearing objects serialize into `manifests`, not ledgers:

- Equipped gear stays attached to its owner handle.
- Unique/artifact/quest items keep entity handles and component state.
- Containers/stashes preserve nested manifests.
- Caravan cargo preserves a route/cargo manifest for interception.
- Unowned junk/filth follows entropy/GC rules.

This preserves the Sprint 2 anti-dupe guarantee without erasing unique items.

## 7. DAG and history

Save:
- DAG nodes and edges, including runtime edges created during play.
- Compaction watermark/cadence state.
- Synthetic Faction-0 player node.
- Links from artifacts/factions/locations to ECS handles or manifests.

Compaction must not prune nodes with live descendants, artifacts, physical ruins, active
quests, or Lineage Journal references.

## 8. RNG and time

Save every RNGService stream state: `worldgen`, `dag`, `combat`, `mutation`, `economy`,
`loot`, and any later named streams. A loaded save only promises continuation from saved
stream states, not cross-platform deterministic replay.

Save GameClock: hour, day, season, year/epoch, and any macro/interregnum counters.

## 9. Lineage Journal vs run save

The run save captures the current in-progress world. The Lineage Journal captures
between-run knowledge:
- Known runes and translated spell schematics.
- Material/crafting discoveries.
- Bestiary/insight maxima.
- Auto-generated DAG chronicle entries.
- Manual player notes.

On death, the new Entity 0 receives a fresh BodyComponent but synchronizes MindComponent
knowledge from the Lineage Journal, per the meta-progression spec.

## 10. Validation and tests

Minimum test requirements when implemented:
- Save/load preserves EntityHandle generation and rejects stale handles.
- Save/load preserves RNG continuation for named streams.
- Active -> Simulated -> save -> load -> Active preserves total faction value.
- Equipped/unique/container/caravan items do not ledgerize.
- Dirty topology flags survive load and force graph/nav rebuild or grid A* fallback.
- Expired ephemerals are discarded; valid ephemerals resume with remaining TTL.
