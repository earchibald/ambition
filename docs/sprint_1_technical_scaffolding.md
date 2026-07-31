Sprint 1 Technical Scaffolding

Target Audience: Lead Coding Agent
Context: This document provides the concrete code structures, data types, and required algorithms to implement sprint_1_implementation_roadmap.md. It includes specific remediations to ensure safe handoffs, strictly asynchronous pathfinding, and fixes for omniscient AI behavior. Rule Zero: Do not use Godot Physics Nodes (CharacterBody3D/RigidBody3D) for ECS entities.

AUTHORITATIVE CORRECTIONS (ADR — read before coding Sprint 1):
- chunk_id is Vector3i(x, y, floor) per ADR-3 (NOT int). PositionComponent below is updated.
- Simulation Tick is 2Hz (SIM_TICK_RATE = 0.5), not 1Hz, per ADR-9.
- A minimal GameClock (time-of-day, advanced by the Macro/Sim tick) is pulled into Sprint 1
  because ScheduleComponent (Step 5) needs it; see the appended Section 8.
- ECS-owned spatial index + collision + picking are REQUIRED Sprint 1 systems (ADR-2), since
  movement, melee targeting, interaction, and the Tactical Lens all need spatial queries and
  wall collision without physics nodes. See appended Section 9. NavigationServer3D is a
  sanctioned Active-only steering exception (ADR-2).
- Combat math needs a strength attribute and a defined force unit; BodyComponent gains
  `strength: float` and creatures carry `density` (see appended Section 10 and Sprint 5).
- Entity handles are generational and destroy is atomic across all registries (ADR-7).
- enum types (phase, LoD state) are GDScript enums, not strings (ADR-13).

1. The Main Game Loop (The Master Clock)

The ECS does not magically run itself. A central Godot Node (e.g., an Autoload named GameLoopManager) must drive the ticks using Godot's engine timing.

# GameLoopManager.gd (Autoload)
var sim_tick_timer: float = 0.0
const SIM_TICK_RATE: float = 0.5 # 2 Hz (ADR-9)
var macro_tick_timer: float = 0.0
const MACRO_TICK_RATE: float = 10.0 # 1 in-game hour every 10 real seconds (ADR-9)

func _physics_process(delta: float):
    # 1. Drive the Micro Tick (60Hz): movement integrate -> collision resolve -> spatial hash
    ECSManager.process_micro_tick(delta)
    
    # 2. Drive the Simulation Tick (2Hz)
    sim_tick_timer += delta
    if sim_tick_timer >= SIM_TICK_RATE:
        ECSManager.process_sim_tick()
        sim_tick_timer -= SIM_TICK_RATE
    
    # 3. Drive the Macro Tick (advances the GameClock by 1 in-game hour; see Section 8)
    macro_tick_timer += delta
    if macro_tick_timer >= MACRO_TICK_RATE:
        ECSManager.process_macro_tick()
        macro_tick_timer -= MACRO_TICK_RATE




2. The Core ECS Implementation (Godot-Native)

Use RefCounted or Resource for pure data classes. Do not inherit from Node.

# ecs_components.gd
class PositionComponent extends RefCounted:
    var floor_id: int
    var chunk_id: Vector3i # (x, y, floor) per ADR-3
    var exact_pos: Vector3
    var velocity: Vector3 = Vector3.ZERO # Explicitly required for ActionResolution physics math
    var current_node_id: int = -1 # abstract-graph node when Simulated
    var current_edge: int = -1
    var edge_progress: float = 0.0
    var edge_speed: float = 0.0

class PhysicalPropertyComponent extends RefCounted:
    var quantity: int = 1 # Mandatory for stacking (e.g. 10,000 gold coins as 1 entity)
    var mass_kg: float
    var volume_cm3: float
    var temperature: float = 20.0
    var heat_capacity: float = 1.0
    var phase: Phase = Phase.SOLID

class BodyComponent extends RefCounted:
    var max_health: float = 100.0
    var health: float = 100.0
    var stamina: float = 100.0
    var strength: float = 10.0
    var exposure: Dictionary = {}

class PerceptionComponent extends RefCounted:
    var sight_range_m: float = 20.0
    var fov_degrees: float = 110.0
    var hearing_sensitivity: float = 1.0
    var awareness_state: AwarenessState = AwarenessState.UNAWARE
    var last_known_targets: Dictionary = {} # { EntityHandle: Vector3 }

class NeedsComponent extends RefCounted:
    var hunger: float = 0.0
    var energy: float = 100.0




The Registry Structure

# ECSManager.gd (Autoload)
var generations: PackedInt32Array = PackedInt32Array()
var free_indices: Array[int] = []
var active_entities: Array[EntityHandle] = []

# Component Registries (Sparse Sets via Godot Dictionaries)
var positions: Dictionary = {} # { EntityHandle: PositionComponent }
var physicals: Dictionary = {} 
var needs: Dictionary = {}




3. The Godot/ECS Event Bus (The Bridge)

The global event bus (ECSEvents.gd Autoload) communicates state changes.

signal entity_created(entity: EntityHandle, tags: Array[StringName], initial_pos: Vector3)
signal entity_destroyed(entity: EntityHandle)
signal entity_moved(entity: EntityHandle, new_pos: Vector3)
signal chunk_state_changed(chunk_id: Vector3i, is_active: bool)




The ViewManager (The "Dumb" Viewer)

# ViewManager.gd
var visual_dictionary: Dictionary = {} # { EntityHandle: Node3D }

func _on_entity_created(entity: EntityHandle, tags: Array[StringName], pos: Vector3):
    # Instantiate a purely visual Node3D based on tags. 
    # NO PHYSICS NODES (No CollisionShape3D / RigidBody3D).
    
func _process(delta):
    # Interpolate visual positions based on ECS exact_pos for smooth rendering
    for entity in visual_dictionary:
        var node = visual_dictionary[entity]
        var target_pos = ECSManager.positions[entity].exact_pos
        node.global_position = node.global_position.lerp(target_pos, delta * 15.0)



4. Input & Action Intents (Bridging Player Control)

Player input does not move the player. It generates data structs that the ECS processes.

# ActionIntent Struct
class ActionIntent extends RefCounted:
    var type: StringName # e.g., &"MOVE", &"MELEE", &"DROP"
    var target: EntityHandle = EntityHandle.invalid()
    var vector_data: Vector3 = Vector3.ZERO

# ECSManager Data Additions:
var action_queues: Dictionary = {} # { EntityHandle: Array[ActionIntent] }



When Godot reads Input.get_vector(), it pushes an ActionIntent (type=&"MOVE", vector_data=Input Vector) to Entity 0's action_queue. The ECS Micro Tick pops this queue and applies it to Entity 0's velocity.

5. Cellular Automata (Fluid Dynamics) — CORRECTED ALGORITHM

The fluid grid lives on `ChunkData` (registry §6), not on a `FluidGridComponent`. Chunks are
not entities. Canonical: 2D grid per chunk plus a `height_map` (ADR-3). Never a 3D voxel volume.

CRITICAL — DO NOT DOUBLE-BUFFER. The previous design paired a `next_volume_map` write buffer
with a sparse dirty-cell set. Those two mechanisms are mutually exclusive: double buffering
requires writing EVERY cell each tick, while a sparse set writes only the dirty subset. After
the swap, every non-dirty cell reads two-tick-old data — so **every settled puddle in the world
is annihilated on the first tick it stops being dirty**. Worked example:

    vol = [5,0,100,0,0]  nxt = [0,0,0,0,0]   # cell 2 is a settled 100-unit puddle, not dirty
    write only dirty cells 0,1 ->  nxt = [3,2,0,0,0]
    swap                        ->  vol = [3,2,0,0,0]   # the 100 units are simply gone

Use ONE `volume_map` plus a sparse delta accumulator and a touched list. This is
order-independent (what double buffering was for), exactly conservative, and touches only
dirty cells:

    # phase 1: read volume_map, write only into delta
    for idx in dirty_cells:
        ... delta[j] += f ; delta[idx] -= f ; touched.append(j) ; touched.append(idx)
    # phase 2: single commit pass
    for t in touched:
        volume_map[t] += delta[t] ; delta[t] = 0

FLOW RULE (was entirely unspecified; the natural integer rule oscillates forever and leaks mass):

    const CA_UNIT_CM3: int = 1000          # 1 grid unit = 1 litre. Tile = 1 m^2 (ADR-18).
    const MAX_CELL_VOLUME: int = 1000      # 1000 units = 1 m depth
    const FLOW_MIN_DIFF: int = 2           # integer hysteresis — REQUIRED for termination
    const FLOOD_PUMP_UNITS_PER_TICK: int = 50

    # flow only downhill in (height + volume) terms
    d = (volume[idx] + height_units[idx]) - (volume[j] + height_units[j])
    if d < FLOW_MIN_DIFF: continue         # below hysteresis -> no flow
    f = d >> 1                             # FLOOR division; never rounds up
    delta[j] += f ; delta[idx] -= f        # exactly conservative by construction
    # a cell with no qualifying neighbour is NOT re-marked, so it LEAVES the dirty set

Why the hysteresis is mandatory: with A=1, B=0 at equal elevation and a plain "push to the
lower neighbour" rule, the grid enters a permanent 2-cycle (A=0,B=1 -> A=1,B=0 -> ...). Both
cells stay dirty forever, so every puddle edge in the world becomes a permanent budget
consumer. `FLOW_MIN_DIFF = 2` with floor division makes the total absolute deviation strictly
decrease, so equilibrium is provably reached and the dirty set drains.
Integer conservation: distributing V=7 over 4 neighbours must use `share = V/4 = 1` and leave
`V - 4*share = 3` at the source. Rounding up fabricates matter (1.2M units/second at budget);
zeroing the source destroys it.

GHOST-CELL APRON (REQUIRED). The grids are flat arrays, so a naive `idx+1` neighbour probe
wraps rows and runs out of range:

    x=63,y=0  -> idx 63   ; idx+1 = 64   -> that is x=0,y=1 (wrapped to the far side)
    x=63,y=63 -> idx 4095 ; idx+1 = 4096 -> OUT OF RANGE

Store a 1-cell apron: 66x66 with `STRIDE = 66`, index `(y+1)*STRIDE + (x+1)`. All four
neighbours of every real cell are then always in range. Each tick, copy the four edge strips
from neighbouring chunks' real cells into the apron (4 x 64 ints per chunk, ~0.05 ms for the
9-chunk Active set). Flow into an apron cell commits to the neighbour's real cell if that
neighbour is Active, or accumulates into its `volume_pools` otherwise. Collision and LoS DDA
use an explicit `world_tile(chunk_id, wx, wy)` accessor that resolves across chunk seams and
treats unloaded chunks as SOLID.

BUDGET CORRECTION (ADR-10 was measured and is wrong for GDScript). Measured on Godot 4.7.1,
realistic kernel (dirty set + delta accumulator + heightmap gate): **0.364 us per cell-update**
on an M5 Max, ~0.655 us on the ADR-10 M1 reference. So 20,000 updates = **7.3 ms / 13.1 ms** —
91% of the entire 8 ms Micro budget on a fast machine and 164% of it on the reference machine,
before collision, perception, or anything else runs.
Canonical resolution: fluids run on their own **15 Hz** cadence (every 4th Micro tick), with
`CA_UPDATES_PER_FLUID_TICK = 12000`, giving ~1.3 ms amortized per frame on M1. The 20,000-per-
Micro-tick figure is retained only as the post-GDExtension target (ADR-10's Rust escape hatch),
not as a GDScript budget. Note for context: a full `PackedInt32Array(4096).duplicate()` costs
only 0.236 us, so copying was never the thing worth optimizing.

LoD TRANSFER MUST BE TRANSACTIONAL (mirrors the Sprint 2 wealth fix). Harvest the grid back
into `volume_pools` on demotion and zero it; guard promotion with a `fluid_materialized` flag
and zero the pool when spawning FloodSources. Without both, ten boundary crossings create ten
copies of the pool while destroying everything in the grid — the exact dupe the wealth ledger
already closed. Handle EVERY material in `volume_pools`, not just MAT_WATER.



6. Pathfinding Ownership (STRICTLY ASYNCHRONOUS HANDSHAKE)

Mandatory Patch: The main thread will freeze if chunks shift to Active and 50 entities request paths synchronously.

ECS System: Emits request_path(entity: EntityHandle, start_pos, target_pos). Entity enters Idle_Waiting_For_Path state.

NavBridge (Godot): Queues the requests. Processes max N (e.g., 5) per frame.

NavigationServer3D IS OUT OF SPRINT 1 SCOPE. It moves to Sprint 2. Reasons, verified against
4.7.1:
- Its bake path consumes mesh instances or static colliders. Sprint 1 has no chunk meshes, and
  colliders are banned by the Prime Directive. The only legal route is hand-feeding
  `NavigationMeshSourceGeometryData3D.add_faces()` from tiles — strictly more work than the
  grid A* it is supposed to accelerate.
- NavigationServer3D maps sync on physics frames. Under GUT (a `SceneTree` with no physics
  steps) queries return empty paths, so the Sprint 1 gate cannot test it.

Sprint 1 therefore ships NavBridge over ECS grid A* on `tile_map` ONLY. The asynchronous
contract is unchanged and is the part that matters: queue path requests, process a bounded
number per frame (N = 5), and never burst synchronously.

For Sprint 2, the verified 4.7.1 API shapes are:
- `NavigationServer3D.query_path(parameters: NavigationPathQueryParameters3D,
  result: NavigationPathQueryResult3D, callback: Callable)` — the correct async query shape.
- `NavigationServer3D.map_get_path(map, origin, destination, optimize, navigation_layers)` —
  the synchronous burst to avoid.
- `bake_from_source_geometry_data_async(navigation_mesh, source_geometry_data, callback)` —
  async bake. `region_bake_navigation_mesh` is synchronous.

Godot to ECS: Emits path_calculated(entity: EntityHandle, path_array). Entity shifts to Moving state.

7. Sprint 1 AI: Utility Evaluation Math & The Acoustic Fix

Run this during the Simulation Tick for entities with a NeedsComponent and ScheduleComponent.

SIGN CONVENTIONS (were undefined; both directions appeared in different docs):
- `hunger` RISES 0 -> 100. 100 = starving. MetabolismSystem INCREASES it.
- `energy` FALLS 100 -> 0. 0 = exhausted. MetabolismSystem DECREASES it.
- `morale` FALLS 100 -> 0.
Rates (per Simulation tick, 2Hz): `hunger += 0.05` (=> ~17 real minutes 0->100),
`energy -= 0.03`. MetabolismSystem ALSO owns `BodyComponent.stamina` drain, including the
cold-exposure term in the_first_hour Phase 4; stamina is not a separate system's concern.

HYSTERESIS is required. Without it an entity flips between Eat and Work every tick once it
sits exactly on a threshold. Each interrupt has an enter threshold and a lower exit threshold,
and a chosen action is held until its exit threshold is crossed.

# Pseudo-code inside JobResolutionSystem
const HUNGER_ENTER := 80.0
const HUNGER_EXIT := 30.0
const ENERGY_ENTER := 20.0   # energy BELOW this triggers sleep
const ENERGY_EXIT := 80.0

func evaluate_needs(handle: int, current: StringName) -> StringName:
    var needs = ECSManager.needs[handle]

    # Sustain an in-progress interrupt until its exit threshold (anti-thrash).
    if current == &"ActionIntent_Consume" and needs.hunger > HUNGER_EXIT:
        return current
    if current == &"ActionIntent_Sleep" and needs.energy < ENERGY_EXIT:
        return current

    if needs.hunger >= HUNGER_ENTER:
        return &"ActionIntent_Consume"
    elif needs.energy <= ENERGY_ENTER:
        return &"ActionIntent_Sleep"
    else:
        return &"ActionIntent_Work" # Fallback to the ScheduleComponent block

Note: the roadmap's "hunger > 80" and this threshold are now the SAME number (80). The old
`(hunger/100)*2.0 > 1.5` weighting fired at 75 and contradicted the roadmap.



The Omniscient Combat Fix (Acoustic Injection)

When ActionResolutionSystem resolves a projectile hitting a target (e.g., Arrow hits Goblin):

DO NOT instantly assign Job_Combat(Target=Player).

DO spawn an [Ephemeral_Noise_Entity] at the point of impact.

If the Goblin's PerceptionComponent does not currently perceive the player via sight cone +
DDA line of sight, its AI parses the noise entity and assigns Job_Investigate(Impact_Location)
instead of omniscient Job_Combat(Target=Player).

8. The GameClock (pulled into Sprint 1 — ADR-9)

ScheduleComponent needs a time-of-day source. Introduce a minimal clock now.

# GameClock.gd (in ECSManager or its own service)
var hour: int = 6   # Day 0 starts at 06:00
var day: int = 1
var season: int = 0 # 0..3
# Advanced once per Macro tick (1 hour). 24 hours -> +1 day; 90 days -> +1 season.
func advance_hour():
    hour += 1
    if hour >= 24:
        hour = 0
        day += 1

ScheduleComponent maps hour ranges to states (Sleep 22-06, Work 06-18, Leisure 18-22).
The Sim-tick utility evaluator reads GameClock.hour to pick the active schedule block.

9. ECS Spatial Index, Collision & Picking (REQUIRED Sprint 1 — ADR-2)

These replace move_and_slide / Area3D / physics raycasts. Godot stays a dumb viewer.

CONSTANTS (none of these existed; collision cannot be written without them):

    const SPATIAL_CELL_M: float = 2.0      # >= 2x max entity extent; a melee r=2 query hits 3x3
    const MIN_ENTITY_EXTENT: float = 0.25
    const SUBSTEP_MAX_M: float = 0.125     # = 0.5 * MIN_ENTITY_EXTENT
    const STEP_UP_MAX_M: float = 0.5
    const AUTO_DROP_MAX_M: float = 1.0     # beyond this it becomes a fall
    const GRAVITY_MPS2: float = 9.81
    const SLIDE_EPSILON_M: float = 0.001   # push-out after depenetration
Entity extents come from `BoundsComponent.half_extents` (ADR-18). Measured note: a full
SpatialHash rebuild for 1,500 entities costs 0.188 ms (M5 Max) / 0.34 ms (M1) = ~4% of the
Micro budget. Rebuild-every-tick is fine up to ~6,000 entities. Do NOT optimize this.

# SpatialHash.gd (per Active chunk, rebuilt each Micro tick). Handles are ints (ADR-19).
var cells: Dictionary = {} # { Vector2i(cell_x, cell_z): PackedInt64Array }
func query_radius(pos: Vector3, r: float) -> PackedInt64Array: ...  # melee/AoE/proximity
# query_ray MUST return distance, normal, and the tile — PickSystem needs "entity OR tile",
# and the old `-> EntityHandle` signature could not express a tile hit or a nearest-hit test.
func query_ray(origin: Vector3, dir: Vector3, max_dist: float) -> Dictionary: ...
    # -> { entity: int, tile: Vector2i, t: float, normal: Vector3 }
    # Tests EVERY entity in each marched cell for nearest ray-AABB intersection.
    # Does NOT return the first cell occupant found.

# CollisionResolveSystem (Micro tick, AFTER velocity integration)
# For each active mover: integrate desired exact_pos += velocity*delta, then sweep its AABB
# via grid-DDA against chunk.tile_map solid cells. 2.5D uses the per-tile heightmap. No
# physics nodes. Loose solid items (dropped/thrown/scattered, incl. backpack rupture) use the
# SAME integrator + grid collision with sleep-on-rest (resolves review B4/D7).
#
# REQUIRED RULES that were missing entirely:
# (a) SUBSTEPPING — prevents tunneling. substeps = ceil(|v|*delta / SUBSTEP_MAX_M).
#     A projectile at the Sprint 5 cap of 50 m/s moves 0.833 m per Micro tick, which is more
#     than a rat's whole AABB, so without substeps it passes straight through. 50 m/s needs 7.
# (b) ENTITY-vs-ENTITY COLLISION — previously specified NOWHERE. Only entity-vs-tile sweeps and
#     radius queries existed, so no projectile could ever hit anything. After the tile sweep,
#     query the spatial hash over the swept AABB's cell footprint and run conservative
#     advancement against each candidate AABB, taking the smallest t.
# (c) AXIS ORDER — resolve the LARGER |v| component first, re-test, then the second, then a
#     final depenetration pass with SLIDE_EPSILON_M. Resolving X and Z independently in one
#     pass makes a 0.4 m half-extent mover either stick or penetrate in a 1.0 m corridor.
# (d) DIAGONAL GAPS — with (1,0) and (0,1) solid but (0,0) and (1,1) open, an axis-separated
#     resolve lets an AABB slip through the shared vertex. Explicitly forbid the diagonal move.
# (e) CHUNK SEAMS — use the world_tile(chunk_id, wx, wy) accessor (see §5 apron), never raw
#     idx+1 arithmetic, which wraps rows and runs off the end of the array.

# PickSystem (used by input + Tactical Lens): project a camera ray in pure math, march it
# through the SpatialHash + tile_map (DDA), return the hit entity_id / tile. The camera is a
# viewer node; the ray math is ECS/bridge-side.

# NavigationServer3D: SANCTIONED EXCEPTION for Active-chunk local steering only (baked per
# Active chunk, owns no state); fall back to tile_map grid A* if a region isn't baked.
# Simulated/Abstracted movement uses the ECS-owned AbstractGraph (see ECS spec Section 7).

10. Combat Math — CORRECTED (kinetic energy model)

The previous model was `impact_force = |velocity| * (weapon_mass_kg + strength)` with a kill at
`mass_kg * density * TOUGHNESS_CONST`. It is discarded. It failed five ways:

1. m/s x kg is MOMENTUM, not force. The spec called it "Newtons-equivalent"; it is not.
2. It added dimensionless `strength` to kilograms. At baseline a 1.5 kg sword contributed 13%
   and strength 87%, so swapping a dagger for a warhammer barely mattered.
3. `mass_kg * density` double-counts density, because registry §5 already derives mass as
   `volume * density`. The threshold was really `volume * density^2`.
4. `|velocity|` was the attacker's BODY velocity, so a stationary player dealt exactly ZERO —
   making Step 6's own success state unreachable — while strafing dealt full damage.
5. It was a boolean kill test with no bridge to `BodyComponent.health`, which both roadmaps
   nonetheless describe as reaching 0.
Worked consequences at TOUGHNESS_CONST = 400: every unarmoured human is one-shot by any 3 m/s
swing, and a 200 L water barrel is 1.6x tougher than a plate-armoured knight. The valid band
for the constant was 277 < K < 82,143, i.e. it constrained nothing.

CANONICAL MODEL — kinetic energy in joules, with toughness scaled by cross-section:

    const STRENGTH_REF: float = 10.0
    const BASE_SWING_MPS: float = 5.0
    const ARM_MASS_FRAC: float = 0.10
    const J_PER_HP: float = 3.0
    const TOUGHNESS_J: float = 120.0     # joules per kg^(2/3)
    const SAFE_FALL_MPS: float = 5.0

    v_swing  = BASE_SWING_MPS * sqrt(strength / STRENGTH_REF) * (1.0 + 0.5 * skill / 100.0)
    v_swing += clamp(body_velocity.dot(swing_dir), 0.0, 0.5 * v_swing)   # capped charge bonus
    m_eff    = weapon_mass_kg + ARM_MASS_FRAC * wielder_mass_kg
    E        = 0.5 * m_eff * v_swing * v_swing                           # joules
    absorb   = clamp(armor_rating / (armor_rating + E), 0.0, 0.95)
    E_eff    = E * (1.0 - absorb)
    damage_hp = E_eff / J_PER_HP
    gib_threshold_J = TOUGHNESS_J * pow(target.mass_kg, 2.0 / 3.0) * material_toughness_mult
    # instant kill (dismember/gib) if E_eff > gib_threshold_J

Verification with real numbers (1.5 kg sword, 70 kg wielder, strength 10 -> m_eff 8.5 kg,
v_swing 5 m/s -> E = 106 J):
- Corpse-rat, 0.4 kg: gib threshold 120 * 0.4^(2/3) = 65 J. 106 > 65 -> one-shot. CORRECT.
- Human, 70 kg: threshold 2,040 J -> not one-shot; takes 106/3 = 35 hp, so three hits. CORRECT.
- Armoured knight (mult 2.5, armor_rating 300): threshold 5,100 J; absorb cuts E_eff to 27 J
  = 9 hp, about eleven hits. CORRECT.
- 500 kg boulder at 20 m/s = 100 kJ -> gibs anything. CORRECT.
- Stationary player still delivers the full 106 J. CORRECT (the old model gave 0).
Only TOUGHNESS_J and J_PER_HP need tuning, and both have physical meaning.

`structural_toughness` in the creature schema (content_authoring §4) supplies
`material_toughness_mult`. There is no `TOUGHNESS_CONST` and no `density` term in combat.
Fall damage reuses the same model: `E = 0.5 * mass_kg * v_impact^2` above SAFE_FALL_MPS.
Targeting uses PickSystem.query_ray (Section 9), NOT a Godot raycast.

11. Perception, Hearing, and Witness Events (REQUIRED Sprint 1)

Perception is the shared primitive for combat fairness, stealth, crime, and alerts.

COST BUDGET (measured — the naive design does not fit). A DDA LoS march (<=20 steps) costs
1.538 us measured on an M5 Max, ~2.77 us on the ADR-10 M1 reference. At the ADR-10 target of
1,500 active entities and `sight_range_m = 20`, every observer has ~16 post-FOV candidates =
23,436 marches per Simulation tick = **65 ms on M1, in a single frame, twice per second** (a
4-frame hitch). At the 3,000 hard cap it is 260 ms. The Simulation tick is one synchronous call,
so this is unshippable as specified. Required mitigations, all four:

    const PERCEPTION_MARCH_BUDGET: int = 1200      # LoS marches per Simulation tick
    const MAX_CANDIDATES_PER_OBSERVER: int = 8     # nearest-first, so real threats win
    const SIGHT_RANGE_DEFAULT_M: float = 12.0      # down from 20; cost ~ r^3 -> 0.216x

1. TIER BY AWARENESS. COMBAT/INVESTIGATING observers re-evaluate every Sim tick; SUSPICIOUS
   every 5th; UNAWARE every 20th, round-robin over a rotating cursor. An unaware NPC does not
   need 2 Hz threat detection.
2. CACHE PAIRWISE LoS within a tick, keyed on the sorted handle pair. Tile occlusion is
   symmetric, so LoS(A,B) == LoS(B,A). This halves cost in clustered scenes — the worst case.
3. COARSE PRE-REJECT. Per chunk, keep an 8x8 sector-to-sector visibility bitset, rebuilt on
   `topology_dirty`. Most pairs die in one bit test with no march.
4. AMORTIZE. Run perception as a fixed slice of each Micro tick from a persistent work queue,
   never as one synchronous Simulation-tick burst.
Combined: ~1,000 marches/Sim tick = 2.8 ms/Sim tick on M1 = **0.09 ms/frame amortized**.

# PerceptionSystem.gd (amortized over Micro ticks; scheduled by Simulation tick)
# Sight: query candidates from SpatialHash, test FOV + range, then DDA line-of-sight through
# chunk.tile_map. Steam/smoke/solid tiles block or attenuate visibility.

HEARING MODEL (was "applies wall/material attenuation" with no formula, no falloff, no
threshold, and no attenuation field on any material — so the mandated test "noise behind a wall
creates Investigating, not Combat" could not be written):

    # material schema gains: acoustic_attenuation_db_per_tile
    #   stone 25, wood 12, earth 18, water 8, steam/smoke 2, open 0
    const FLOOR_DB: float = 10.0
    const MAX_HEARING_RANGE_M: float = 40.0
    const MAX_NOISE_EVENTS_PER_CHUNK_PER_TICK: int = 8   # loudest first
    const MAX_LISTENERS_PER_EVENT: int = 16              # nearest first

    source_db = FLOOR_DB + 20.0 * log(max(noise_radius_m, 1.0)) / log(10.0)
    loudness  = source_db - 20.0 * log(max(dist_m, 1.0)) / log(10.0) \
                          - sum(attenuation_db over tiles on the DDA segment)
    heard if loudness > FLOOR_DB - 10.0 * log(hearing_sensitivity) / log(10.0)

Verification: a sword impact (`noise_radius_m = 18` -> source_db 35.1) heard from 15 m through
one stone wall = 35.1 - 23.5 - 25 = -13.4 -> NOT heard. Same distance, open air = 11.6 > 10 ->
heard -> INVESTIGATING. A door slam (radius 60 -> 45.6) through steam = 20.1 -> heard. That
makes the required test expressible. The two caps keep cost at ~128 marches = 0.35 ms.
# Witness: if an entity perceives a [Crime] action, emit WitnessEvent(observer, subject,
# action, location, tick, confidence) and write a MemoryEvent. Reputation changes through
# gossip/faction_memory, never via a global crime flag.

Tests to add with implementation: unseen crime does not revoke Guest_Status; noise behind a
wall creates Investigating, not Combat; steam blocks line of sight.
