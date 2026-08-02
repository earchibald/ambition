## Debug/observability configuration (debugging spec §9, Sprint 0 deliverable).
##
## Flags are read from `user://debug_config.json` when present, so they can be toggled without
## a rebuild. Defaults are safe for CI: traces off, assertions on.
##
## Observability READS ECS state and never mutates it. Nothing here may gate simulation
## behaviour — only what gets recorded or drawn.
class_name DebugFlags
extends RefCounted

const CONFIG_PATH: String = "user://debug_config.json"
const TRACE_DIR: String = "user://debug_traces"

## Ring-buffer capacity for the structured event trace (debugging spec §3).
const DEFAULT_TRACE_CAPACITY: int = 4096

## Overlay text size in points at the 1280x720 reference resolution. The window stretch mode is
## `canvas_items`, so the drawn size scales with the window on top of this.
##
## Readability is not a preference to be defaulted to the smallest legible value. 13 pt was
## chosen by an agent that never had to read it on a real monitor.
const DEFAULT_OVERLAY_FONT_SIZE: int = 20
const MIN_OVERLAY_FONT_SIZE: int = 10
const MAX_OVERLAY_FONT_SIZE: int = 64

static var event_trace_enabled: bool = false
static var perception_overlay_enabled: bool = false
static var fluid_overlay_enabled: bool = false
static var tick_counters_enabled: bool = true
static var hard_fail_on_invariant_violation: bool = true
static var trace_capacity: int = DEFAULT_TRACE_CAPACITY

static var overlay_font_size: int = DEFAULT_OVERLAY_FONT_SIZE
## Wireframe reach/arc/facing overlays. Off by default since the player HUD landed: they are
## debug drawing on a player's screen, and the heading nose covers facing. `G` summons them.
static var gizmos_enabled: bool = false
## Whether the debug overlay panel is up at boot. Off since the player HUD took over the
## player-facing duties; `F1` summons it exactly as before. A NEW key rather than a reuse of
## `boot_overlay_page`, because that key is already persisted in existing config files and
## reusing it would let an old save silently pin the overlay open forever.
static var overlay_visible_on_boot: bool = false
## Which scenario `Main` boots. "world" is the game; "test_arena" is the fast debug room the
## scope doc budgets at under 2 seconds, kept reachable because it is the loop paid ~50 times
## a day while iterating on movement and combat.
static var boot_scenario: StringName = &"world"
## Overlay page index the game opens on. Only useful for capturing a specific page in a headless
## render; the default is the live counters.
static var boot_overlay_page: int = 0

## Micro ticks the ADR-20 soak harness should run before dumping metrics and exiting. Zero means
## "not a soak run". Set ONLY by `--soak=<n>`; deliberately absent from the config file and from
## `snapshot()`.
static var soak_ticks: int = 0

static var _loaded: bool = false

## Flags the command line overrode this run. A CLI override is for ONE run: without this,
## launching once with `--scenario=test_arena` and then nudging the font size would call
## `save_config`, write `test_arena` into the file, and silently make the override permanent —
## so the next plain `godot` boots the arena and the player has no idea why.
static var _cli_overrides: Dictionary = {}


## Idempotent. Called once from Main._ready(); safe to call again.
##
## COMMAND LINE LAST, so it beats the config file. Editing JSON in an OS-specific application
## data directory is not a developer loop — you cannot put it in a shell alias, a README, or a
## `.desktop` shortcut, and on macOS the path contains a space and the words "Application
## Support". `--scenario=test_arena` is what the scope document actually specifies.
static func initialize() -> void:
	if _loaded:
		return
	_loaded = true
	_ensure_trace_dir()
	_load_config()
	_apply_command_line()


## `--scenario=<name>` and `--overlay-font=<n>`, specified in `scope_and_milestones.md` §7 as a
## Sprint 1 deliverable and never built until 2026-08-01. Its absence meant the only way to reach
## the test arena — where every hand-authored feature in the build lives, including all three
## Sprint 4 props — was to hand-write JSON into `user://`, and RUNNING.md named that file eleven
## times before saying where it was.
##
## Both `godot --scenario=x` and `godot -- --scenario=x` work. Godot swallows arguments it
## recognises, so unknown ones appear in `get_cmdline_args()`; anything after a bare `--` appears
## in `get_cmdline_user_args()` instead. Reading both means the caller does not have to know
## which list Godot chose to put it in.
static func _apply_command_line() -> void:
	var args: PackedStringArray = OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	for arg in args:
		if arg.begins_with("--scenario="):
			_cli_overrides["boot_scenario"] = boot_scenario
			boot_scenario = StringName(arg.trim_prefix("--scenario="))
		elif arg.begins_with("--overlay-font="):
			_cli_overrides["overlay_font_size"] = overlay_font_size
			overlay_font_size = clampi(
				int(arg.trim_prefix("--overlay-font=")),
				MIN_OVERLAY_FONT_SIZE,
				MAX_OVERLAY_FONT_SIZE
			)
		elif arg == "--no-overlay":
			_cli_overrides["tick_counters_enabled"] = tick_counters_enabled
			tick_counters_enabled = false
		elif arg.begins_with("--soak="):
			# ADR-20's headless soak entry point: run N ticks, dump a metrics CSV, gate against
			# the committed baseline. CLI-only by nature — never loaded from or saved to the
			# config file, because a persisted soak would make every future boot a soak.
			soak_ticks = maxi(0, int(arg.trim_prefix("--soak=")))


## The debugging spec requires that logs be writable under `user://`. Fail loudly here rather
## than discovering it when an assertion tries to dump a trace.
static func _ensure_trace_dir() -> void:
	if DirAccess.dir_exists_absolute(TRACE_DIR):
		return
	var err: int = DirAccess.make_dir_recursive_absolute(TRACE_DIR)
	if err != OK:
		push_error("cannot create %s (err %d) — debug traces would be lost" % [TRACE_DIR, err])


static func _load_config() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		return
	var file: FileAccess = FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_warning("could not open %s; using defaults" % CONFIG_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("%s is not a JSON object; using defaults" % CONFIG_PATH)
		return
	event_trace_enabled = bool(parsed.get("event_trace_enabled", event_trace_enabled))
	perception_overlay_enabled = bool(
		parsed.get("perception_overlay_enabled", perception_overlay_enabled)
	)
	fluid_overlay_enabled = bool(parsed.get("fluid_overlay_enabled", fluid_overlay_enabled))
	tick_counters_enabled = bool(parsed.get("tick_counters_enabled", tick_counters_enabled))
	hard_fail_on_invariant_violation = bool(
		parsed.get("hard_fail_on_invariant_violation", hard_fail_on_invariant_violation)
	)
	trace_capacity = int(parsed.get("trace_capacity", trace_capacity))
	# Read under a NEW key ("gizmos_visible", not "gizmos_enabled") as a one-time default
	# reset: every existing config file has the OLD on-by-default baked in from before the
	# player HUD existed, and honouring it would pin the debug wireframes on for exactly the
	# players the new default is for. `G` re-saves the preference under the new name.
	gizmos_enabled = bool(parsed.get("gizmos_visible", gizmos_enabled))
	overlay_visible_on_boot = bool(
		parsed.get("overlay_visible_on_boot", overlay_visible_on_boot)
	)
	boot_scenario = StringName(parsed.get("boot_scenario", String(boot_scenario)))
	boot_overlay_page = int(parsed.get("boot_overlay_page", boot_overlay_page))
	overlay_font_size = clampi(
		int(parsed.get("overlay_font_size", overlay_font_size)),
		MIN_OVERLAY_FONT_SIZE,
		MAX_OVERLAY_FONT_SIZE
	)


static func snapshot() -> Dictionary:
	return {
		"event_trace_enabled": event_trace_enabled,
		"perception_overlay_enabled": perception_overlay_enabled,
		"fluid_overlay_enabled": fluid_overlay_enabled,
		"tick_counters_enabled": tick_counters_enabled,
		"hard_fail_on_invariant_violation": hard_fail_on_invariant_violation,
		"trace_capacity": trace_capacity,
		"overlay_font_size": overlay_font_size,
		"gizmos_visible": gizmos_enabled,
		"overlay_visible_on_boot": overlay_visible_on_boot,
		"boot_scenario": String(boot_scenario),
		"boot_overlay_page": boot_overlay_page,
	}


## Persists the current flags, so a size chosen at runtime survives a restart. Writing the file
## by hand to change one number is a chore nobody does twice.
##
## COMMAND-LINE OVERRIDES ARE NOT PERSISTED. `--scenario` is for one run; writing it back would
## make a throwaway flag permanent and leave the player wondering why the game now boots the
## debug arena.
static func save_config() -> void:
	var file: FileAccess = FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("could not write %s; overlay settings will not persist" % CONFIG_PATH)
		return
	var persisted: Dictionary = snapshot()
	persisted.merge(_cli_overrides, true)
	file.store_string(JSON.stringify(persisted, "\t"))


## Where the config file actually lives, as a real filesystem path. `user://` is meaningless in a
## shell, and RUNNING.md referred to this file eleven times before saying where it was.
static func config_path_for_humans() -> String:
	return ProjectSettings.globalize_path(CONFIG_PATH)
