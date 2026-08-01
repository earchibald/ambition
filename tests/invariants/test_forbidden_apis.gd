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

## A table, not a match ladder: gdlint caps a function at six returns, and the cap is the right
## shape of rule here — this is data, and data belongs in a constant.
const REGISTRY_ENUMS: Dictionary = {
	"Phase": ECSEnums.Phase,
	"LoD": ECSEnums.LoD,
	"Quality": ECSEnums.Quality,
	"RelationshipStatus": ECSEnums.RelationshipStatus,
	"JobStatus": ECSEnums.JobStatus,
	"Objective": ECSEnums.Objective,
	"Emotion": ECSEnums.Emotion,
	"AwarenessState": ECSEnums.AwarenessState,
	"MaterializationPolicy": ECSEnums.MaterializationPolicy,
	"NodeType": ECSEnums.NodeType,
	"NodeStatus": ECSEnums.NodeStatus,
	"EdgeType": ECSEnums.EdgeType,
}


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


## THE TYPED-ARRAY TERNARY TRAP. `var xs: Array[T] = a if c else b` yields an UNTYPED Array, and
## assigning that to a typed one throws at RUNTIME — aborting the enclosing function part-way,
## which GDScript then reports as a plain `false`/null return rather than as an error the caller
## can see.
##
## It has shipped twice. In Sprint 1 it aborted the collision axis resolve every frame; in
## Sprint 2 it made `_passes_filters` refuse every item that had no ChemistryComponent, which
## surfaced to the player as "take refused - this container refuses it" on a pile of cloth.
##
## Both times the code read perfectly and the failure looked like a logic bug somewhere else.
## Build the array explicitly instead.
func test_no_typed_array_is_assigned_from_a_ternary() -> void:
	var offenders: Array[String] = []
	for dir in FIRST_PARTY_DIRS:
		for path in _gd_files(dir):
			var line_number: int = 0
			for line in _read(path).split("\n"):
				line_number += 1
				if not line.contains(": Array["):
					continue
				# A declaration with a conditional on the same line is the whole hazard.
				if line.contains(" if ") and line.contains(" else "):
					offenders.append("%s:%d %s" % [path, line_number, line.strip_edges()])
	assert_eq(
		offenders,
		[] as Array[String],
		"typed arrays are built explicitly, never from a ternary"
	)


## THE REGISTRY IS CANONICAL, and nothing enforced it until 2026-08-01.
##
## `docs/component_and_field_registry.md` is declared the single source of truth for every enum
## name and member, and the specs, the JSON output schema, and the content validators all quote it.
## It was kept in step with `ECSEnums` by hand, which is to say by luck. An audit found the
## roadmap naming a `Killed_By` edge type the enum did not have; the implementation overloaded
## `DESTROYED` and recorded player deaths backwards for the whole sprint.
##
## This parses the registry and compares it to the enum, so the two cannot drift again in silence.
func test_every_registry_enum_matches_the_code() -> void:
	var text: String = FileAccess.get_file_as_string(
		"res://docs/component_and_field_registry.md"
	)
	assert_ne(text, "", "the registry was readable at all")

	var checked: int = 0
	for line in text.split("\n"):
		var trimmed: String = line.strip_edges()
		if not trimmed.begins_with("- `"):
			continue
		var open_brace: int = trimmed.find("{")
		var close_brace: int = trimmed.find("}")
		if open_brace < 0 or close_brace < open_brace:
			continue
		var name: String = trimmed.substr(3, open_brace - 3).strip_edges()
		# Lines like `RelationshipState = { score:float ... }` are record shapes, not enums.
		if not _enum_exists(name):
			continue

		var documented: Array[String] = []
		for member in trimmed.substr(
			open_brace + 1, close_brace - open_brace - 1
		).split(","):
			var cleaned: String = member.strip_edges()
			if cleaned != "":
				documented.append(cleaned)

		var actual: Array[String] = []
		for key in _enum_dictionary(name):
			actual.append(String(key))
		assert_eq(
			actual, documented, "%s matches the registry, member for member and in order" % name
		)
		checked += 1

	# Without this the loop above is vacuous if the parse ever silently stops matching.
	assert_gt(checked, 8, "the registry really was parsed, not skipped")


func _enum_exists(name: String) -> bool:
	return not _enum_dictionary(name).is_empty()


func _enum_dictionary(name: String) -> Dictionary:
	return REGISTRY_ENUMS.get(name, {})
