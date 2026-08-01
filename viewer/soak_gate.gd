## The ADR-20 soak gate: dump metrics, compare against the committed baseline, verdict.
##
## Lives in `viewer/` because it does file IO and process-exit codes — infrastructure, not
## simulation. The metrics gated are INTEGER, CUMULATIVE counters only: ADR-20 promises a run is
## reproducible from its seed, so on the same seed and tick count these must match EXACTLY.
## Millisecond timings are dumped for humans and never gated — they measure the machine.
class_name SoakGate
extends RefCounted

const BASELINE_PATH: String = "res://tests/soak/soak_baseline.cfg"

## The gated set. Every one is deterministic under ADR-20; a mismatch means either the
## simulation stopped being seed-reproducible (an ADR-20 violation) or behaviour genuinely
## changed and the baseline needs a REVIEWED update — both are things a human must look at.
const GATED_METRICS: Array[String] = [
	"micro_frames",
	"sim_ticks",
	"macro_ticks",
	"fluid_ticks",
	"alive_count",
	"reason_enqueued",
	"grievances",
	"gossip_spread",
	"plans_made",
	"loyalty_updates",
]


## Returns the process exit code: 0 clean, 1 drifted, 2 no baseline (candidate written).
static func run_and_report(ticks: int) -> int:
	var counters: Dictionary = GameLoopManager.counters()
	var csv_path: String = _dump_csv(counters, ticks)
	print("SOAK_CSV %s" % ProjectSettings.globalize_path(csv_path))

	var baseline := ConfigFile.new()
	if baseline.load(BASELINE_PATH) != OK:
		var candidate: String = _write_candidate(counters, ticks)
		print("SOAK_BASELINE_MISSING — candidate written to %s" % candidate)
		print("review it, then commit it as %s" % BASELINE_PATH)
		return 2

	if int(baseline.get_value("soak", "ticks", -1)) != ticks:
		print("SOAK_BASELINE_MISMATCH — baseline is for %d ticks, this run was %d" % [
			int(baseline.get_value("soak", "ticks", -1)), ticks
		])
		return 1

	var drifted: int = 0
	for metric in GATED_METRICS:
		var expected: int = int(baseline.get_value("soak", metric, 0))
		var actual: int = int(counters.get(metric, 0))
		if expected != actual:
			drifted += 1
			print("SOAK_DRIFT %s: expected %d, got %d" % [metric, expected, actual])
	if drifted > 0:
		print("SOAK_FAIL — %d metric(s) left their band" % drifted)
		return 1
	print("SOAK_OK — %d metrics inside their bands over %d ticks" % [GATED_METRICS.size(), ticks])
	return 0


static func _dump_csv(counters: Dictionary, ticks: int) -> String:
	var path: String = "%s/soak-%s-%d.csv" % [DebugFlags.TRACE_DIR, World.scenario, ticks]
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return path
	file.store_line("metric,value")
	var keys: Array = counters.keys()
	keys.sort()
	for key in keys:
		file.store_line("%s,%s" % [key, counters[key]])
	return path


static func _write_candidate(counters: Dictionary, ticks: int) -> String:
	var candidate := ConfigFile.new()
	candidate.set_value("soak", "ticks", ticks)
	for metric in GATED_METRICS:
		candidate.set_value("soak", metric, int(counters.get(metric, 0)))
	var path: String = "%s/soak_baseline_candidate.cfg" % DebugFlags.TRACE_DIR
	candidate.save(path)
	return ProjectSettings.globalize_path(path)
