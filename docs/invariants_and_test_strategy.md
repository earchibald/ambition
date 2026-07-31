# Invariants & Test Strategy

**Status:** Authoritative cross-cutting quality contract. Every sprint must preserve these
invariants. This document is not gameplay code; it defines what implementation must prove.

## 1. Purpose

The Living Delve is a systemic simulation. Bugs will often look like valid emergent behavior
unless the project defines hard invariants. This document lists the invariants that must never
be broken, the test styles that catch them, and the sprint gates that prevent regressions.

## 2. Universal invariants

### ECS identity and lifecycle
- Entity references are EntityHandles `{ index, generation }`, never bare recycled ids.
- A stale handle must fail validation instead of resolving to a different entity.
- `destroy_entity(handle)` removes that handle from every component registry, action queue,
  spatial hash, path request, manifest, and ownership index.
- Entity 0 / Faction 0 remains the current player identity contract; a new adventurer reuses
  the player slot with a valid generation transition.

### ECS/viewer separation
- Viewer nodes never own authoritative state.
- UI emits ActionIntents or queries; it never mutates ECS data directly.
- No Godot physics nodes, Area3D logic, physics raycasts, or move_and_slide drive simulation.
- NavigationServer3D is only a stateless Active-chunk steering accelerator; ECS tile_map,
  collision, and AbstractGraph remain truth.

### Tick and time
- Micro tick is 60Hz.
- Simulation tick is 2Hz.
- Macro tick fires every 10 real seconds and advances 1 in-game hour.
- Interregnum uses 12 dedicated monthly coarse passes, not ordinary hourly Macro ticks.
- Schedules, logs, climate, LLM cadence, and save timestamps read GameClock.

### Conservation and economy
- Fungible material/value cannot duplicate or disappear across Active/Simulated/Abstracted
  transitions except through an explicit entropy, tax, spoilage, consumption, or destruction
  event.
- Payment validation sums value, not mass. Mass affects physics and encumbrance only.
- `mass_kg` is a derived cache from volume and material composition; tests recompute it after
  crafting, dilution, splitting, merging, and loading.
- Ownership is `OwnershipComponent`, never an ownership tag.

### LoD materialization
- Only `MaterializationPolicy.LEDGERIZE` items become ledger entries.
- Equipped items, artifacts, containers, Residence stash contents, and caravan cargo preserve
  identity through manifests.
- Boundary oscillation cannot increase total faction value.
- Projectiles and kinetic ephemerals never freeze at a LoD boundary.

### Perception and social knowledge
- Combat, crime, and reputation are not omniscient.
- Sight requires range/FOV plus DDA line-of-sight.
- Hearing requires a noise/sensory emitter and attenuation.
- Crime reputation changes require WitnessEvents and memory/gossip propagation, except for
  the explicit witnessed "caught red-handed" fast path.

### Persistence
- Save/load preserves EntityHandle generations, component registry membership, WorldGrid,
  DAG runtime edges, RNG stream states, GameClock, ledgers, and manifests.
- Unknown schema versions or unknown components fail loudly unless a migration exists.
- Expired ephemerals are discarded on load; valid ephemerals resume with remaining TTL.
- Dirty topology/nav flags survive load and trigger rebuild/fallback behavior.

### Performance budgets
- Active physical entities target <= 1,500 and hard cap 3,000.
- Total individual Tier 2/3 entities target <= 10,000.
- CA fluids process dirty cells only, budget <= 20,000 active cell-updates per Micro tick.
- Combined ECS Micro systems target <= 8ms/frame on reference hardware.
- Systems iterate query/archetype caches, not broad linear scans in hot paths.

## 3. Required test styles

### Unit tests
Use for deterministic math and pure data:
- EntityHandle validation and generation bumping.
- Component add/remove/destroy registry behavior.
- Mass/value derivation.
- Price rounding and change-making.
- Stack split/merge.
- Reaction rule key normalization.
- Spell compile caps.
- Memory weight/decay.

### Property tests / randomized invariant tests
Use for exploit surfaces:
- Cross LoD boundary N times -> total faction value invariant.
- Split/merge/drop/pickup sequences -> total quantity invariant.
- Save/load at random simulation points -> entity registry and ledger invariants hold.
- Random tile mutations -> graph/nav dirty flags and fallback invariants hold.
- Random witness/noise scenarios -> no perception without LoS/hearing path.

If the chosen Godot/GUT stack lacks a property-test library, implement bounded randomized GUT
tests with fixed RNGService seeds and enough iterations to catch common regressions.

### Integration tests
Use for multi-system flows:
- Player buys item: payment value transfers, ownership changes, mass remains physical.
- NPC hears projectile impact behind wall: investigate, not combat.
- Witnessed crime revokes Guest_Status via memory/gossip; unwitnessed crime does not.
- Active -> Simulated -> save -> load -> Active preserves manifests and ledgers.
- Mining a wall dirties topology and allows grid A* fallback before graph/nav rebuild.

### Smoke tests
Use for build-level gates:
- Project imports headlessly.
- Main scene boots once Sprint 0 creates it.
- No GUT false-positive: tests directory must contain at least one `test_*.gd` once GUT is
  installed.

## 4. Sprint gates

### Sprint 0 gate
- Headless import works (`godot --headless --import`).
- CI runs lint on first-party directories only, and the lint step is PROVEN to execute —
  a dir-guard that silently skips every directory is a gate failure, not a pass.
- GUT installed at a pinned tag, and CI FAILS if the parsed test count is 0. "gut_cmdln.gd
  exists" is not sufficient: GUT exits 0 with zero tests run via three separate paths.
- GUT runs with `-ginclude_subdirs`; `-gdir` alone does not recurse.
- Main scene boots and prints the `ECS_BOOT_OK` sentinel; CI fails on `SCRIPT ERROR` in the
  boot log. A boot step that cannot fail is not a smoke test.
- `InputMap.has_action()` is true for move_left/move_right/move_forward/move_back/interact/
  attack/inspect/cancel.
- Agent instruction files resolve, and `CLAUDE.md` / `.claude/CLAUDE.md` are byte-identical.
- All authoritative docs are TRACKED IN GIT. An untracked doc does not exist for anyone else,
  and README links to it will dangle on a fresh clone.

### Sprint 1 gate
- ECS identity/lifecycle tests pass.
- Tick cadence tests pass.
- SpatialHash/PickSystem/CollisionResolveSystem unit tests pass.
- Perception/noise/witness primitive tests pass.
- No Godot physics-node usage in first-party gameplay code.

### Sprint 2 gate
- LoD value conservation property test passes.
- Flood buffer activation test passes.
- MaterializationPolicy manifest tests pass.
- Topology dirty/rebuild/fallback tests pass.
- AbstractGraph movement can reconstruct Simulated positions.

### Sprint P / 2.5 gate
- Save/load round trip passes for ECS, WorldGrid, DAG, RNG, GameClock, ledgers, and manifests.
- Schema version mismatch fails loudly or migrates.
- Save/load preserves dirty topology and perception state as specified.

### Sprint 3 gate
- NullLLMProvider prevents network access in tests/CI.
- Prompt salience filter outputs top-3 weight + 3 recent.
- Invalid/hallucinated LLM outputs use the single FallbackMatrix.
- Interregnum uses coarse monthly passes and ledger/counter taxes.

### Sprint 4 gate
- Reaction rules are sorted-pair and scope-aware.
- Absorb_Tag cannot double-spend environmental resources.
- Ephemerals TTL-cleanup under stress.
- Mutation social effects propagate through witness/gossip paths.

### Sprint 5/6 gate
- Every content JSON validates before runtime ingestion.
- No duplicate IDs or unknown component/tag references.
- LLM prompt compression strips engine-only data and uses canonical Faction-0 player identity.

## 5. CI guardrails

Add lightweight grep/script checks when implementation begins:
- Forbidden simulation APIs: `CharacterBody3D`, `RigidBody3D`, `Area3D`, `move_and_slide`,
  physics raycasts in first-party ECS/viewer logic.
- Stale spec/code traps: legacy ownership-as-tag spelling, string-based phase examples,
  direct global RNG calls outside RNGService internals, chain-of-thought schema fields, old
  full-3D-neighbor helper names, and ordinary macro ticks for interregnum.
- Content schema validation for all JSON/data files.
- Registry drift: every `*Component` referenced in docs/code must exist in the registry or be
  marked historical.

## 6. Failure policy

Invariant failures are blockers. Do not "fix" them by weakening the invariant unless the ADR
changes. If a test exposes an intentional design change, update the relevant ADR/spec first,
then update the test.
