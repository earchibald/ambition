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

CORRECTED (2026-07-31). The formula above has a **hard floor at V_base**: with D=5, Q=10,000 the
multiplier is 1.0005, so a faction drowning in iron still pays full price. There is therefore no
surplus discount, no price gradient, and nothing to drive the trade-route behaviour the factions
doc depends on. `D_need` also had no unit, no range, and no update rule (D=1000, Q=0 gives
1001x base), and `Quality_Modifier` had no values. Canonical replacement:

    D_need in [0, 10], recomputed per Macro tick from the faction's objective target stock
    const SCARCITY_MAX: float = 4.0     # hard clamp on the multiplier
    const GLUT_FLOOR: float = 0.25      # price CAN fall to 25% of base
    const GLUT_REF: float = 200.0
    const BID_ASK_SPREAD: float = 0.20  # merchant buys at 0.8x, sells at 1.0x
    QUALITY_MOD = { PRISTINE: 1.0, CHIPPED: 0.65, RUINED: 0.30, SCRAP: 0.10 }

    multiplier = clamp(1.0 + D_need / (Q_local + 1.0) - Q_local / (Q_local + GLUT_REF),
                       GLUT_FLOOR, SCARCITY_MAX)
    Price = V_base * multiplier * QUALITY_MOD[condition]

Verification: Q=10,000/D=0 -> clamped to 0.25 -> price 2.5 vs base 10 (a real glut discount).
Q=0/D=10 -> clamped to 4.0 -> price 40 (bounded). Q=9/D=5/PRISTINE -> 1.457 -> 14.6, which
matches the Day-0 walkthrough's intended 15. NOTE: that walkthrough's arithmetic as written
(`1 + D/Q + 1`) has a minimum of 2, so its stated result of 15 was impossible; it needed
`D/(Q+1) = 0.5`.

Merchants hold a FINITE per-shop coin stock, replenished on the Macro tick from the faction
ledger. Without it, mined material converts to gold without bound at >= base value.

GOLD SUPPLY SINK (required). GrayBoxSystem adds +50 MAT_GOLD per Macro tick = 1 in-game hour =
10 real seconds (ADR-9), i.e. 18,000 gold/real-hour/faction and 432,000/real-hour across the
ADR-12 cap of 24 factions. The only sink is the 40% interregnum entropy tax, applied once per
player death, giving a steady state of ~648,000 gold per faction. Scale injection with
`abstract_population` and add a per-Macro-tick consumption sink so ledgers reach steady state
without depending on the player dying.

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
heat_capacity (see the §2 table); an entity/grid-cell stores temperature and derives thermal
energy from it. Phase changes trigger on the resulting temperature. This replaces per-tag
temperature guesses with one representation.

CORRECTED 2026-07-31 — three defects in the original model:

**(a) CONDUCTION NEEDS A STABILITY BOUND AND A CLAMP.** "Conduct toward equilibrium at a rate
scaled by a conduction constant" gave no constant and no bound. For `T_i += K*dt*sum(T_n - T_i)`
at dt = 1/60, stability needs `K <= 1/(N*dt)` = 15 for N=4, and monotone convergence needs
K <= 7.5. Measured over 8 ticks on a 100C/0C pair: K=3 converges (71.5/28.5); K=15 converges
(50.2/49.8); **K=60 becomes a perfect 2-cycle (100.0/0.0 forever)** — which looks stable because
energy is conserved, while the cell flickers ICE<->LIQUID<->GAS 30 times a second, spawning and
destroying steam every frame; **K=150 reaches +3,276,850 / -3,276,750 C in 0.13 s.**

    const CONDUCTION_K: float = 3.0    # game-feel; MUST satisfy K <= 1/(4*dt) = 15
    # per adjacent pair, once per pair per tick:
    C_a = mass_a * heat_capacity_a ; C_b = mass_b * heat_capacity_b
    T_eq = (C_a * T_a + C_b * T_b) / (C_a + C_b)
    dE = CONDUCTION_K * contact_area_m2 * (T_a - T_b) * dt
    dE = clamp(dE, -abs(C_b * (T_eq - T_b)), abs(C_a * (T_a - T_eq)))   # cannot overshoot
    T_a -= dE / C_a ; T_b += dE / C_b

The equilibrium clamp makes overshoot impossible for ANY K, so a mis-tuned constant merely slows
convergence instead of exploding. Note `CONDUCTION_K` is necessarily a game-feel number: stone's
real diffusivity gives an equilibration time of ~231 hours at 1 m tiles, i.e. no observable
transfer at all.

**(b) ENERGY APPLIES TO SURFACE MASS, NOT TOTAL MASS.** Distributing `Add_Temperature(1000)`
over an entity's whole mass gives absurd results: it raises an iron sword by **+1,485C** (melting
it) and a human by **+4.1C** (unharmed), and makes a rat 175x more flammable than a human. A
fireball is a surface effect.

    const SURFACE_DEPTH_CM: float = 0.5
    heated_mass = min(mass_kg, SURFACE_DEPTH_CM * exposed_area_cm2 * density_kg_per_cm3)

Verification: a human presenting ~4,500 cm2 to the blast heats 2.36 kg -> **+121C**, i.e. severe
burns. The sword at 200 cm2 heats 0.79 kg -> partial melt. A stone wall at 10,000 cm2 heats
12.6 kg -> +94C, scorched rather than inert.

**(c) PHASE CHANGE NEEDS LATENT HEAT, AND THE STATE VARIABLE IS ENTHALPY.** As written, a cell's
bulk temperature crossing 100C flips the WHOLE cell to GAS, so 1,000 kg of water at 99.9C
flash-boils on receiving 1 kJ (it should boil 0.44 kg). Also `E = m*c*T` with T in Celsius yields
negative energy below 0C and melts ice with no latent barrier. Store **enthalpy H (joules)** and
derive temperature and phase fraction from it:

    # material schema gains: latent_fusion_kj_kg, latent_vapor_kj_kg
    T = f(H, mass, heat_capacity, latent_fusion, latent_vapor)
    phase_fraction = (H - H_phase_start) / (mass * L)

Water's L_vap is 2,257 kJ/kg and iron needs 370 kJ of L_fus to melt a 1.5 kg sword after reaching
1538C. Without these, phase changes are free and total.

Reaction matrix keys (review F2): reaction keys are the SORTED tag pair so "A+B" == "B+A".
Each rule declares whether it fires intra-entity (two tags on one entity) or inter-entity (two
overlapping entities, tested via SpatialHash). Reactions are data-driven rules, not a flat
hardcoded dict, and apply the [Reaction_Cooldown] anti-recursion lock (Sprint 4).

Currency & mass: see §5/§6 above — coin = 1 value unit, base_value 50 is a unit-mass value;
mass_kg is a derived cache (registry §5).
