# Canonical Component & Field Registry

**Status:** Authoritative reference (ADR-13 / review H3). Every sprint and system doc must
match this registry. When a spec names a component, field, enum, or tag, it must use the
names/types here. Governed by `architecture_decisions.md`.

This exists so cross-document drift (int vs Vector3i, string vs enum, tag vs component
ownership, `swarm_population`, `OwnedByFaction` vs `OwnershipComponent`) cannot recur.

---

## 1. Identity & handles (ADR-7 / ADR-14 / **ADR-19**)
- **EntityHandle is a plain `int`** — a packed 64-bit value, NOT an object (ADR-19).
  `index = h & 0xFFFFFFFF`, `generation = h >> 32`, **`EH.INVALID = 0`**, generations start at 1
  (so `is_valid(h)` is `h > 0`). Not `-1`: GDScript's `>>` rejects negative operands and a
  constant-folded `-1 >> 32` is a hard parse error.
  A reused index bumps `generation` so stale reads are detectable. (No bare monotonic ids.)
  **A `RefCounted` handle cannot be a Dictionary key in GDScript** — it hashes by object
  identity, so `d.has(other_handle_with_same_values)` is `false` and the dict silently grows a
  second entry. Verified on 4.7.1. Every registry below is keyed by this packed int.
- Anywhere older text says `EntityHandle`, the GDScript type is `int`; collections of handles
  are `PackedInt64Array`. Saves still serialize as `{"index": i, "generation": g}`.
- **Player = Entity 0 = Faction 0**, with a synthetic **Faction-0 DAG node** registered at
  world gen. Helper: `is_player(faction_id) -> bool`.
- **chunk_id: Vector3i** = `(x, y, floor)` everywhere (ADR-3). Never `int`.

## 2. Component list (authoritative names & fields)
Pure data (`RefCounted`/`Resource`), no `Node` inheritance.

| Component | Fields |
|-----------|--------|
| `PositionComponent` | `floor_id:int`, `chunk_id:Vector3i`, `exact_pos:Vector3`, `velocity:Vector3`, `current_node_id:int`, `current_edge:int`, `edge_progress:float`, `edge_speed:float` | **STORED AS COLUMNS** — parallel `PackedFloat32Array`s on `ECSManager` (`col_pos_x`…), never a RefCounted per entity. This is the "Data Arrays over Nodes" directive: it is the hottest data in the build and one object per entity would defeat the point |
| `PhysicalPropertyComponent` | `quantity:int`, `mass_kg:float` (derived cache — see §5), `volume_cm3:float`, `temperature:float`, `heat_capacity:float`, `phase:Phase(enum)` |
| `MaterialCompositionComponent` | `volume_fractions:Dictionary{StringName:float}` (**VOLUME** fractions, sum = 1.0 ± 0.001 — see §5) |
| `ChemistryComponent` | `active_tags:Array[StringName]`, `tag_expiry:Dictionary{StringName:int}` (Micro-frame deadline per TIMED tag; a tag absent from this map never lapses. Sprint 4 needs `Reaction_Cooldown` to lift after exactly 60 frames, and expiry lives on the COMPONENT so `destroy_entity` clears it atomically — a system-side map keyed by row would hand a recycled row the previous occupant's cooldown) |
| `QualityComponent` | `wear:float` (0.0 pristine → 100.0 destroyed, the authoritative value), `condition:Quality(enum)` (DERIVED band — see §5) |
| `BoundsComponent` | `half_extents:Vector3` (metres, ADR-18). Required by CollisionResolveSystem and the SpatialHash; any entity that collides or is picked must have one. |
| `MaterializationComponent` | `policy:MaterializationPolicy(enum)`, `item_class:StringName` (`manifest_id` removed 2026-08-01 with the unused `*_MANIFEST` policies' plumbing) |
| `NeedsComponent` | `hunger:float`, `energy:float`, `morale:float` |
| `BodyComponent` | `species:StringName` (what kind of body, e.g. `SPC_CORPSE_RAT`; added 2026-08-01 — `spawn_creature` took a species, branched on it for stats and discarded it, so nothing downstream could name an animal), `max_health:float`, `health:float`, `stamina:float`, `max_stamina:float`, `strain:float` (casting Strain — temporary damage to the effective stamina ceiling, healed by rest), `strength:float`, `structural_toughness:float`, `armor_rating:float`, `mutations:Array[StringName]`, `skills:Dictionary{StringName:float}`, `exposure:Dictionary{StringName:float}` (corrected 2026-08-01: three of the five stat channels the Sprint 4 mutation table writes were undeclared here) |
| `MindComponent` | `known_runes:Array[StringName]`, `insight:Dictionary{StringName:int}`, `grimoire:Dictionary{StringName:CompiledSpell}` (bound Action_IDs), `active_spell:StringName` (what the cast key fires). (`faction_reputations` and `language_fluency` were declared here with no reader anywhere; removed 2026-08-01 — the translation-cipher minigame, declared gap G-1, re-adds fluency with its feature) |
| `LoDComponent` | `current_state:LoD(enum)` |
| `InventoryComponent` | `held_items:Array[EntityHandle]`, `total_volume_used:float` (`sub_containers` removed 2026-08-01: declared, never read — nested containers return with their feature) |
| `ContainerComponent` | `capacity_cm3:float`, `accepts_tags:Array[StringName]`, `rejects_tags:Array[StringName]`, `allow_nested_container:bool` |
| `JobComponent` | `current_action:StringName`, `target_entity:EntityHandle`, `target_location:Vector3`, `claimed_by:EntityHandle`, `status:JobStatus(enum)`, `score_at_claim:float` (the latch compares preemption candidates against this), `progress_ticks:int` (Simulation ticks IN_PROGRESS; what makes DONE reachable) |
| `ScheduleComponent` | `blocks:Array` (hour-range → schedule state) |
| `FactionCoreComponent` | `faction_id:int`, `culture_tags:Array[StringName]`, `diplomacy:Dictionary{int:RelationshipState}` (top-K only), `abstract_wealth_ledger:Dictionary{MaterialID:int}`, `abstract_population:int`, `faction_memory:Array[Dictionary]` (record shape in §4), `anchor_chunk_id:Vector3i`, `dag_node_id:int`, `current_objective:Objective(enum)`, `current_emotion:Emotion(enum)`, `objective_target:int`, `last_declaration:String`, `last_reasoning:String` (the reasoner's capped one-line why), `leader_handle:EntityHandle` (the Tier 2 citizen currently leading; succession promotes the highest-prestige member here) (corrected 2026-08-01: the Sprint 3 objective state was undeclared) |
| `SocialIdentityComponent` | `faction_id:int`, `loyalty:float`, `prestige:float` |
| `ProfessionComponent` | `profession:StringName` |
| `MemoryComponent` | `events:Array[MemoryEvent]` |
| `OwnershipComponent` | `faction_id:int` (THE single ownership representation — not a tag) |
| `EphemeralComponent` | `time_to_live:float`, `source_entity:EntityHandle`, `payload:Dictionary`, `radius_m:float`, `expansion_mps:float`, `applies_tags:Array[StringName]`, `removes_tags:Array[StringName]`, `energy_j:float`, `speed_mps:float`, `heading:Vector3`, `trigger:StringName`, `arm_after_s:float`, `cone_angle_deg:float`, `spent:bool`, `blast_radius_m:float` (Sprint 4: the TRIGGER decides when the payload fires, the SHAPE decides where — a single `detonates` flag could express neither the timer nor the proximity mine) |
| `FloodSourceComponent` | `pending_volume:int`, `material_id:MaterialID` | **NOT YET IMPLEMENTED** |
| `HeatSourceComponent` | `stored_energy:float`, `max_temperature:float` (temperature ceiling while lit, enforced by the burn pass), `output_j_per_tick:float` (fuel spent into the chunk air per Micro tick; a drained source stops Burning). (`fuel_materials` removed 2026-08-01: a refuelling list nothing read) |
| `PerceptionComponent` | `sight_range_m:float`, `fov_degrees:float`, `hearing_sensitivity:float`, `awareness_state:AwarenessState(enum)`, `last_known_targets:Dictionary{EntityHandle:Vector3}` |
| `SensoryEmitterComponent` | `noise_radius_m:float` (`visibility_modifier` and `scent_tags` removed 2026-08-01: no visibility or scent sense reads them yet) |
| `ZonePopulationComponent` | `population_by_species:Dictionary{StringName:int}` | **NOT YET IMPLEMENTED** — the per-species swarm cap needs this; Sprint 3 caps the single `ChunkData.swarm_population` total instead |
| `LLMPromptComponent` | `persona_node_id:int`, `pending_reasoning:bool` | **NOT YET IMPLEMENTED** — succession is specified to grant this on promotion; neither exists yet |
| `PlayerInputComponent` | (marker; attached only to Entity 0 while alive) |
| `LooseItemComponent` | `resting:bool`, `still_ticks:int` (sleep-on-rest debounce), `inscribed_runes:Array[StringName]` (readable knowledge on lecterns/tablets — the `Inscribed` route into rune learning) |
| `LocomotionComponent` | `waypoints:Array[Vector3]` (consumed front-first; there is no separate index), `destination:Vector3`, `has_destination:bool`, `speed_mps:float`, `replan_cooldown:int` (route state lives here so a Simulated mover keeps its progress across a LoD demotion) (corrected 2026-08-01: the declared `waypoint_index` never existed in code) |

**"STORED AS COLUMNS"** marks a logical component realised as packed arrays rather than a class. It is exempt from the class check for the same reason it exists.

**"NOT YET IMPLEMENTED" is load-bearing.** Added 2026-08-01 after an audit found three registry
components with no class and one real component (`LooseItemComponent`) with no registry row. The
registry is declared canonical, so an undeclared component is invisible to save/load, validators
and every future agent, and a declared-but-absent one is a promise a later sprint will try to
call in. `tests/invariants/test_forbidden_apis.gd` now enforces both directions: every row without
that marker must have a class in `ecs/components/`, and every class there must have a row.

## 3. Enums (GDScript `enum`, never strings — ADR-13/C6)
- `Phase { SOLID, LIQUID, GAS }`
- `LoD { ACTIVE, SIMULATED, ABSTRACTED }`
- `Quality { PRISTINE, CHIPPED, RUINED, SCRAP }`
- `RelationshipStatus { WAR, NEUTRAL, TRADE, ALLIED }`
- `JobStatus { OPEN, CLAIMED, IN_PROGRESS, DONE, ABORTED }`
- `Objective { FORTIFY, RAID_FACTION, GATHER_RESOURCES, MIGRATE, IDLE }`
- `Emotion { CALM, FEARFUL, AGGRESSIVE, DESPERATE }`
- `AwarenessState { UNAWARE, SUSPICIOUS, INVESTIGATING, COMBAT }`
- `MaterializationPolicy { LEDGERIZE, PRESERVE_ENTITY, CONTAINER_MANIFEST, CARAVAN_MANIFEST, GC_ELIGIBLE }`
- `NodeType { FACTION, LEADER, LOCATION, ARTIFACT, EVENT_ABSTRACT }` (DAG history graph)
- `NodeStatus { ACTIVE, DESTROYED, DORMANT }` — DESTROYED nodes are **retained, never deleted**:
  a conquered faction is the reason its conqueror holds that territory.
- `EdgeType { FOUNDED, DESTROYED, CONQUERED, MIGRATED_TO, FORGED, ALLIED_WITH, KILLED_BY }`
  - Edge direction is `(source = the subject the edge is about, target = the other party)`.
    `CONQUERED(aggressor, victim)`. `KILLED_BY(victim, killer)`. `DESTROYED` is written as a
    self-loop `(node, node)` meaning "this node ceased to exist".
  - `KILLED_BY` added 2026-08-01: the Sprint 3 roadmap asked for a player-death edge and named a
    type that was not in this enum, so the implementation overloaded `DESTROYED` and recorded the
    death with the direction reversed. A death with no killer is `KILLED_BY(victim, victim)`.

## 4. Shared record types
- `RelationshipState` = `{ score:float(-100..100), status:RelationshipStatus, grievances:Array }`
- `MemoryEvent` (class, `MemoryComponent.events`) = `{ event_id:int (globally unique — REQUIRED
  for gossip dedup), kind:StringName (weight class), text:StringName, tick_hours:int, core:bool,
  subject:EntityHandle }`. Weight is NEVER stored — `weight_at(now)` derives it from age.
- `faction_memory` record (Dictionary, `FactionCoreComponent`) = `{ event_id:int, text:String,
  tick:int, weight:float (the BASE weight — decay is applied at read via
  `PromptBuilder.decayed_weight`, corrected 2026-08-01: the stored snapshot never decayed),
  core:bool }`. Two shapes for one concept, recorded as such: the class is the per-entity
  record, the dictionary is the ledger-side summary.
- `WitnessEvent` = `{ observer:EntityHandle, subject:EntityHandle, action:StringName,
  location:Vector3, tick:int, confidence:float }` (used for crime, stealth, mutation, and
  reputation propagation; generated by PerceptionSystem). `action` is `MURDER`, `ASSAULT`,
  `THEFT`, `TRESPASS`, or `MUTATION_<track>`. **Only the mutation actions have a severity that
  depends on the WITNESS**: a fungal mutation is a defilement to a farming culture and a mark of
  favour to a scavenging one (`ReputationSystem.severity_for`). Crime severity is constant.
- `CompiledSpell` (Sprint 4) = a validated spell produced ONLY by `SpellCompilerSystem.compile`:
  `{ spell_id:StringName, runes:Array[StringName], complexity:int, strain_cost:float,
  trigger:StringName, shape:StringName, radius_m:float, speed_mps:float, ttl_s:float,
  expansion_mps:float, delay_s:float, cone_angle_deg:float, applies_tags:Array[StringName],
  removes_tags:Array[StringName], energy_j:float, absorbs:StringName, absorb_j:float,
  caps_applied:Array[StringName], unstable:bool (branded by a FORCED overclock compile;
  every cast rolls the d100 mishap table) }`. Nothing else may construct one: the geometric
  caps are anti-crash rules, and a second construction path is a second place to forget them.

## 5. Derived values (single source of truth)
- **Composition fractions are VOLUME fractions, not mass fractions.** The mass formula below is
  a volume-weighted mean density, so it is only correct for volume fractions. The old field was
  named `materials` and documented merely as "percentages", which every authoring example reads
  as mass. The error is not small: `{MAT_IRON: 0.8, MAT_WATER: 0.2}` gives ρ = 6.499 g/cm³ read
  as volume fractions but 3.316 g/cm³ read as mass fractions — a **96% error** propagating into
  every derived mass, encumbrance value, and combat threshold. Authors who think in mass convert
  with `volume_fraction_i = (w_i / ρ_i) / Σ(w_j / ρ_j)`; content may carry `by_mass: true` and
  be converted at load. The validator rejects any composition not summing to 1.0 ± 0.001.
- **mass_kg** is a cache: `mass_kg = volume_cm3 * Σ(volume_fractions[m] * density[m])` using
  `density_kg_per_cm3` from the SEED material dictionary in
  `material_crafting_and_economy_architecture.md` §2 (authoritative from Sprint 1; Sprint 5
  expands it). Recompute on composition/volume change. Never edit independently. (review C5)
- **condition** is a derived band over `wear` — never set independently:
  `wear < 25 → PRISTINE`, `< 50 → CHIPPED`, `< 85 → RUINED`, else `SCRAP`.
  Degradation always writes `wear` (a float, on a Simulation-tick cadence), because an enum
  cannot be decremented "by 1 point per tick" or multiplied by a percentage.
- **item value** derives from composition base_values × quality modifier; prices apply the
  scarcity formula (material/economy doc).

## 6. Chunk & world data
- `ChunkData` = `chunk_id:Vector3i`, `state:LoD`, `biome_tag:StringName`,
  `tile_map:PackedInt32Array`, `height_map:PackedFloat32Array` (2.5D, metres),
  `ambient_temperature_c:float`, `volume_pools:Dictionary`,
  `swarm_population:int`, `hazard_tags:Array[StringName]` (ZONE-level hazards — `Spores`,
  `Filth`, `Toxic`, `Radiation` — that `MutationSystem` accrues exposure from. Chunks are not
  entities, so this is chunk data and deliberately NOT a `ChemistryComponent`),
  `wealth_materialized:bool`, `props_spawned:bool` (one-shot ruin-prop spawn at first
  promotion), `claim_faction_id:int` (the ClaimTag: which faction considers this chunk theirs,
  -1 unclaimed; consumed by the trespass rule in `SocialSystem`), `tile_map_dirty:bool`,
  `topology_dirty:bool`, `nav_region_dirty:bool`,
  and the **cellular-automata fluid buffers** (these had no owner before):
  `volume_map:PackedInt32Array` (read buffer), `next_volume_map:PackedInt32Array` (write
  buffer), `material_map:PackedInt32Array`, `dirty_cells:Dictionary` (used as a sparse set of
  cell indices — this is the ADR-10 "active cell" set), `flood_buffer:Dictionary`
  ({cell_index: pending_volume}).
  All grids are `CHUNK_TILES * CHUNK_TILES` = 4096 entries, row-major: `index = y * 64 + x`.
- There is **no** separate `FluidGridComponent`. Chunks are not entities; the fluid grid is
  chunk data. (Sprint 1 scaffolding's `FluidGridComponent` is superseded by these fields.)
- `ChunkData` ownership: Sprint 1 hand-authors a single test-arena chunk; Sprint 2's
  `WorldGrid` generator becomes the real producer. The consumer contract does not change.
- Tier-1 swarms are **integers** (`ChunkData.swarm_population` / zone `ZonePopulationComponent`),
  not individual entities, until materialized on Active.
- Zone-level population uses the same integer abstraction as chunks; if modeled as data rather
  than a chunk field, call it `ZonePopulationComponent`.

## 7. Tag vocabulary conventions
- Tags are `StringName` in `ChemistryComponent.active_tags` (state/chemistry) — e.g.
  `&"Burning"`, `&"Wet"`, `&"Toxic"`, `&"Filth"`, `&"Kinetic_Ephemeral"`, `&"Guest_Status"`,
  `&"Reaction_Cooldown"`, `&"Muffled"`, `&"Bursting"`, `&"Slippery"`, `&"Rupture_Cooldown"`.
  Sprint 4 adds `&"Spores"`, `&"Volatile_Gas"`, `&"Explosion"`, `&"Steam"`,
  `&"Smoke"`, `&"Radiation"`, and the `Resist_*` family (`&"Resist_Spores"`, `&"Resist_Filth"`,
  `&"Resist_Toxic"`, `&"Resist_Radiation"`) granted by mutation or by protective gear.
  **There is no `&"Water"` tag (corrected 2026-08-01): the one word for water is `&"Wet"`** —
  the build briefly had both, and the reaction table keying one rule on each is why the
  starting water spell could not quench a fire it hit. The remediation pass adds
  `&"Inscribed"` (readable knowledge), `&"Arcane_Burn"` and `&"Bleeding"` (mishap trauma;
  Arcane_Burn cripples rest recovery until cured). `Explosion`/`Smoke`/`Burning` are TIMED
  result tags (`ReactionSystem.RESULT_TAG_LIFETIME_FRAMES`) — an event tag with no expiry is
  a permanent flag wearing an event's name.
- **Mutation tags** live in `BodyComponent.mutations`, not in `active_tags`: they are permanent
  for a run and reset on death, where chemistry tags are transient world state. Both the
  mutation's own tag (`&"Fungal_Lungs"`) and the resistance it grants are appended there.
- **Phase is NOT a tag.** `Solid`/`Liquid`/`Gas` are `Phase` enum values on
  `PhysicalPropertyComponent.phase`. Never write `&"Solid"` into `active_tags`.
- **Ownership is NOT a tag** — use `OwnershipComponent`. Zone control is
  `ChunkData.claim_faction_id` (§6), which is distinct from item ownership.
- **Profession is NOT an ad-hoc tag** in implementation docs — use `ProfessionComponent`;
  legacy prose like `[Prof_Hauler]` is shorthand for that component value.
- Reaction-matrix keys are the **sorted** tag pair (see material/Sprint-4 docs) so
  `A+B == B+A`.
