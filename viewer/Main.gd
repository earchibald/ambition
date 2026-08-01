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
	# Sprint 2 boots the GENERATED world by default: history, village, factions at their anchors.
	# `debug_config.json` can select `test_arena` instead, which is the fast path the scope doc
	# budgets at under 2 seconds and the one to use while iterating on movement and combat.
	World.boot_scenario(DebugFlags.boot_scenario, 1)
	if World.scenario == World.SCENARIO_TEST_ARENA:
		_spawn_demo_contents()
	print("Godot %s" % Engine.get_version_info().get("string", "unknown"))
	print("autoloads: ECSEvents=%s ECSManager=%s GameLoopManager=%s" % [
		ECSEvents != null,
		ECSManager != null,
		GameLoopManager != null,
	])
	print("player handle: %s" % EH.to_debug_string(ECSManager.player_handle()))
	print("world: %s  player at %v" % [World.scenario, ECSManager.position_of(0)])
	# Printed every boot, because "which scenario am I in and how do I change it" cost a
	# play-tester a whole session. `--scenario=test_arena` is the answer; the file path is the
	# fallback, and it is an OS-specific directory nobody can guess.
	print("scenario: %s   (override: --scenario=test_arena|world)" % World.scenario)
	print("debug config: %s" % DebugFlags.config_path_for_humans())
	# Printed LAST, so its presence means every check above completed.
	print(BOOT_SENTINEL)
	_maybe_run_soak()


## ADR-20's soak harness: `--soak=<n>` runs n Micro ticks headless, dumps every counter to a
## CSV under `user://debug_traces/`, gates the DETERMINISTIC integer metrics against the
## committed baseline, and exits nonzero on drift. The gate is the deliverable: "did any metric
## leave its band" against a committed file, not a human squinting at a log.
func _maybe_run_soak() -> void:
	if DebugFlags.soak_ticks <= 0:
		return
	GameLoopManager.set_physics_process(false)
	for _tick in DebugFlags.soak_ticks:
		GameLoopManager._physics_process(1.0 / 60.0)
	get_tree().quit(SoakGate.run_and_report(DebugFlags.soak_ticks))


## A rat to fight and a nugget to pick up, so Gate A and Gate B are reachable on boot.
##
## SPRINT 4 ADDS THREE TARGETS, for the same reason `K` and `R` exist: a feature with no route in
## from the keyboard is one nobody can play-test, and this project has shipped that four times.
## The reaction matrix needs something to react, and the arena had no spores, no volatile gas and
## nothing burning.
##
## They are placed APART — further than `ReactionSystem.CONTACT_RADIUS_M` — so nothing goes off
## on boot. The player sets them off with a spell, which makes one demo out of the Grimoire, the
## cast path and the reaction matrix instead of three separate things to arrange.
func _spawn_demo_contents() -> void:
	var chunk: ChunkData = World.active_chunk
	var spawn: Vector3 = TestArena.spawn_position(chunk)
	World.spawn_creature(spawn + Vector3(3.0, 0.0, 0.0), &"SPC_CORPSE_RAT")
	World.spawn_item(spawn + Vector3(1.5, 0.5, 0.0), MaterialLibrary.MAT_COPPER, 112.0, 5)

	# Shoot this with a fireball: flash-fire, the biomass burns, the chunk's air warms.
	World.spawn_reactant(
		spawn + Vector3(0.0, 0.5, 8.0), MaterialLibrary.MAT_BIOMASS, 100.0, &"Spores"
	)
	# Shoot this one instead: explosion, and everything nearby is thrown outward.
	World.spawn_reactant(
		spawn + Vector3(6.0, 0.5, 8.0), MaterialLibrary.MAT_SULFUR, 1000.0, &"Volatile_Gas"
	)
	World.spawn_brazier(spawn + Vector3(-4.0, 0.5, 4.0))

	# The library lectern: `E` to read, and every rune in the build becomes castable. Ten of
	# seventeen runes were reachable only from tests (gap G-3); in the arena — the room where
	# everything is supposed to be testable — the whole rune set is one interaction away.
	var all_runes: Array[StringName] = []
	for rune_id in RuneLibrary.RUNES:
		all_runes.append(rune_id)
	World.spawn_lectern(spawn + Vector3(-2.0, 0.5, 2.0), all_runes)


## Fails loudly at boot rather than subtly at runtime. These are the Sprint 0 gate
## conditions from `docs/invariants_and_test_strategy.md`.
func _verify_boot_contract() -> void:
	assert(ECSEvents != null, "ECSEvents autoload missing")
	# Content validation at BOOT, not only under GUT. `validate_table` existed and ran only in
	# tests, so a bad material committed without running the suite shipped silently.
	assert(
		MaterialLibrary.validate_table().is_empty(),
		"material table invalid: %s" % ", ".join(MaterialLibrary.validate_table())
	)
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
		&"precision_move",
		&"attack",
		&"attack_secondary",
		&"inspect",
		&"debug_hurt",
		&"debug_respawn",
		&"cycle_debug_page",
		&"slow_time",
		&"toggle_gizmos",
		&"overlay_text_bigger",
		&"overlay_text_smaller",
		&"cancel",
		&"grimoire",
		&"cast",
		&"debug_hazard",
		&"free_camera",
		&"debug_spawn_rat",
		&"debug_spawn_item",
	]:
		assert(InputMap.has_action(action), "missing InputMap action: %s" % action)
