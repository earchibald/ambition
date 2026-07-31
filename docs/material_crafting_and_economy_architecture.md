Material, Crafting & Economy Architecture

Target Audience: Lead Coding Agent / Systems Architect
Context: This document defines the physical reality of items, crafting, and the economy. We reject abstract item definitions. Items are composites of Base Materials, constructed via Recipes, and governed by physical volume, thermodynamic energy, and chemical tags.

1. The Anatomy of an Item (ECS Representation)

An item is an Entity with specific components:

PhysicalPropertyComponent: mass_kg (derived cache), volume_cm3 (float), temperature (float), heat_capacity (float), phase (Enum: Solid, Liquid, Gas).

MaterialCompositionComponent: Dict of materials/percentages (e.g., {"MAT_IRON": 0.8, "MAT_WOOD": 0.2}).

ChemistryComponent: Dynamic tags (e.g., [Wet], [Coated_Poison]).

QualityComponent: Condition (Pristine, Chipped, Ruined, Scrap). Modifies baseline stats.

2. Expanded Base Material Data Dictionary

This table is the SEED material dictionary and is authoritative from Sprint 1 onward. Sprint 5
expands it with more materials; it does not re-originate these values. Every field required by
`content_authoring_and_schema_validation.md` §4 (Materials) is present, because Sprint 1's mass
derivation (registry §5) and thermodynamics (§7 below) cannot run without them.

Units: `density_kg_per_cm3` in kg/cm3. `heat_capacity` in J/(kg*K). Phase points in Celsius.
`base_value` is a scalar value-units-per-unit-mass figure (never a range — a range is not a
valid schema value). `acoustic_resonance` is 0..1 (inventory spec §1C).

| Material ID | Category | density_kg_per_cm3 | heat_capacity | melt_c | boil_c | acoustic_resonance | base_value | Innate Tags | Specific Mechanics |
|---|---|---|---|---|---|---|---|---|---|
| MAT_IRON | Metal | 0.00787 | 450 | 1538 | 2862 | 0.7 | 5 | [Conductive, Magnetic] | Rusts if [Wet] for > 1 Macro Tick. |
| MAT_COPPER | Metal | 0.00896 | 385 | 1085 | 2562 | 0.6 | 3 | [High_Conductivity, Soft] | Basic wiring / Rune circuitry. |
| MAT_TIN | Metal | 0.00729 | 227 | 232 | 2602 | 0.5 | 2 | [Low_Melting_Point] | Catalyst material. |
| MAT_SULFUR | Mineral | 0.00207 | 710 | 115 | 445 | 0.3 | 10 | [Volatile, Toxic] | Catalyst for Fire Magic. |
| MAT_SILICA | Mineral | 0.00265 | 703 | 1700 | 2230 | 0.8 | 1 | [Brittle, Transparent] | Melts into MAT_GLASS at T > 1700C. |
| MAT_GLASS | Mineral | 0.00250 | 840 | 1400 | 2230 | 0.9 | 2 | [Brittle, Transparent] | Refined MAT_SILICA. Shatters on impact. |
| MAT_CLOTH | Organic | 0.00030 | 1300 | — | — | 0.1 | 1 | [Flammable, Insulating] | Wrapping/lining; applies [Muffled]. |
| MAT_BIOMASS | Organic | 0.00106 | 3500 | — | — | 0.2 | 1 | [Rot, Edible_Scavenger] | Converts to Filth on Spoilage Timer. |
| MAT_WATER | Liquid | 0.00100 | 4186 | 0 | 100 | 0.4 | 1 | [Wet, Extinguishing] | Required for life. Universal solvent. |
| MAT_GOLD | Metal | 0.01932 | 129 | 1064 | 2856 | 0.6 | 50 | [Heavy, Noble, Soft] | Universal currency base. Does not tarnish. |

Notes:
- MAT_GLASS and MAT_CLOTH are promoted into the dictionary because the acoustic-encumbrance
  system (inventory spec §1C) and the material soundboard (ui_ux §4) already reference them by
  ID, and unknown material references are a hard content-validation blocker.
- MAT_WATER and MAT_BIOMASS carry base_value 1, not 0. A 0 base value makes
  `Price = V_base * (...) * Quality` identically 0, which would make food and water permanently
  free and silently disable the famine/scarcity economy the LLM reasons over.
- `melt_c`/`boil_c` of "—" means the material chars/decomposes rather than melting cleanly;
  phase-change logic must not fire on it.

3. Thermodynamics, States, & Fluids

Fluid Volumes: Liquids dropped create a PuddleEntity that spreads via Cellular Automata to lower elevations.

Solubility: MAT_VENOM (1 unit) + MAT_WATER (10 units) = Diluted_Poison (Applies weak [Toxic] over large area).

State Changes (Thermodynamics):

MAT_WATER + T < 0C -> Solid (Ice). Applies [Slippery].

MAT_WATER + T > 100C -> Gas (Steam). Volumetric cloud, blocks LoS.

4. The Crafting Architecture

A. Ad-hoc Combinatory Logic (In-Inventory)

Checks the ChemistryComponent of Item A and Item B.

Iron Sword + Venom_Gland = Adds [Coated_Poison] to Sword.

Filthy_Armor + Water_Flask = Cleans armor, creates Dirty_Water.

B. Station Crafting & Thermodynamics (The Supply Chain)

Stations require a HeatSourceComponent that uses the same heat model as materials.

Station: Forge ([Requires_Heat_Source])

To smelt Iron, the Forge's internal temperature must exceed Iron's melting point (1538C).

The player (or NPC [Prof_Smith]) must feed it Fuel (Coal, Wood, or Magic).

Alloys & Composites:

MAT_COPPER (70%) + MAT_TIN (30%) + Heat = MAT_BRONZE. (Bronze has higher durability than either base metal, and won't rust like Iron).

5. Dynamic Trade, Scarcity, & Currency

There are no fixed prices. Factions value items based on local utility and scarcity.

The Scarcity Math:
Let V_base be the base value, Q_local be the local quantity in faction stockpiles, and D_need be the faction's current demand (driven by LLM Objectives).


    Price = V_base * (1 + D_need / (Q_local + 1)) * Quality_Modifier

Physical Currency: We do not use abstract "Gold" in a UI counter. Gold is physical matter (MAT_GOLD).

Currency granularity (resolves review D6): the atomic coin (MAT_GOLD, quantity-stackable) is worth 1 value unit — the "base_value: 50" in the material table is the value of a unit MASS/nugget of refined gold, NOT a single coin. The barter resolver rounds a float price up to the nearest whole coin and returns change from the merchant's own coin stock; if the merchant cannot make exact change, it rounds in the buyer's favor by <1 coin. Denominations (nugget vs coin) differ only by quantity/mass, not by special-casing.

Mass source of truth (resolves review C5): mass_kg is a derived cache. Authoritative mass = volume_cm3 * sum(material_pct * density_kg_per_cm3) over MaterialCompositionComponent, using densities from the Sprint 5 material dictionary. Recompute mass whenever composition or volume changes (alloying, partial consumption, dilution). Never edit mass_kg independently.

To buy a sword, the player must physically place coins (or nuggets) whose summed coin value
meets the required price onto the Merchant's barter table. Their mass still matters for
encumbrance and physics, but payment validation sums value, not weight.

Because gold has the [Heavy] tag, carrying 10,000 gold coins will physically encumber the player, forcing them to use the Adventurer's Residence stash or hire a [Prof_Hauler] NPC to carry their wealth.

6. Entropy (Degradation & The Ecology Loop)

Wear & Tear: Weapons lose Condition based on the hardness of what they hit (striking MAT_BASALT degrades an Iron Sword rapidly).

Spoilage: MAT_BIOMASS has a timer of SPOILAGE_MACRO_TICKS = 72 (72 in-game hours = 3 in-game
days = 12 real minutes at the ADR-9 macro cadence). When it hits 0, the entity transforms into
a Filth entity. Cold slows it: the timer decrements at `max(0.25, 1.0 - (20.0 - temp_c) * 0.05)`
per macro tick, so refrigeration is a real preservation strategy.

The Cleanup: Flowing water pushes Filth into stagnant pools, breeding Tier 1 Swarms (Rats/Slimes).

7. Integrated Corrections: Thermodynamics & Reactions (ADR / Adversarial Review)

Authoritative note: governed by docs/architecture_decisions.md and the registry.

Consistent heat model (review H2): temperature is not ad-hoc. Each material has a
heat_capacity; an entity/grid-cell stores temperature and derives thermal energy as
mass_kg * heat_capacity * temperature. A fixed catalyst like Add_Temperature(1000) adds ENERGY
(joules-equivalent game units) distributed over the target's mass, so it heats a small item a
lot and a large volume little. Adjacent cells/entities conduct toward equilibrium each Micro
tick at a rate scaled by a conduction constant and contact area. Phase changes (freeze <0C,
boil >100C for water; melt points for metals) trigger on the resulting temperature. This
replaces per-tag temperature guesses with one representation.

Reaction matrix keys (review F2): reaction keys are the SORTED tag pair so "A+B" == "B+A".
Each rule declares whether it fires intra-entity (two tags on one entity) or inter-entity (two
overlapping entities, tested via SpatialHash). Reactions are data-driven rules, not a flat
hardcoded dict, and apply the [Reaction_Cooldown] anti-recursion lock (Sprint 4).

Currency & mass: see §5/§6 above — coin = 1 value unit, base_value 50 is a unit-mass value;
mass_kg is a derived cache (registry §5).
