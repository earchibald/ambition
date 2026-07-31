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
	print("Godot %s" % Engine.get_version_info().get("string", "unknown"))
	print("autoloads: ECSEvents=%s ECSManager=%s GameLoopManager=%s" % [
		ECSEvents != null,
		ECSManager != null,
		GameLoopManager != null,
	])
	print("player handle: %s" % EH.to_debug_string(ECSManager.player_handle()))
	# Printed LAST, so its presence means every check above completed.
	print(BOOT_SENTINEL)


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
