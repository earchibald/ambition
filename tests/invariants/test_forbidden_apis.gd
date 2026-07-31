## Prime Directive enforcement, and the ADR-20 wall-clock ban.
##
## This test lives in a SUBDIRECTORY on purpose. GUT's `-gdir` does not recurse, so a suite
## that passes without seeing this file proves the runner is misconfigured (it needs
## `-ginclude_subdirs`). That was a real false-positive path in the original CI.
extends GutTest

## Banned in first-party simulation/viewer code (CLAUDE.md §1). NavigationServer3D is the one
## sanctioned exception (ADR-2) and is deliberately absent from this list.
const FORBIDDEN_PHYSICS: Array[String] = [
	"CharacterBody3D",
	"RigidBody3D",
	"Area3D",
	"move_and_slide",
	"PhysicsRayQueryParameters3D",
	"intersect_ray",
]

## ADR-20: simulation code must be reproducible from RNG seeds alone, so `ecs/` never reads
## wall-clock time. Only `ecs/` is scanned — profiling elsewhere is legitimate.
const FORBIDDEN_WALLCLOCK: Array[String] = [
	"Time.get_ticks_msec",
	"Time.get_ticks_usec",
	"Time.get_unix_time_from_system",
	"Engine.get_frames_drawn",
]

const FIRST_PARTY_DIRS: Array[String] = [
	"res://ecs",
	"res://viewer",
	"res://ui",
	"res://singletons",
]


func test_no_godot_physics_nodes_in_first_party_code() -> void:
	var offenders: Array[String] = []
	for dir in FIRST_PARTY_DIRS:
		for path in _gd_files(dir):
			var text: String = _read(path)
			for needle in FORBIDDEN_PHYSICS:
				if text.contains(needle):
					offenders.append("%s uses %s" % [path, needle])
	assert_eq(offenders, [] as Array[String], "no Godot physics nodes in gameplay code")


func test_ecs_never_reads_wall_clock() -> void:
	var offenders: Array[String] = []
	for path in _gd_files("res://ecs"):
		var text: String = _read(path)
		for needle in FORBIDDEN_WALLCLOCK:
			if text.contains(needle):
				offenders.append("%s uses %s" % [path, needle])
	assert_eq(offenders, [] as Array[String], "ecs/ is free of wall-clock reads (ADR-20)")


func test_phase_is_never_written_as_a_tag_string() -> void:
	# Registry §7: Solid/Liquid/Gas are Phase enum values, never ChemistryComponent tags.
	var offenders: Array[String] = []
	for dir in FIRST_PARTY_DIRS:
		for path in _gd_files(dir):
			var text: String = _read(path)
			for needle in ['&"Solid"', '&"Liquid"', '&"Gas"']:
				if text.contains(needle):
					offenders.append("%s uses phase-as-tag %s" % [path, needle])
	assert_eq(offenders, [] as Array[String], "phase is an enum, never a tag string")


func test_the_scan_actually_found_files() -> void:
	# Without this, an empty or broken walk would make every test above vacuously pass.
	var total: int = 0
	for dir in FIRST_PARTY_DIRS:
		total += _gd_files(dir).size()
	assert_gt(total, 0, "the forbidden-API scan must actually read some .gd files")


func _gd_files(root: String) -> Array[String]:
	var found: Array[String] = []
	var pending: Array[String] = [root]
	while not pending.is_empty():
		var current: String = pending.pop_back()
		var dir: DirAccess = DirAccess.open(current)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry: String = dir.get_next()
		while entry != "":
			if entry.begins_with("."):
				entry = dir.get_next()
				continue
			var full: String = current.path_join(entry)
			if dir.current_is_dir():
				pending.append(full)
			elif entry.ends_with(".gd"):
				found.append(full)
			entry = dir.get_next()
		dir.list_dir_end()
	return found


## Returns the file with COMMENTS STRIPPED. Scanning raw text would flag this project's own
## documentation, which deliberately names the banned APIs in order to explain why they are
## banned. Only real code is checked.
func _read(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var out: PackedStringArray = PackedStringArray()
	for line in file.get_as_text().split("\n"):
		var stripped: String = line.strip_edges()
		if stripped.begins_with("#"):
			continue
		var hash_at: int = line.find("#")
		if hash_at >= 0:
			out.append(line.substr(0, hash_at))
		else:
			out.append(line)
	return "\n".join(out)
