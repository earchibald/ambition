# Content Authoring & Schema Validation

**Status:** Authoritative content-data contract. This governs materials, creatures, runes,
cultures, reactions, job templates, LLM prompt data, and any future JSON/content packs.
Use `docs/archetypal_content_catalog.md` as the seed list for reusable object archetypes once
schemas are implemented.

## 1. Purpose

The project depends on data-driven content. Content errors must fail loudly during validation,
not become runtime simulation corruption. This document defines naming, schemas, references,
migration, and validation phases.

## 2. Content principles

- Data files are declarative. They do not contain executable code.
- Every ID is stable once released; migrations rename or deprecate IDs explicitly.
- Every cross-reference validates before gameplay starts.
- Unknown fields fail validation unless a schema explicitly marks an extension point.
- Numeric units are explicit and match the owning spec.
- Content cannot override ADR invariants.

## 3. ID conventions

Use stable, namespaced StringName-friendly IDs:

| Domain | Pattern | Example |
|--------|---------|---------|
| Material | `MAT_*` | `MAT_IRON` |
| Species | `SPC_*` | `SPC_CORPSE_RAT` |
| Rune | `RUNE_*` | `RUNE_ADD_TEMPERATURE` |
| Culture | `CULT_*` | `CULT_GOBLIN` |
| Job type | `JOB_*` | `JOB_PATROL` |
| Objective | `OBJ_*` or registry enum | `RAID_FACTION` |
| Reaction | `RXN_*` | `RXN_BURNING_VOLATILE_GAS` |
| Item archetype | `ITEM_*` | `ITEM_IRON_SWORD` |
| Hazard archetype | `HAZARD_*` | `HAZARD_VOLATILE_GAS_POCKET` |

IDs are case-sensitive. Do not use display names as IDs.

## 4. Required schema domains

### Materials
Required fields:
- `material_id`
- `density_kg_per_cm3`
- `base_value`
- `innate_tags`
- `acoustic_resonance`
- `heat_capacity`
- phase thresholds where relevant (`freeze_c`, `boil_c`, `melt_c`)

Validation:
- Density and heat capacity must be positive.
- Tags must be known Chemistry tags or explicitly declared as new content tags.
- Currency content must preserve the coin = 1 value unit rule.

### Item archetypes
Required fields:
- `item_id`
- `display_name`
- `archetype_family`
- `components`
- `materialization_policy`
- `stackable`
- `merge_key`

Validation:
- `materialization_policy` must be one of the registry enum values.
- Stackable items must define a merge key.
- Containers must include ContainerComponent capacity and accept/reject filters.
- Equipped/unique/artifact items cannot use `LEDGERIZE`.
- Archetype family should match the catalog (anchor fixture, container/logistics, document,
  sensory object, crafting station, remains/evidence, route/boundary, social token). Hazards
  may be separate `HAZARD_*` content or `ITEM_*` objects with hazard behavior, but must use
  the hazard schema below if their ID is `HAZARD_*`.

### Hazard archetypes
Required fields:
- `hazard_id`
- `display_name`
- `archetype_family`
- `components`
- `materialization_policy`
- `topology_dirty_behavior`
- `sensory_emitters`
- `trigger_conditions`
- `effects`

Validation:
- `hazard_id` must use `HAZARD_*`.
- `materialization_policy` must be one of the registry enum values.
- Topology-mutating hazards must declare which dirty flags they set.
- Perception-affecting hazards must declare sight/hearing/scent behavior.
- Reaction hazards must reference known reaction IDs or Chemistry tags.

### Creature archetypes
Required fields:
- `species_id`
- `tier`
- `base_health`
- `base_stamina`
- `base_strength`
- `density`
- `structural_toughness`
- `dietary_needs`
- `loot_table`
- `default_faction_or_social_identity`
- optional `perception_defaults`

Validation:
- Tier 1 entries must specify abstract population behavior.
- Tier 2/3 entries must define enough BodyComponent data for combat math.
- Loot references must resolve to materials/items.

### Runes and spells
Required fields:
- `rune_id`
- `rune_category`
- `complexity_cost`
- `execution_logic`
- `geometric_limits`

Validation:
- Geometric limits must not exceed engine hard caps.
- Catalyst names must map to known reaction/chemistry effects.
- Absorb runes must specify quantified resources, not bare tags.

### Reactions
Required fields:
- `reaction_id`
- `tags` (two or more, normalized/sorted)
- `scope` (`INTRA` or `INTER`)
- `preconditions`
- `effects`
- `cooldown_ticks`

Validation:
- Sorted tags must normalize to one canonical key.
- Scope must define whether tags are on one entity/grid cell or overlapping entities.
- Effects must use the heat model (`energy_delta`) rather than ad-hoc temperature jumps.

### Cultures and language
Required fields:
- `culture_id`
- `behavior_modifiers`
- `language_dictionary`
- `semantic_roles`

Validation:
- Cipher data must support semantic replacement (`noun?`, `verb?`), never letter/symbol
  obfuscation as the primary mechanic.
- Behavior modifiers must reference known systems/professions/objectives.

### Job templates
Required fields:
- `objective`
- `steps`
- `preconditions`
- `target_selector`
- `profession_filters`

Validation:
- Objective must be in the registry enum.
- Job types must resolve to known JobComponents/action handlers.
- Profession filters reference ProfessionComponent values.
- Target selectors must respect Faction-0 player identity and DAG active-faction validation.

### LLM prompt templates
Required fields:
- `template_id`
- `schema_version`
- `valid_objectives`
- `required_context_sections`
- `output_schema`

Validation:
- Output schema uses `reason_summary`, not chain-of-thought-style fields.
- Valid targets are enumerated by faction id and include Faction 0 only when known/valid.
- Prompt content must not include secrets.

## 5. Validation phases

### Static validation
Runs in CI or editor tooling:
- JSON parses.
- Required fields exist.
- Unknown fields rejected unless schema permits extensions.
- Types and units match schema.
- IDs are unique.

### Cross-reference validation
Runs after all content loads:
- Materials/items/species/runes/reactions/job templates resolve references.
- Tags are registered or explicitly declared.
- Component names exist in `component_and_field_registry.md`.
- Faction/objective/profession names match registry enums/components.

### Simulation validation
Runs in targeted tests:
- Spawn every creature archetype.
- Instantiate every item archetype.
- Compile every starter rune combination marked valid.
- Execute every reaction rule in a dummy chunk.
- Expand every job template into jobs without missing handlers.

## 6. Migration and deprecation

Every content pack has a `schema_version`. When schemas change:
- Add a migration function or fail loudly.
- Keep deprecated IDs in a redirect table until old saves migrate.
- Do not silently reinterpret an old ID as a different material/species/rune.
- Saves store both schema version and content pack version.

## 7. Failure policy

Content validation failures are blockers. The game should not start a run with:
- Duplicate IDs.
- Unknown component names.
- Unknown material/species/rune references.
- Invalid materialization policies.
- Invalid reaction scopes.
- Prompt schemas missing required fields.
- Numeric values outside declared ranges.

Developer builds should show a validation report. CI should fail. Release builds should fail
to load the broken content pack and preserve existing saves.

## 8. Authoring reports

Validation should emit a compact report:
- Files loaded.
- IDs registered by domain.
- Warnings for deprecated IDs.
- Errors with file path and JSON pointer.
- Derived stats: material value range, creature tier counts, reaction count, job template
  coverage, rune category coverage.

These reports feed the observability/debugging architecture and make content review possible
without reading every JSON file manually.
