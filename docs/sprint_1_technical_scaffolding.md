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

class PhysicalPropertyComponent extends RefCounted:
    var quantity: int = 1 # Mandatory for stacking (e.g. 10,000 gold coins as 1 entity)
    var mass_kg: float
    var volume_cm3: float
    var temperature: float = 20.0
    var phase: String = "Solid" 

class NeedsComponent extends RefCounted:
    var hunger: float = 0.0
    var energy: float = 100.0




The Registry Structure

# ECSManager.gd (Autoload)
var next_entity_id: int = 1
var active_entities: Array[int] = []

# Component Registries (Sparse Sets via Godot Dictionaries)
var positions: Dictionary = {} # { entity_id: PositionComponent }
var physicals: Dictionary = {} 
var needs: Dictionary = {}




3. The Godot/ECS Event Bus (The Bridge)

The global event bus (ECSEvents.gd Autoload) communicates state changes.

signal entity_created(entity_id: int, tags: Array[String], initial_pos: Vector3)
signal entity_destroyed(entity_id: int)
signal entity_moved(entity_id: int, new_pos: Vector3)
signal chunk_state_changed(chunk_id: Vector3i, is_active: bool)




The ViewManager (The "Dumb" Viewer)

# ViewManager.gd
var visual_dictionary: Dictionary = {} # { entity_id: Node3D }

func _on_entity_created(entity_id, tags, pos):
    # Instantiate a purely visual Node3D based on tags. 
    # NO PHYSICS NODES (No CollisionShape3D / RigidBody3D).
    
func _process(delta):
    # Interpolate visual positions based on ECS exact_pos for smooth rendering
    for entity_id in visual_dictionary:
        var node = visual_dictionary[entity_id]
        var target_pos = ECSManager.positions[entity_id].exact_pos
        node.global_position = node.global_position.lerp(target_pos, delta * 15.0)



4. Input & Action Intents (Bridging Player Control)

Player input does not move the player. It generates data structs that the ECS processes.

# ActionIntent Struct
class ActionIntent extends RefCounted:
    var type: String # e.g., "MOVE", "MELEE", "DROP"
    var target_id: int = -1
    var vector_data: Vector3 = Vector3.ZERO

# ECSManager Data Additions:
var action_queues: Dictionary = {} # { entity_id: Array[ActionIntent] }



When Godot reads Input.get_vector(), it pushes an ActionIntent (type="MOVE", vector_data=Input Vector) to Entity 0's action_queue. The ECS Micro Tick pops this queue and applies it to Entity 0's velocity.

5. Cellular Automata Data Structure (Fluid Dynamics)

Chunks hold 1D arrays representing 2D/3D grids.

class FluidGridComponent extends RefCounted:
    var grid_size: int = 64 
    var volume_map: PackedInt32Array # Read buffer
    var next_volume_map: PackedInt32Array # Write buffer (prevents cascade errors)
    var material_map: PackedInt32Array 
    
    # FLOOD BUFFER: Track pending volume from adjacent chunks
    var flood_buffer_queue: Dictionary = {} # { Target_Cell_Index: Total_Pending_Volume }



6. Pathfinding Ownership (STRICTLY ASYNCHRONOUS HANDSHAKE)

Mandatory Patch: The main thread will freeze if chunks shift to Active and 50 entities request paths synchronously.

ECS System: Emits request_path(entity_id, start_pos, target_pos). Entity enters Idle_Waiting_For_Path state.

NavBridge (Godot): Queues the requests. Processes max N (e.g., 5) per frame.

NavBridge Query: MUST use NavigationServer3D.query_path_async(). Do NOT use map_get_path().

Godot to ECS: Emits path_calculated(entity_id, path_array). Entity shifts to Moving state.

7. Sprint 1 AI: Utility Evaluation Math & The Acoustic Fix

Run this during the Simulation Tick for entities with a NeedsComponent and ScheduleComponent.

# Pseudo-code inside JobResolutionSystem
func evaluate_needs(entity_id: int) -> String:
    var needs = ECSManager.needs[entity_id]
    
    var hunger_urgency = (needs.hunger / 100.0) * 2.0 # Weight multiplier
    var energy_urgency = (1.0 - (needs.energy / 100.0)) * 1.5
    
    if hunger_urgency > 1.5:
        return "ActionIntent_Consume"
    elif energy_urgency > 1.2:
        return "ActionIntent_Sleep"
    else:
        return "ActionIntent_Work" # Fallback to Routine block



The Omniscient Combat Fix (Acoustic Injection)

When ActionResolutionSystem resolves a projectile hitting a target (e.g., Arrow hits Goblin):

DO NOT instantly assign Job_Combat(Target=Player).

DO spawn an [Ephemeral_Noise_Entity] at the point of impact.

If the Goblin does not have the Player in its VisionCone, its AI parses the noise entity and assigns Job_Investigate(Impact_Location).

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

# SpatialHash.gd (per Active chunk, rebuilt/updated each Micro tick)
var cells: Dictionary = {} # { Vector2i(cell_x, cell_z): PackedInt32Array of entity_ids }
func query_radius(pos: Vector3, r: float) -> Array[int]: ...   # melee/AoE/proximity
func query_ray(origin: Vector3, dir: Vector3) -> int: ...      # crosshair/mouse pick (grid DDA)

# CollisionResolveSystem (Micro tick, AFTER velocity integration)
# For each active mover: compute desired exact_pos += velocity*delta, then sweep its AABB
# via grid-DDA against chunk.tile_map solid cells; on hit, project velocity along the
# surface (slide) or stop. 2.5D: use the per-tile heightmap for steps/drops. No physics nodes.
# Loose solid items (dropped/scattered/thrown, incl. backpack rupture) use the SAME
# integrator + grid collision with a sleep-on-rest rule (resolves review B4/D7).

# PickSystem (used by input + Tactical Lens): project a camera ray in pure math, march it
# through the SpatialHash + tile_map (DDA), return the hit entity_id / tile. The camera is a
# viewer node; the ray math is ECS/bridge-side.

# NavigationServer3D: SANCTIONED EXCEPTION for Active-chunk local steering only (baked per
# Active chunk, owns no state); fall back to tile_map grid A* if a region isn't baked.
# Simulated/Abstracted movement uses the ECS-owned AbstractGraph (see ECS spec Section 7).

10. Combat Math — Defined Stats & Units (resolves review H1)

BodyComponent gains `strength: float` (baseline ~10). Creatures carry `density` (from the
Sprint 5 bestiary). Kinetic force is in Newtons-equivalent game units:
    impact_force = |velocity| * (weapon_mass_kg + strength)
A hit "kills" when impact_force exceeds the target's structural threshold
(target.mass_kg * target.density * TOUGHNESS_CONST). Define TOUGHNESS_CONST in one place.
Targeting uses PickSystem.query_ray (Section 9), NOT a Godot raycast.
