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
## Wireframe reach/arc/facing overlays. On by default: Sprint 1 has no other way to see facing.
static var gizmos_enabled: bool = true
## Which scenario `Main` boots. "world" is the game; "test_arena" is the fast debug room the
## scope doc budgets at under 2 seconds, kept reachable because it is the loop paid ~50 times
## a day while iterating on movement and combat.
static var boot_scenario: StringName = &"world"

static var _loaded: bool = false


## Idempotent. Called once from Main._ready(); safe to call again.
static func initialize() -> void:
	if _loaded:
		return
	_loaded = true
	_ensure_trace_dir()
	_load_config()


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
	gizmos_enabled = bool(parsed.get("gizmos_enabled", gizmos_enabled))
	boot_scenario = StringName(parsed.get("boot_scenario", String(boot_scenario)))
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
		"gizmos_enabled": gizmos_enabled,
		"boot_scenario": String(boot_scenario),
	}


## Persists the current flags, so a size chosen at runtime survives a restart. Writing the file
## by hand to change one number is a chore nobody does twice.
static func save_config() -> void:
	var file: FileAccess = FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("could not write %s; overlay settings will not persist" % CONFIG_PATH)
		return
	file.store_string(JSON.stringify(snapshot(), "\t"))
