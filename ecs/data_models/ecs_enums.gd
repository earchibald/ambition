## Canonical ECS enumerations.
##
## Every enum in `docs/component_and_field_registry.md` §3 lives here and ONLY here.
## Enums are never represented as strings (ADR-13).
##
## This is a `class_name` holder because a bare `enum` in a script without `class_name`
## is unreachable from other files. Access as `ECSEnums.Phase.SOLID`.
class_name ECSEnums
extends RefCounted

enum Phase { SOLID, LIQUID, GAS }

enum LoD { ACTIVE, SIMULATED, ABSTRACTED }

enum Quality { PRISTINE, CHIPPED, RUINED, SCRAP }

enum RelationshipStatus { WAR, NEUTRAL, TRADE, ALLIED }

enum JobStatus { OPEN, CLAIMED, IN_PROGRESS, DONE, ABORTED }

enum Objective { FORTIFY, RAID_FACTION, GATHER_RESOURCES, MIGRATE, IDLE }

enum Emotion { CALM, FEARFUL, AGGRESSIVE, DESPERATE }

enum AwarenessState { UNAWARE, SUSPICIOUS, INVESTIGATING, COMBAT }

## History graph vocabulary (DAG spec §2). The DAG is generated before the world exists and is
## the only source of "why is this here", so its node and edge kinds are canonical enums like
## everything else — never strings.
enum NodeType { FACTION, LEADER, LOCATION, ARTIFACT, EVENT_ABSTRACT }

## DESTROYED nodes are RETAINED, never deleted. A conquered faction is the reason its conqueror
## holds that territory, and erasing it erases the explanation.
enum NodeStatus { ACTIVE, DESTROYED, DORMANT }

enum EdgeType { FOUNDED, DESTROYED, CONQUERED, MIGRATED_TO, FORGED, ALLIED_WITH }

enum MaterializationPolicy {
	LEDGERIZE,
	PRESERVE_ENTITY,
	CONTAINER_MANIFEST,
	CARAVAN_MANIFEST,
	GC_ELIGIBLE,
}


## Derived `Quality` band from the authoritative `wear` float (registry §5).
## Degradation always writes `wear`; `condition` is never set independently.
static func quality_from_wear(wear: float) -> Quality:
	if wear < 25.0:
		return Quality.PRISTINE
	if wear < 50.0:
		return Quality.CHIPPED
	if wear < 85.0:
		return Quality.RUINED
	return Quality.SCRAP
