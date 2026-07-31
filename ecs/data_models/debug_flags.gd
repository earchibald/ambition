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

static var event_trace_enabled: bool = false
static var perception_overlay_enabled: bool = false
static var fluid_overlay_enabled: bool = false
static var tick_counters_enabled: bool = true
static var hard_fail_on_invariant_violation: bool = true
static var trace_capacity: int = DEFAULT_TRACE_CAPACITY

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


static func snapshot() -> Dictionary:
	return {
		"event_trace_enabled": event_trace_enabled,
		"perception_overlay_enabled": perception_overlay_enabled,
		"fluid_overlay_enabled": fluid_overlay_enabled,
		"tick_counters_enabled": tick_counters_enabled,
		"hard_fail_on_invariant_violation": hard_fail_on_invariant_violation,
		"trace_capacity": trace_capacity,
	}
