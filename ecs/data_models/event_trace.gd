## The structured event trace (debugging spec §3): a ring buffer with configurable capacity,
## dumpable to `user://debug_traces/`.
##
## Specified in Sprint 0, configured since Sprint 0 — `event_trace_enabled` and `trace_capacity`
## were parsed, snapshotted and read by NOTHING, and `_ensure_trace_dir()` created a directory
## no code ever wrote a file into. The overlay's 8-line feed was the entire observability record
## of a run: unstructured, unfilterable, and gone on scroll.
##
## Records carry the FRAME and the CLOCK, never wall time (ADR-20): a trace from a seeded run
## must line up with a second run of the same seed, or it cannot be used to diff them.
class_name EventTrace
extends RefCounted

static var records_taken: int = 0
static var _ring: Array[Dictionary] = []
static var _cursor: int = 0


## One structured record. A no-op unless the flag is on, so call sites never guard.
static func record(
	system: StringName, event_type: StringName, entity: int, detail: String = ""
) -> void:
	if not DebugFlags.event_trace_enabled:
		return
	var capacity: int = maxi(DebugFlags.trace_capacity, 1)
	var entry: Dictionary = {
		"frame": GameLoopManager.micro_frames,
		"clock_h": GameClock.total_hours(),
		"system": system,
		"event": event_type,
		"entity": entity,
		"detail": detail,
	}
	if _ring.size() < capacity:
		_ring.append(entry)
	else:
		_ring[_cursor % capacity] = entry
	_cursor = (_cursor + 1) % capacity
	records_taken += 1


## Oldest-first snapshot of the ring's current contents.
static func snapshot() -> Array[Dictionary]:
	var capacity: int = maxi(DebugFlags.trace_capacity, 1)
	if _ring.size() < capacity:
		return _ring.duplicate()
	var out: Array[Dictionary] = []
	for offset in _ring.size():
		out.append(_ring[(_cursor + offset) % _ring.size()])
	return out


## Writes the ring as CSV and returns the path ("" on failure). Called on player death and
## available to any assertion handler — the "dump on failure" half of the spec.
static func dump_to_file(label: String = "trace") -> String:
	var events: Array[Dictionary] = snapshot()
	var path: String = "%s/%s-%d.csv" % [DebugFlags.TRACE_DIR, label, records_taken]
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("could not write event trace to %s" % path)
		return ""
	file.store_line("frame,clock_h,system,event,entity,detail")
	for entry in events:
		file.store_line("%d,%d,%s,%s,%d,%s" % [
			int(entry["frame"]), int(entry["clock_h"]), entry["system"], entry["event"],
			int(entry["entity"]), String(entry["detail"]).replace(",", ";"),
		])
	return path


static func clear() -> void:
	_ring.clear()
	_cursor = 0
