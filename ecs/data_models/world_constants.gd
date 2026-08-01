## Canonical world scale, tick, and budget constants (ADR-18, ADR-9, ADR-10).
##
## These are CORRECTNESS constants, not tuning knobs. Per `docs/scope_and_milestones.md` R4,
## budgets are test assertions and must never appear in a tuning UI. Feel constants live in
## `data/tunables.json` instead.
class_name WorldConstants
extends RefCounted

# --- Scale (ADR-18). `exact_pos` is in METRES, not tiles. ---
const TILE_SIZE_M: float = 1.0
const CHUNK_TILES: int = 64
const CHUNK_SIZE_M: float = CHUNK_TILES * TILE_SIZE_M

## Grids carry a 1-cell ghost apron so neighbour probes cannot wrap rows or run off the end
## of the array. Real cell (x, y) lives at (y + 1) * GRID_STRIDE + (x + 1).
const GRID_STRIDE: int = CHUNK_TILES + 2
const GRID_CELLS: int = GRID_STRIDE * GRID_STRIDE

# --- Ticks (ADR-9). Counted in physics frames, not accumulated floats. ---
const MICRO_TICK_HZ: int = 60
const SIM_TICK_EVERY_N_MICRO: int = 30  # 2 Hz
const MACRO_TICK_EVERY_N_MICRO: int = 600  # every 10 real seconds -> +1 in-game hour
const FLUID_TICK_EVERY_N_MICRO: int = 4  # 15 Hz (ADR-10, corrected by measurement)

# --- Collision / spatial (ADR-18, Sprint 1 §9). ---
const SPATIAL_CELL_M: float = 2.0
const MIN_ENTITY_EXTENT: float = 0.25
const SUBSTEP_MAX_M: float = 0.125
const STEP_UP_MAX_M: float = 0.5
const AUTO_DROP_MAX_M: float = 1.0
const GRAVITY_MPS2: float = 9.81
const SLIDE_EPSILON_M: float = 0.001
## Landings at or above this speed are announced to the event feed, damaging or not. Below it a
## landing is an ordinary footstep and reporting it would drown everything else.
const REPORTABLE_LANDING_MPS: float = 2.0

const SAFE_FALL_MPS: float = 5.0

# --- Movement (ADR-18). ---
## 4.0 m/s is a real brisk walk and reads as a CRAWL from this camera: the rig sits 11 m up, so
## screen-space displacement per metre is small, and the village is 192 m across. Tuned by
## playing rather than by realism — the number that matters is how fast the world goes past, not
## how fast the legs move.
const BASE_SPEED_MPS: float = 7.0

## Hold the precision modifier to move at this fraction of full speed. Full speed is for covering
## ground; this is for lining up on a ledge edge or a pit lip without overshooting.
const PRECISION_SPEED_SCALE: float = 0.35

# --- Combat (Sprint 1 §10, kinetic energy model). ---
const STRENGTH_REF: float = 10.0
const BASE_SWING_MPS: float = 5.0
const ARM_MASS_FRAC: float = 0.10
const J_PER_HP: float = 3.0
const TOUGHNESS_J: float = 120.0

const MAX_CELL_VOLUME: int = 1000
const FLOW_MIN_DIFF: int = 2
const FLOOD_PUMP_UNITS_PER_TICK: int = 50

# --- Chemistry reactions (Sprint 4 §1). ---
## The anti-recursion lock, in Micro frames. One second at 60 Hz, exactly as the scaffolding
## specifies. Counted in FRAMES rather than seconds so bullet-time cannot change how long a
## reaction stays locked out — a cooldown measured in scaled deltas would be six times longer
## while `T` is held, which is a physics rule quietly depending on a viewer setting.
const REACTION_COOLDOWN_FRAMES: int = 60

## Volumetric heat capacity of air at room temperature, J/(m^3 * K): 1.2 kg/m^3 * 1005 J/(kg*K).
## Real, so the ambient rise a fire produces is arguable rather than tuned.
const AIR_J_PER_M3_PER_C: float = 1206.0

## Ceiling height used to turn a chunk's floor area into a volume of air. The world is 2.5D, so
## there is no modelled ceiling; 3 m is a room.
const CHUNK_AIR_HEIGHT_M: float = 3.0

## No single reaction may move the ambient temperature more than this in one tick. A blast big
## enough to exceed it is still capped, because ambient feeds conduction into every entity in the
## chunk and an unbounded spike is how a thermodynamics bug becomes a world-wide one.
const MAX_AMBIENT_STEP_C: float = 40.0

## Blast impulse falls to zero at this multiple of the reaction radius.
const BLAST_FALLOFF_EXPONENT: float = 2.0

## Hard ceiling on the speed a blast may impart, m/s. Without it a light entity next to a large
## explosion leaves the chunk in one frame and the collision sweep has nothing to sweep against.
const MAX_BLAST_SPEED_MPS: float = 25.0

# --- Magic (Sprint 4 §2/§3). Geometric caps are ANTI-CRASH rules, not balance. ---
const MAX_SPELL_RADIUS_M: float = 15.0
const MAX_SPELL_SPEED_MPS: float = 40.0
const MAX_SPELL_TTL_S: float = 5.0
const MAX_SPELL_RUNES: int = 8
## Strain per point of spell complexity (scaffolding §2).
const STRAIN_PER_COMPLEXITY: float = 2.5
## Complexity budget is this multiple of the caster's Rune_Stability insight (scaffolding §2).
const RUNE_STABILITY_MULTIPLIER: float = 1.5

# --- Mutation (Sprint 4 §4). ---
const EXPOSURE_MUTATION_THRESHOLD: float = 100.0
const MAX_MUTATIONS: int = 3

# --- Performance budgets (ADR-10). TEST ASSERTIONS — never tunable. ---
const MICRO_BUDGET_MS: float = 8.0
const ACTIVE_ENTITY_TARGET: int = 1500
const ACTIVE_ENTITY_HARD_CAP: int = 3000
const TOTAL_ENTITY_TARGET: int = 10000
const CA_UPDATES_PER_FLUID_TICK: int = 12000
const PERCEPTION_MARCH_BUDGET: int = 1200
const MAX_CANDIDATES_PER_OBSERVER: int = 8

# --- Identity (ADR-14). ---
const PLAYER_INDEX: int = 0
const PLAYER_FACTION_ID: int = 0


## Row-major index into an aproned chunk grid. Never do raw `idx + 1` arithmetic.
static func cell_index(x: int, y: int) -> int:
	return (y + 1) * GRID_STRIDE + (x + 1)


static func is_player_faction(faction_id: int) -> bool:
	return faction_id == PLAYER_FACTION_ID
