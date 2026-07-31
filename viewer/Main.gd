## Root viewer node. Godot is a dumb viewer: this node owns NO authoritative state.
##
## Sprint 0's job is only to boot cleanly and prove it. Sprint 1 attaches the camera rig,
## ViewManager, and debug overlays here.
extends Node3D

## CI greps for this exact string. Without a sentinel the boot smoke test cannot fail:
## a scene whose `_ready()` throws a hard runtime error still exits 0.
const BOOT_SENTINEL: String = "ECS_BOOT_OK"


func _ready() -> void:
	DebugFlags.initialize()
	_verify_boot_contract()
	# Debug scenario boot path: no DAG generation, no worldgen, no pre-warm. Budget is under
	# 2 seconds to controllable, because this is the loop paid ~50 times a day.
	World.boot_scenario(World.SCENARIO_TEST_ARENA, 1)
	_spawn_demo_contents()
	print("Godot %s" % Engine.get_version_info().get("string", "unknown"))
	print("autoloads: ECSEvents=%s ECSManager=%s GameLoopManager=%s" % [
		ECSEvents != null,
		ECSManager != null,
		GameLoopManager != null,
	])
	print("player handle: %s" % EH.to_debug_string(ECSManager.player_handle()))
	print("world: %s  player at %v" % [World.scenario, ECSManager.position_of(0)])
	# Printed LAST, so its presence means every check above completed.
	print(BOOT_SENTINEL)


## A rat to fight and a nugget to pick up, so Gate A and Gate B are reachable on boot.
func _spawn_demo_contents() -> void:
	var chunk: ChunkData = World.active_chunk
	var spawn: Vector3 = TestArena.spawn_position(chunk)
	World.spawn_creature(spawn + Vector3(3.0, 0.0, 0.0), &"SPC_CORPSE_RAT")
	World.spawn_item(spawn + Vector3(1.5, 0.5, 0.0), MaterialLibrary.MAT_COPPER, 112.0, 5)


## Fails loudly at boot rather than subtly at runtime. These are the Sprint 0 gate
## conditions from `docs/invariants_and_test_strategy.md`.
func _verify_boot_contract() -> void:
	assert(ECSEvents != null, "ECSEvents autoload missing")
	assert(ECSManager != null, "ECSManager autoload missing")
	assert(GameLoopManager != null, "GameLoopManager autoload missing")
	assert(
		ECSManager.is_player(ECSManager.player_handle()),
		"player entity must occupy index 0 at boot (ADR-14)"
	)
	for action in [
		&"move_left",
		&"move_right",
		&"move_forward",
		&"move_back",
		&"interact",
		&"attack",
		&"inspect",
		&"cancel",
	]:
		assert(InputMap.has_action(action), "missing InputMap action: %s" % action)
