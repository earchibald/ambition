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
const FALL_DAMAGE_M: float = 3.0

# --- Movement (ADR-18). ---
const BASE_SPEED_MPS: float = 4.0

# --- Combat (Sprint 1 §10, kinetic energy model). ---
const STRENGTH_REF: float = 10.0
const BASE_SWING_MPS: float = 5.0
const ARM_MASS_FRAC: float = 0.10
const J_PER_HP: float = 3.0
const TOUGHNESS_J: float = 120.0

# --- Fluid CA (Sprint 1 §5). 1 unit = 1 litre; a tile is 1 m^2. ---
const CA_UNIT_CM3: int = 1000
const MAX_CELL_VOLUME: int = 1000
const FLOW_MIN_DIFF: int = 2
const FLOOD_PUMP_UNITS_PER_TICK: int = 50

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
