## What survives a death (Sprint 3 Step 6).
##
## The death loop's premise is that the WORLD persists and the CHARACTER does not. The journal is
## the narrow, deliberate exception: knowledge carries forward, possessions do not. Getting that
## boundary wrong in either direction ruins the loop — carry everything and death costs nothing,
## carry nothing and 40 hours of learning evaporates.
##
## Only `MindComponent.insight` and `known_runes` cross. Not health, not inventory, not position,
## not reputation: the next adventurer is a different person who happens to have read the same
## notes.
##
## ADR-21: JSON coerces every number to a double, so integers above 2^53 corrupt silently. Insight
## values are small counters and are safe, but the schema version is written explicitly so a
## future field cannot quietly widen past that limit without someone noticing the migration.
class_name LineageJournal
extends RefCounted

const PATH: String = "user://lineage_journal.json"
const SCHEMA_VERSION: int = 1


## Captures what the dying adventurer knew. Called BEFORE the Interregnum, because the
## Interregnum destroys the entity this reads from.
static func capture(row: int) -> Dictionary:
	var mind: MindComponent = ECSManager.minds.get(row)
	if mind == null:
		return _empty()
	return {
		"schema_version": SCHEMA_VERSION,
		"generation": 0,
		"insight": mind.insight.duplicate(),
		"known_runes": mind.known_runes.map(func(r: StringName) -> String: return String(r)),
		"deaths": 1,
	}


## Merges a new death into whatever is already on disk, then writes it. Insight takes the HIGHER
## of the two: a later adventurer who learned less about a subject should not erase what an
## earlier one knew, because the journal is the lineage's memory rather than one life's.
static func record_death(row: int) -> Dictionary:
	var previous: Dictionary = load_journal()
	var fresh: Dictionary = capture(row)

	var merged_insight: Dictionary = previous.get("insight", {}).duplicate()
	for subject in fresh.get("insight", {}):
		merged_insight[subject] = maxi(
			int(merged_insight.get(subject, 0)), int(fresh["insight"][subject])
		)
	var runes: Array = previous.get("known_runes", []).duplicate()
	for rune in fresh.get("known_runes", []):
		if not runes.has(rune):
			runes.append(rune)

	var journal: Dictionary = {
		"schema_version": SCHEMA_VERSION,
		"generation": int(previous.get("generation", 0)) + 1,
		"insight": merged_insight,
		"known_runes": runes,
		"deaths": int(previous.get("deaths", 0)) + 1,
	}
	save_journal(journal)
	return journal


## Dresses a new adventurer in what the lineage knows.
static func apply_to(row: int, journal: Dictionary) -> void:
	var mind: MindComponent = ECSManager.minds.get(row)
	if mind == null:
		return
	mind.insight = journal.get("insight", {}).duplicate()
	mind.known_runes.clear()
	for rune in journal.get("known_runes", []):
		mind.known_runes.append(StringName(rune))


static func load_journal() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return _empty()
	var file: FileAccess = FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		push_warning("lineage journal exists but could not be opened; starting fresh")
		return _empty()
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		# Corrupt beats crashed. A damaged journal costs the player their notes; refusing to boot
		# costs them the game.
		push_warning("lineage journal is not a JSON object; starting fresh")
		return _empty()
	return _migrate(parsed)


static func save_journal(journal: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		push_error("could not write the lineage journal; this death will not carry forward")
		return
	file.store_string(JSON.stringify(journal, "\t"))


static func erase() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


## Forward migration by version. Unknown FUTURE versions are refused rather than guessed at:
## reading a newer schema with older code is how a save gets silently mangled.
static func _migrate(journal: Dictionary) -> Dictionary:
	var version: int = int(journal.get("schema_version", 0))
	if version > SCHEMA_VERSION:
		push_warning("lineage journal is from a newer build; ignoring it rather than mangling it")
		return _empty()
	journal["schema_version"] = SCHEMA_VERSION
	return journal


static func _empty() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"generation": 0,
		"insight": {},
		"known_runes": [],
		"deaths": 0,
	}
