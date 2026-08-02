## The ONE shared transient primitive: noise events, alert auras, bard morale auras, and
## Sprint 4 magic effects all use this (entity_behavior section 6).
##
## TTL cleanup is mandatory. An ephemeral that never expires is a leak with a radius.
##
## SPRINT 4 ADDS MOTION AND A PAYLOAD, and deliberately adds them HERE rather than giving magic
## its own entity type. A fireball is an alert aura that moves and carries a catalyst; building a
## second transient with its own lifetime rules would give the build two places to forget the TTL
## sweep, and the TTL sweep is the only thing standing between magic and an unbounded entity leak.
##
## Projectiles do NOT go through CollisionResolveSystem. That system slides a body along a wall
## and steps it up a ledge, which is right for a person and wrong for a fireball — a spell that
## slid along the wall it was aimed at would never detonate. `EphemeralSystem` advances them and
## detonates on the first thing they touch.
class_name EphemeralComponent
extends RefCounted

var time_to_live: float = 1.0
var source_entity: int = EH.INVALID
## Expanding radius in metres. 0 means a point event.
var radius_m: float = 0.0
var expansion_mps: float = 0.0
## Tags applied to entities the aura overlaps, via the SpatialHash.
var applies_tags: Array[StringName] = []
## Tags stripped from those same entities. A spell that dries you off needs this.
var removes_tags: Array[StringName] = []
## Surface energy delivered on contact, in joules (review H2 — energy over mass, never a flat
## temperature).
var energy_j: float = 0.0

## Metres per second along `heading`. Zero for a stationary aura.
var speed_mps: float = 0.0
var heading: Vector3 = Vector3.ZERO

## THE TRIGGER DECIDES WHEN, THE SHAPE DECIDES WHERE. Keeping them separate is what makes the
## magic doc's examples composable: the trap is a proximity trigger on an aura, the fireball is
## an impact trigger on a projectile, and a smoke cloud is On_Cast on the same aura as the trap.
## A single `detonates` boolean could not express the timer or the mine.
var trigger: StringName = &"On_Cast"
## Seconds an On_Timer spell still has to wait. Counted down by the system.
var arm_after_s: float = 0.0
## Half-angle of a Cone in degrees, measured from `heading`. 0 means spherical.
var cone_angle_deg: float = 0.0
## True once the payload has gone off, so a one-shot cannot fire twice in the frame it dies.
var spent: bool = false
## Radius of the detonation, which is not the same as the projectile's own contact radius.
var blast_radius_m: float = 0.0
var payload: Dictionary = {}


## Whether this fires once and dies, or applies continuously until it expires. Derived from the
## trigger rather than stored, so the two can never disagree.
func detonates() -> bool:
	return trigger != &"On_Cast"


func is_expired() -> bool:
	return time_to_live <= 0.0


func advance(delta: float) -> void:
	time_to_live -= delta
	radius_m += expansion_mps * delta
	arm_after_s -= delta


## Whether this ephemeral does anything to the entities it overlaps. An expanding radius with no
## payload is a noise event, and running the overlap query for it would be wasted work.
func has_payload() -> bool:
	return (
		not applies_tags.is_empty()
		or not removes_tags.is_empty()
		or not is_zero_approx(energy_j)
	)
