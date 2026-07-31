# Archetypal Content Catalog

**Status:** Canonical seed catalog for pure content. These are archetypal object families, not
new engine features. Each archetype exists to exercise already-specified systems: ownership,
containers, perception, heat, LoD materialization, rumors, contracts, crafting, hazards, and
history.

## 1. Purpose

The project benefits from a small set of reusable content archetypes because systemic games
need objects that carry meaning across many systems. The goal is not "more loot"; it is to
seed objects that:

- create clear player affordances,
- give NPC jobs physical anchors,
- make the economy legible,
- produce gossip/history hooks,
- stress-test invariants,
- and give content authors stable templates.

All archetypes below must validate against `docs/content_authoring_and_schema_validation.md`
and component names in `docs/component_and_field_registry.md`.

## 2. Archetype families

### A. Anchor fixtures

Fixtures define places where systems converge. They are usually not inventory items.

| Archetype | Purpose | Policy | Core components/data |
|-----------|---------|--------|----------------------|
| `ITEM_BOUNTY_BOARD` | Turns LLM/faction needs into physical contracts. | `MaterializationPolicy.PRESERVE_ENTITY` | OwnershipComponent, readable document slots, ClaimTags via zone. |
| `ITEM_PUBLIC_LEDGER` | Shows prices, debts, taxes, and faction inventory summaries diegetically. | `MaterializationPolicy.PRESERVE_ENTITY` | Faction reference, readable UI payload, audit/debug hook. |
| `ITEM_FACTION_BANNER` | Physical claim marker for territory, morale, and war targets. | `MaterializationPolicy.PRESERVE_ENTITY` | OwnershipComponent, SocialIdentity link, aura/emitter payload. |
| `ITEM_SHRINE_OR_RELIC_PLINTH` | Morale/religion/social gathering anchor and artifact placement. | `MaterializationPolicy.PRESERVE_ENTITY` | OwnershipComponent, HeatSource optional, MemoryEvent hooks. |
| `ITEM_STOCKPILE_MARKER` | Declares where fungible goods materialize/dematerialize. | `MaterializationPolicy.PRESERVE_ENTITY` | OwnershipComponent, MaterializationPolicy rules, accepted material filters. |

Why these matter: they make abstract faction state visible and create deterministic targets for
jobs, raids, gossip, and LoD sync.

### B. Containers and logistics objects

Containers are content-level expressions of ContainerComponent and MaterializationPolicy.

| Archetype | Purpose | Policy |
|-----------|---------|--------|
| `ITEM_BACKPACK_BASIC` | Starting physical inventory. | `MaterializationPolicy.PRESERVE_ENTITY` |
| `ITEM_ALCHEMIST_BANDOLIER` | Fast access for vials/reagents. | `MaterializationPolicy.CONTAINER_MANIFEST` |
| `ITEM_LEAD_LINED_LOCKBOX` | Suppresses hazardous aura while adding mass. | `MaterializationPolicy.CONTAINER_MANIFEST` |
| `ITEM_STOCKPILE_CRATE` | Faction commodity storage; fungible contents may ledgerize individually. | `MaterializationPolicy.CONTAINER_MANIFEST` |
| `ITEM_CARAVAN_CHEST` | Route cargo for interception/theft. | `MaterializationPolicy.CARAVAN_MANIFEST` |
| `ITEM_RESIDENCE_STASH_CHEST` | Between-run physical stash. | `MaterializationPolicy.CONTAINER_MANIFEST` |

Why these matter: they give inventory, trade, stealth, LoD materialization, and persistence a
shared content vocabulary.

### C. Documents and knowledge objects

Documents let the DAG, LLM, and Lineage systems leak knowledge into the world.

| Archetype | Purpose | Policy |
|-----------|---------|--------|
| `ITEM_RUMOR_NOTE` | Local gossip fragment generated from MemoryEvent/DAG edge. | `MaterializationPolicy.PRESERVE_ENTITY` |
| `ITEM_BOUNTY_CONTRACT` | Physical quest produced from faction objective. | `MaterializationPolicy.PRESERVE_ENTITY` |
| `ITEM_WORK_ORDER` | Internal faction job queue made visible: haul, repair, mine, patrol. | `MaterializationPolicy.PRESERVE_ENTITY` |
| `ITEM_TAX_NOTICE` | Explains gray-box resource sinks diegetically. | `MaterializationPolicy.PRESERVE_ENTITY` |
| `ITEM_MAP_FRAGMENT` | Reveals partial AbstractGraph/floor topology. | `MaterializationPolicy.PRESERVE_ENTITY` |
| `ITEM_RUNE_TABLET` | Carries translated/unknown spell syntax. | `MaterializationPolicy.PRESERVE_ENTITY` |
| `ITEM_FIELD_NOTE` | Player-authored note synced to Lineage Journal if recovered/uploaded. | `MaterializationPolicy.PRESERVE_ENTITY` |

Why these matter: they reduce the need for abstract UI exposition and make history inspectable
as physical content.

### D. Heat, light, and sensory objects

These exercise perception, thermodynamics, stealth, and accessibility channels.

| Archetype | Purpose | Policy | Key systems |
|-----------|---------|--------|-------------|
| `ITEM_TORCH` | Light/heat source, consumes fuel, reveals tags. | `MaterializationPolicy.PRESERVE_ENTITY` | HeatSource, SensoryEmitter |
| `ITEM_BRAZIER` | Stationary heat/light/social anchor. | `MaterializationPolicy.PRESERVE_ENTITY` | HeatSource, ClaimTags |
| `ITEM_BELL_CHIME_TRAP` | Noise source for stealth/tutorials. | `MaterializationPolicy.PRESERVE_ENTITY` | SensoryEmitter, PerceptionSystem |
| `ITEM_SMOKE_POT` | Blocks LoS, changes perception without damage. | `MaterializationPolicy.PRESERVE_ENTITY` | Chemistry, PerceptionSystem |
| `ITEM_SILENCE_WRAP` | Muffles carried item acoustics. | `MaterializationPolicy.PRESERVE_ENTITY` | Container/active tag interaction |
| `ITEM_GLOW_MOSS_LAMP` | Low heat, biological light, fungal culture affordance. | `MaterializationPolicy.PRESERVE_ENTITY` | Material/biology tags |

Why these matter: they make PerceptionSystem testable and teach players the difference between
sight, hearing, heat, and chemistry.

### E. Crafting stations and tools

Stations make the material economy spatial and job-driven.

| Archetype | Purpose | Policy |
|-----------|---------|--------|
| `ITEM_FORGE_BASIC` | HeatSource station for smelting/alloys. | `MaterializationPolicy.PRESERVE_ENTITY` |
| `ITEM_ALCHEMY_STILL` | Liquids, dilution, volatile reactions. | `MaterializationPolicy.PRESERVE_ENTITY` |
| `ITEM_BUTCHER_TABLE` | Corpses -> parts, insight, filth risk. | `MaterializationPolicy.PRESERVE_ENTITY` |
| `ITEM_REPAIR_ANVIL` | Condition repair, material consumption. | `MaterializationPolicy.PRESERVE_ENTITY` |
| `ITEM_GRIMOIRE_DESK` | Safe spell dry-run/binding anchor in residence. | `MaterializationPolicy.PRESERVE_ENTITY` |
| `ITEM_LOOM_OR_TANNING_RACK` | Cloth/leather padding and stealth gear. | `MaterializationPolicy.PRESERVE_ENTITY` |

Why these matter: they anchor professions, make pre-warm output plausible, and create clear
places for the player to interact with production chains.

### F. Hazards and environmental affordances

Hazards should be objects/tiles that create systemic choices, not scripted traps.

| Archetype | Purpose | Policy |
|-----------|---------|--------|
| `HAZARD_UNSTABLE_CEILING` | Collapse risk, topology mutation, noise. | `MaterializationPolicy.PRESERVE_ENTITY` |
| `HAZARD_SEEPING_CRACK` | Boundary fluid source / flood buffer tutorial. | `MaterializationPolicy.PRESERVE_ENTITY` |
| `HAZARD_SPORE_VENT` | Mutation exposure, LoS haze, faction ecology. | `MaterializationPolicy.PRESERVE_ENTITY` |
| `HAZARD_RUST_PATCH` | Material-specific gear degradation. | `MaterializationPolicy.PRESERVE_ENTITY` |
| `HAZARD_THIN_ICE` | Phase-change terrain and kinetic breakage. | `MaterializationPolicy.PRESERVE_ENTITY` |
| `HAZARD_VOLATILE_GAS_POCKET` | Reaction rule teaching object. | `MaterializationPolicy.GC_ELIGIBLE` |

Why these matter: they provide natural tests for mutable topology, thermodynamics, reactions,
and player/NPC perception.

### G. Corpses, remains, and evidence

Remains bridge combat, ecology, crime, loot, and memory.

| Archetype | Purpose | Policy |
|-----------|---------|--------|
| `ITEM_FRESH_CORPSE` | Loot, butchery, witness/evidence, smell/noise bait. | `MaterializationPolicy.PRESERVE_ENTITY` |
| `ITEM_SKELETON_REMAINS` | Historical clue, low-value materials, map/rune hint. | `MaterializationPolicy.PRESERVE_ENTITY` |
| `ITEM_BLOOD_PUDDLE` | CA fluid, witness evidence, scent trail. | `MaterializationPolicy.GC_ELIGIBLE` |
| `ITEM_BROKEN_WEAPON` | Combat aftermath, scrap economy, historical clue. | `MaterializationPolicy.PRESERVE_ENTITY` |
| `ITEM_GRAVE_MARKER` | Memory anchor, faction morale, player death history. | `MaterializationPolicy.PRESERVE_ENTITY` |

Why these matter: they make consequences persistent and let crimes be discovered after the
moment of action.

### H. Route and boundary objects

These make abstract movement visible and interceptable.

| Archetype | Purpose | Policy |
|-----------|---------|--------|
| `ITEM_WAYSTONE` | AbstractGraph node made visible in-world. | `MaterializationPolicy.PRESERVE_ENTITY` |
| `ITEM_ELEVATOR_GATE` | Floor transition and Active-set boundary. | `MaterializationPolicy.PRESERVE_ENTITY` |
| `ITEM_CARAVAN_WAYBILL` | Route manifest, cargo ownership, target for theft. | `MaterializationPolicy.CARAVAN_MANIFEST` |
| `ITEM_BORDER_POST` | Faction boundary and patrol anchor. | `MaterializationPolicy.PRESERVE_ENTITY` |
| `ITEM_COLLAPSED_PASSAGE_MARKER` | Dirty topology/worldgen history clue. | `MaterializationPolicy.PRESERVE_ENTITY` |

Why these matter: they connect Simulated movement, player interception, LoD transitions, and
territorial control.

### I. Social tokens and faction goods

These make reputation and diplomacy physical.

| Archetype | Purpose | Policy |
|-----------|---------|--------|
| `ITEM_GUEST_TOKEN` | Physical/diegetic representation of Guest_Status. | `MaterializationPolicy.PRESERVE_ENTITY` |
| `ITEM_TRADE_SEAL` | Grants trade access with a faction. | `MaterializationPolicy.PRESERVE_ENTITY` |
| `ITEM_WAR_TROPHY` | Grievance/prestige object; can provoke or appease. | `MaterializationPolicy.PRESERVE_ENTITY` |
| `ITEM_RATION_CHIT` | Food scarcity, wage, and morale artifact. | `MaterializationPolicy.PRESERVE_ENTITY` |
| `ITEM_OATH_STONE` | Alliance/mutiny/succession ritual anchor. | `MaterializationPolicy.PRESERVE_ENTITY` |

Why these matter: they let social systems produce objects the player can steal, return,
display, or misunderstand.

## 3. Starter content set

For Sprint 5's first content pass, prioritize a minimal set that exercises the most systems:

1. `ITEM_BACKPACK_BASIC`
2. `ITEM_STOCKPILE_CRATE`
3. `ITEM_RESIDENCE_STASH_CHEST`
4. `ITEM_BOUNTY_BOARD`
5. `ITEM_BOUNTY_CONTRACT`
6. `ITEM_TORCH`
7. `ITEM_FORGE_BASIC`
8. `ITEM_BUTCHER_TABLE`
9. `HAZARD_SEEPING_CRACK`
10. `HAZARD_VOLATILE_GAS_POCKET`
11. `ITEM_FRESH_CORPSE`
12. `ITEM_BLOOD_PUDDLE`
13. `ITEM_ELEVATOR_GATE`
14. `ITEM_CARAVAN_WAYBILL`
15. `ITEM_GUEST_TOKEN`

This set covers inventory, LoD ledgers/manifests, death loop, contracts, heat/light,
crafting, CA fluids, reactions, evidence, floor transitions, caravan interception, and social
status without adding new mechanics.

## 4. Authoring rules

- Every archetype must declare its component set.
- Every archetype must declare materialization policy.
- Every archetype must declare whether it is movable, equippable, readable, containerized,
  station-like, hazardous, or zone-anchored.
- Any archetype that emits light/noise/scent must declare SensoryEmitter defaults.
- Any archetype that mutates tiles must declare topology dirty behavior.
- Any archetype that can appear in a save must declare migration-safe stable ID.
- Any archetype that can be owned must use OwnershipComponent.

## 5. What not to add yet

Avoid adding one-off named legendary items, large bestiary expansions, or bespoke quest chains
before Sprint 5 schemas exist. The useful content now is archetypal: reusable objects that
make systems legible and testable.
