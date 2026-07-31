# Canonical Component & Field Registry

**Status:** Authoritative reference (ADR-13 / review H3). Every sprint and system doc must
match this registry. When a spec names a component, field, enum, or tag, it must use the
names/types here. Governed by `architecture_decisions.md`.

This exists so cross-document drift (int vs Vector3i, string vs enum, tag vs component
ownership, `swarm_population`, `OwnedByFaction` vs `OwnershipComponent`) cannot recur.

---

## 1. Identity & handles (ADR-7 / ADR-14)
- **EntityHandle** = `{ index: int, generation: int }`. All references use handles; a reused
  index bumps `generation` so stale reads are detectable. (No bare monotonic ids.)
- **Player = Entity 0 = Faction 0**, with a synthetic **Faction-0 DAG node** registered at
  world gen. Helper: `is_player(faction_id) -> bool`.
- **chunk_id: Vector3i** = `(x, y, floor)` everywhere (ADR-3). Never `int`.

## 2. Component list (authoritative names & fields)
Pure data (`RefCounted`/`Resource`), no `Node` inheritance.

| Component | Fields |
|-----------|--------|
| `PositionComponent` | `floor_id:int`, `chunk_id:Vector3i`, `exact_pos:Vector3`, `velocity:Vector3`, `current_node_id:int`, `current_edge:int`, `edge_progress:float`, `edge_speed:float` |
| `PhysicalPropertyComponent` | `quantity:int`, `mass_kg:float` (derived cache — see §5), `volume_cm3:float`, `temperature:float`, `heat_capacity:float`, `phase:Phase(enum)` |
| `MaterialCompositionComponent` | `materials:Dictionary{MaterialID:float}` (percentages, sum≈1.0) |
| `ChemistryComponent` | `active_tags:Array[StringName]` |
| `QualityComponent` | `condition:Quality(enum)` |
| `NeedsComponent` | `hunger:float`, `energy:float`, `morale:float` |
| `BodyComponent` | `max_health:float`, `health:float`, `stamina:float`, `strength:float`, `mutations:Array[StringName]`, `skills:Dictionary{StringName:float}`, `exposure:Dictionary{StringName:float}` |
| `MindComponent` | `known_runes:Array[StringName]`, `insight:Dictionary{StringName:int}`, `faction_reputations:Dictionary{int:float}`, `language_fluency:Dictionary{StringName:int}` |
| `LoDComponent` | `current_state:LoD(enum)` |
| `InventoryComponent` | `held_items:Array[EntityHandle]`, `total_volume_used:float`, `sub_containers:Array[EntityHandle]` |
| `JobComponent` | `current_action:StringName`, `target_entity:EntityHandle`, `target_location:Vector3`, `claimed_by:EntityHandle`, `status:JobStatus(enum)` |
| `ScheduleComponent` | `blocks:Array` (hour-range → schedule state) |
| `FactionCoreComponent` | `faction_id:int`, `culture_tags:Array[StringName]`, `diplomacy:Dictionary{int:RelationshipState}` (top-K only), `abstract_wealth_ledger:Dictionary{MaterialID:int}`, `abstract_population:int`, `faction_memory:Array[MemoryEvent]` (§4) |
| `SocialIdentityComponent` | `faction_id:int`, `loyalty:float`, `prestige:float` |
| `MemoryComponent` | `events:Array[MemoryEvent]` |
| `OwnershipComponent` | `faction_id:int` (THE single ownership representation — not a tag) |
| `EphemeralComponent` | `time_to_live:float`, `source_entity:EntityHandle`, `payload` |
| `FloodSourceComponent` | `pending_volume:int`, `material_id:MaterialID` |
| `LLMPromptComponent` | `persona_node_id:int`, `pending_reasoning:bool` |
| `PlayerInputComponent` | (marker; attached only to Entity 0 while alive) |

## 3. Enums (GDScript `enum`, never strings — ADR-13/C6)
- `Phase { SOLID, LIQUID, GAS }`
- `LoD { ACTIVE, SIMULATED, ABSTRACTED }`
- `Quality { PRISTINE, CHIPPED, RUINED, SCRAP }`
- `RelationshipStatus { WAR, NEUTRAL, TRADE, ALLIED }`
- `JobStatus { OPEN, CLAIMED, IN_PROGRESS, DONE, ABORTED }`
- `Objective { FORTIFY, RAID_FACTION, GATHER_RESOURCES, MIGRATE, IDLE }`
- `Emotion { CALM, FEARFUL, AGGRESSIVE, DESPERATE }`

## 4. Shared record types
- `RelationshipState` = `{ score:float(-100..100), status:RelationshipStatus, grievances:Array }`
- `MemoryEvent` = `{ text:StringName, epoch/tick:int, weight:float, core:bool }`
  (used by both `MemoryComponent` and `FactionCoreComponent.faction_memory`; weight/decay
  model defined in the LLM/factions docs).

## 5. Derived values (single source of truth)
- **mass_kg** is a cache: `mass_kg = volume_cm3 * Σ(materials[m] * density[m])` using
  `density_kg_per_cm3` from the Sprint 5 material dictionary. Recompute on composition/volume
  change. Never edit independently. (review C5)
- **item value** derives from composition base_values × quality modifier; prices apply the
  scarcity formula (material/economy doc).

## 6. Chunk & world data
- `ChunkData` = `chunk_id:Vector3i`, `state:LoD`, `biome_tag:StringName`,
  `tile_map:PackedInt32Array`, `height_map:PackedFloat32Array` (2.5D), `volume_pools:Dictionary`,
  `swarm_population:int`, `wealth_materialized:bool`.
- Tier-1 swarms are **integers** (`ChunkData.swarm_population` / zone `PopulationComponent`),
  not individual entities, until materialized on Active.

## 7. Tag vocabulary conventions
- Tags are `StringName` in `ChemistryComponent.active_tags` (state/chemistry) — e.g.
  `&"Burning"`, `&"Wet"`, `&"Toxic"`, `&"Filth"`, `&"Kinetic_Ephemeral"`, `&"Guest_Status"`,
  `&"Reaction_Cooldown"`, `&"Muffled"`, `&"Bursting"`.
- **Ownership is NOT a tag** — use `OwnershipComponent`. Zone control uses `ClaimTags` on the
  zone entity, which is distinct from item ownership.
- Reaction-matrix keys are the **sorted** tag pair (see material/Sprint-4 docs) so
  `A+B == B+A`.
