Implementation Roadmap: Sprint 5 (Content & Data Population)

Target Audience: Lead Coding Agent / Systems Designer
Objective: Establish the scalable data frameworks for the game's content. This sprint defines the JSON schemas and GDScript dictionaries that the ECS will ingest to populate the world with materials, spells, creatures, and cultures.

Authoritative content contract: all schemas, IDs, cross-reference checks, migrations, and
failure policy must follow docs/content_authoring_and_schema_validation.md.
Use docs/archetypal_content_catalog.md for the initial pure-content object families; prioritize
its starter content set before adding bespoke legendary items or quest chains.

Step 1: The Universal Material Dictionary

The Objective: Create the master lookup table for all physical matter in the game, dictating density, value, and inherent chemistry.
Required Implementation:

Build a centralized materials_database.json or a global GDScript dictionary.

Schema Requirement: Every material MUST have:

material_id (String, e.g., "MAT_BONE")

density_kg_per_cm3 (Float)

base_value (Integer)

innate_tags (Array of Strings, e.g., ["Brittle", "Flammable"])

acoustic_resonance (Float, 0.0 to 1.0)

Goal: The coder will populate 20-30 base materials (Metals, Woods, Organics, Minerals) using this schema, allowing the ChemistryComponent to easily interpolate composite items.

Step 2: The Bestiary & Tier 1/2 Archetypes

The Objective: Define the data structures that instantiate life.
Required Implementation:

Create a creature_archetypes.json file.

Schema Requirement:

species_id (String)

tier (Integer, 1 or 2)

base_health, base_stamina (Floats)

dietary_needs (Array of Material/Tag Strings, e.g., ["MAT_BIOMASS"])

loot_table (Dictionary mapping material_id to drop probability)

default_faction_tags (Array of Strings)

Goal: Populate the base Tier 1 Swarms (Rats, Spiders, Slimes, Mites) and the core Tier 2 worker/soldier templates (Goblin, Dwarf, Spore-Drone).

Step 3: The Rune Lexicon (Magic Building Blocks)

The Objective: Define the hardcoded array of Triggers, Shapes, and Catalysts the player can use to compile spells.
Required Implementation:

Create rune_dictionary.json.

Schema Requirement:

rune_id (String)

rune_category (Enum: TRIGGER, SHAPE, CATALYST)

complexity_cost (Integer, dictates the Strain cap)

execution_logic (String matching a function name in SpellCompilerSystem)

geometric_limits (Dictionary, e.g., {"max_radius": 15, "max_speed": 50})

Goal: Implement 5 Triggers, 5 Shapes, and 10 Catalysts to provide a massive combinatory sandbox for the player's first runs.

Step 4: Cultural Tags & The Translation Cipher

The Objective: Provide the data bindings for the linguistic and behavioral rules of factions.
Required Implementation:

Culture Dictionary: Map tags like [Militaristic] to specific baseline modifiers (e.g., {"guard_ratio": 0.4, "aggression_bias": 1.2}).

Language Dictionary: Create mapping tables for the semantic translation UI.

E.g., LANG_GOBLIN: { "food": "grub", "fight": "krump", "gold": "shine" }. When the LLM
outputs "food," the UI uses the known cultural word ("grub") or semantic replacement
("noun?") based on the player's MindComponent.language_fluency. It never obfuscates text
with random letters or symbols.

Step 5: Integrated Corrections (ADR / Adversarial Review)

Authoritative note: governed by docs/architecture_decisions.md and
docs/component_and_field_registry.md. All Sprint 5 data must conform to the registry.

Material schema additions: alongside density_kg_per_cm3, base_value, innate_tags,
acoustic_resonance, add heat_capacity (float) for the thermodynamics model (material §7) and
melt/boil/freeze points where relevant. mass is derived (registry §5), never stored per item.

Bestiary schema additions: add density (float) and structural toughness so combat's kinetic
force model (Sprint 1 §10) resolves; include per-species base strength.

Rune Lexicon: geometric_limits are enforced by the SpellCompiler hard caps (max_radius 15,
max_speed). complexity_cost gates against MindComponent.insight.

Stack split/merge data (review D7): define which items are quantity-stackable and their
merge key (material_id + quality + tags). Currency: coin = 1 value unit (material §5/§6).

Materialization policy data (review 2026-07-31 A3): item/archetype schemas must declare
whether the item is a fungible commodity stack (LEDGERIZE), equipped/unique identity item
(PRESERVE_ENTITY), container/stash manifest (CONTAINER_MANIFEST), caravan cargo
(CARAVAN_MANIFEST), or cleanup-eligible junk (GC_ELIGIBLE). LoD sync uses this field instead
of flattening all owned matter into ledgers.

Container data: container archetypes declare capacity_cm3, accept/reject tag filters, and
allow_nested_container. Sub-container sorting uses ContainerComponent filters directly.

Language/Culture dictionaries feed the SEMANTIC cipher (unknown word -> grammatical function),
never symbol/letter obfuscation (ui_ux §8).
