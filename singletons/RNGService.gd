## Named, independently-seeded RNG streams (ADR-8).
##
## MUST `extends Node` to be autoloadable. Every stream's state is serializable, so a loaded
## save CONTINUES from where it stopped. ADR-1 promises continuation, not cross-platform
## reproducibility.
##
## Simulation code must never call `randf()`/`randi()` directly — a global generator cannot be
## saved and makes the ADR-20 soak harness irreproducible.
extends Node

const STREAM_NAMES: Array[StringName] = [
	&"worldgen",
	&"dag",
	&"combat",
	&"mutation",
	&"economy",
	&"loot",
	&"perception",
	&"magic",
]

var master_seed: int = 0

var _streams: Dictionary = {}


func _ready() -> void:
	reseed_all(1)


## Derives each stream from the master seed so one seed reproduces a whole first generation.
func reseed_all(new_master_seed: int) -> void:
	master_seed = new_master_seed
	_streams.clear()
	for name in STREAM_NAMES:
		var rng := RandomNumberGenerator.new()
		# Mix the stream name in so streams are independent but master-derived.
		rng.seed = hash(str(new_master_seed) + ":" + String(name))
		_streams[name] = rng


func stream(name: StringName) -> RandomNumberGenerator:
	assert(_streams.has(name), "unknown RNG stream: %s" % name)
	return _streams[name]


func randf_in(name: StringName) -> float:
	return stream(name).randf()


func randi_range_in(name: StringName, from: int, to: int) -> int:
	return stream(name).randi_range(from, to)


## ADR-21: `state` is a 64-bit int and Godot's JSON coerces every number to a double, which
## silently corrupts it and breaks continuation. Split into two sub-2^32 halves.
func save_to_dict() -> Dictionary:
	var out: Dictionary = {
		"master_seed_hi": master_seed >> 32,
		"master_seed_lo": master_seed & 0xFFFFFFFF,
	}
	var streams: Dictionary = {}
	for name in _streams:
		var rng: RandomNumberGenerator = _streams[name]
		streams[String(name)] = {
			"seed_hi": rng.seed >> 32,
			"seed_lo": rng.seed & 0xFFFFFFFF,
			"state_hi": rng.state >> 32,
			"state_lo": rng.state & 0xFFFFFFFF,
		}
	out["streams"] = streams
	return out


func load_from_dict(data: Dictionary) -> void:
	master_seed = (int(data.get("master_seed_hi", 0)) << 32) | int(data.get("master_seed_lo", 0))
	var streams: Dictionary = data.get("streams", {})
	for name in STREAM_NAMES:
		if not _streams.has(name):
			_streams[name] = RandomNumberGenerator.new()
		if not streams.has(String(name)):
			continue
		var entry: Dictionary = streams[String(name)]
		var rng: RandomNumberGenerator = _streams[name]
		rng.seed = (int(entry.get("seed_hi", 0)) << 32) | int(entry.get("seed_lo", 0))
		rng.state = (int(entry.get("state_hi", 0)) << 32) | int(entry.get("state_lo", 0))
