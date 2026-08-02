## Dynamic state tags.
##
## Tags are StringName ONLY (registry section 7). Phase is NOT a tag: Solid/Liquid/Gas are
## `ECSEnums.Phase` values on PhysicalPropertyComponent.
##
## TAGS MAY EXPIRE. Sprint 4 needs `Reaction_Cooldown` to lapse after exactly 60 Micro ticks, and
## a lock that never lifts is not an anti-recursion guard, it is a permanently inert entity.
## Expiry is stored HERE rather than in the reaction system's own dictionary, because system-side
## state keyed by row outlives the entity: `destroy_entity` clears every registered registry in
## one operation, so a component field is cleaned up atomically and a system Dictionary is not.
## A recycled row would otherwise inherit the previous occupant's cooldown.
##
## Deadlines are MICRO-FRAME COUNTS, never seconds and never wall-clock (ADR-20). The frame
## number is passed in by the caller, so nothing in `ecs/` reads a clock to decide when a tag
## lapses, and a soak run replays identically.
class_name ChemistryComponent
extends RefCounted

## Deadlines never expire when absent from this map, so a plain `add_tag` still means "forever".
const NEVER: int = -1

var active_tags: Array[StringName] = []

## tag -> the Micro frame at which it lapses. Only timed tags appear here.
var tag_expiry: Dictionary = {}


func has_tag(tag: StringName) -> bool:
	return active_tags.has(tag)


## Adds a tag, optionally with a deadline. Re-adding an existing tag with a LATER deadline
## extends it — an entity set on fire twice burns until the second fire would have gone out,
## which is the only reading that does not let a rapid re-application shorten an effect.
func add_tag(tag: StringName, expires_at_frame: int = NEVER) -> bool:
	var fresh: bool = not active_tags.has(tag)
	if fresh:
		active_tags.append(tag)
	if expires_at_frame == NEVER:
		# An explicitly permanent re-application outranks a pending deadline.
		tag_expiry.erase(tag)
	elif not tag_expiry.has(tag) or int(tag_expiry[tag]) < expires_at_frame:
		tag_expiry[tag] = expires_at_frame
	return fresh


func remove_tag(tag: StringName) -> bool:
	tag_expiry.erase(tag)
	var idx: int = active_tags.find(tag)
	if idx < 0:
		return false
	active_tags.remove_at(idx)
	return true


## Drops every tag whose deadline has passed. Returns how many lapsed, so the caller can report
## it rather than the component guessing that anyone cares.
func expire_tags(now_frame: int) -> int:
	if tag_expiry.is_empty():
		return 0
	var lapsed: Array[StringName] = []
	for tag in tag_expiry:
		if int(tag_expiry[tag]) <= now_frame:
			lapsed.append(tag)
	for tag in lapsed:
		remove_tag(tag)
	return lapsed.size()


## Frames remaining on a timed tag, or -1 if it is absent or permanent. Read by the inspector,
## because "Reaction_Cooldown" with no countdown beside it cannot be told from a stuck lock.
func frames_left(tag: StringName, now_frame: int) -> int:
	if not tag_expiry.has(tag):
		return -1
	return maxi(0, int(tag_expiry[tag]) - now_frame)
