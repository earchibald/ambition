Material, Crafting & Economy Architecture

Target Audience: Lead Coding Agent / Systems Architect
Context: This document defines the physical reality of items, crafting, and the economy. We reject abstract item definitions. Items are composites of Base Materials, constructed via Recipes, and governed by physical volume, thermodynamic energy, and chemical tags.

1. The Anatomy of an Item (ECS Representation)

An item is an Entity with specific components:

PhysicalPropertyComponent: mass_kg (float), volume_cm3 (float), temperature (float), phase (Enum: Solid, Liquid, Gas).

MaterialCompositionComponent: Dict of materials/percentages (e.g., {"MAT_IRON": 0.8, "MAT_WOOD": 0.2}).

ChemistryComponent: Dynamic tags (e.g., [Wet], [Coated_Poison]).

QualityComponent: Condition (Pristine, Chipped, Ruined, Scrap). Modifies baseline stats.

2. Expanded Base Material Data Dictionary

Material ID

Category

Innate Tags

Base Value

Specific Mechanics

MAT_IRON

Metal

[Conductive, Magnetic]

5

Rusts if [Wet] for > 1 Macro Tick.

MAT_COPPER

Metal

[High_Conductivity, Soft]

3

Used for basic wiring/Rune circuitry.

MAT_TIN

Metal

[Low_Melting_Point]

2

Catalyst material.

MAT_SULFUR

Mineral

[Volatile, Toxic]

10

Catalyst for Fire Magic.

MAT_SILICA

Mineral

[Brittle, Transparent]

1

Melts into Glass at T > 1700C.

MAT_BIOMASS

Organic

[Rot, Edible_Scavenger]

0

Converts to Filth on Spoilage Timer.

MAT_WATER

Liquid

[Wet, Extinguishing]

0-10

Required for life. Acts as universal solvent.

MAT_GOLD

Metal

[Heavy, Noble, Soft]

50

Universal currency base. Does not tarnish.

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

Stations require an EnergyComponent (Heat).

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

To buy a sword, the player must physically place coins (or nuggets) totaling the weight of the required value onto the Merchant's barter table.

Because gold has the [Heavy] tag, carrying 10,000 gold coins will physically encumber the player, forcing them to use the Adventurer's Residence stash or hire a [Prof_Hauler] NPC to carry their wealth.

6. Entropy (Degradation & The Ecology Loop)

Wear & Tear: Weapons lose Condition based on the hardness of what they hit (striking MAT_BASALT degrades an Iron Sword rapidly).

Spoilage: MAT_BIOMASS has a timer. When it hits 0, it transforms into a Filth entity.

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
