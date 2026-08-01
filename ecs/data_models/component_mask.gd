## Component mask bits for the archetype/query index (ADR-13).
##
## Systems never scan linearly. They call `ECSManager.query(mask)` and iterate the returned
## row indices. `get_all_entities_with_component` is banned by name in ADR-10.
class_name ComponentMask
extends RefCounted

const NONE: int = 0
const POSITION: int = 1 << 0
const BOUNDS: int = 1 << 1
const PHYSICAL: int = 1 << 2
const MATERIAL: int = 1 << 3
const CHEMISTRY: int = 1 << 4
const QUALITY: int = 1 << 5
const BODY: int = 1 << 6
const NEEDS: int = 1 << 7
const PERCEPTION: int = 1 << 8
const SENSORY_EMITTER: int = 1 << 9
const INVENTORY: int = 1 << 10
const CONTAINER: int = 1 << 11
const JOB: int = 1 << 12
const SCHEDULE: int = 1 << 13
const PROFESSION: int = 1 << 14
const SOCIAL_IDENTITY: int = 1 << 15
const OWNERSHIP: int = 1 << 16
const MEMORY: int = 1 << 17
const EPHEMERAL: int = 1 << 18
const LOD: int = 1 << 19
const MATERIALIZATION: int = 1 << 20
const PLAYER_INPUT: int = 1 << 21
const HEAT_SOURCE: int = 1 << 22
const LOOSE_ITEM: int = 1 << 23
const MIND: int = 1 << 24
const FACTION_CORE: int = 1 << 25
const LOCOMOTION: int = 1 << 26

# --- Common composite queries, named so call sites stay readable. ---

## Anything that integrates velocity and resolves collision each Micro tick.
const MOVER: int = POSITION | BOUNDS

## Anything the SpatialHash must contain.
const SPATIAL: int = POSITION | BOUNDS

## An agent that can perceive.
const PERCEIVER: int = POSITION | PERCEPTION

## A Tier-2 agent with a daily life.
const AGENT: int = POSITION | BODY | NEEDS | SCHEDULE

## Something that can be damaged.
const DAMAGEABLE: int = POSITION | BODY | PHYSICAL


## Human-readable mask for the debug inspector.
static func describe(mask: int) -> String:
	var names: Array[String] = []
	for entry in [
		[POSITION, "Position"],
		[BOUNDS, "Bounds"],
		[PHYSICAL, "Physical"],
		[MATERIAL, "Material"],
		[CHEMISTRY, "Chemistry"],
		[QUALITY, "Quality"],
		[BODY, "Body"],
		[NEEDS, "Needs"],
		[PERCEPTION, "Perception"],
		[SENSORY_EMITTER, "SensoryEmitter"],
		[INVENTORY, "Inventory"],
		[CONTAINER, "Container"],
		[JOB, "Job"],
		[SCHEDULE, "Schedule"],
		[PROFESSION, "Profession"],
		[SOCIAL_IDENTITY, "SocialIdentity"],
		[OWNERSHIP, "Ownership"],
		[MEMORY, "Memory"],
		[EPHEMERAL, "Ephemeral"],
		[LOD, "LoD"],
		[MATERIALIZATION, "Materialization"],
		[PLAYER_INPUT, "PlayerInput"],
		[HEAT_SOURCE, "HeatSource"],
		[LOOSE_ITEM, "LooseItem"],
		[MIND, "Mind"],
		[FACTION_CORE, "FactionCore"],
		[LOCOMOTION, "Locomotion"],
	]:
		if mask & int(entry[0]) != 0:
			names.append(String(entry[1]))
	if names.is_empty():
		return "<none>"
	return ", ".join(names)
