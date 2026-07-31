## TTL and aura application for the ONE shared transient primitive.
##
## Noise events, [Alert] auras, bard morale auras, and Sprint 4 magic effects all flow through
## here. TTL cleanup is mandatory: an ephemeral that never expires is a leak with a radius.
class_name EphemeralSystem
extends RefCounted

var active: int = 0
var expired: int = 0
var tags_applied: int = 0


func run(delta: float, hash: SpatialHash) -> void:
	active = 0
	expired = 0
	tags_applied = 0
	var rows: PackedInt32Array = ECSManager.query(ComponentMask.EPHEMERAL)
	var doomed: PackedInt32Array = PackedInt32Array()

	for i in rows.size():
		var row: int = rows[i]
		var ephemeral: EphemeralComponent = ECSManager.ephemerals[row]
		ephemeral.advance(delta)
		if ephemeral.is_expired():
			doomed.append(row)
			continue
		active += 1
		if ephemeral.radius_m > 0.0 and not ephemeral.applies_tags.is_empty():
			_apply_aura(row, ephemeral, hash)

	for i in doomed.size():
		expired += 1
		ECSManager.destroy_entity(ECSManager.handle_of(doomed[i]))


func _apply_aura(row: int, ephemeral: EphemeralComponent, hash: SpatialHash) -> void:
	var centre: Vector3 = ECSManager.position_of(row)
	var overlapped: PackedInt32Array = hash.query_radius(centre, ephemeral.radius_m)
	for i in overlapped.size():
		var other: int = overlapped[i]
		if other == row:
			continue
		var chemistry: ChemistryComponent = ECSManager.chemistries.get(other)
		if chemistry == null:
			continue
		for tag in ephemeral.applies_tags:
			if chemistry.add_tag(tag):
				tags_applied += 1


## Spawns a noise event at a location. This is how an unseen impact produces INVESTIGATE rather
## than omniscient combat.
static func spawn_noise(position: Vector3, radius_m: float, ttl: float, source: int) -> int:
	var handle: int = ECSManager.allocate_entity()
	var row: int = EH.index_of(handle)
	ECSManager.set_position(row, position)
	ECSManager.add_component_bit(row, ComponentMask.POSITION)

	var ephemeral := EphemeralComponent.new()
	ephemeral.time_to_live = ttl
	ephemeral.source_entity = source
	ECSManager.ephemerals[row] = ephemeral
	ECSManager.add_component_bit(row, ComponentMask.EPHEMERAL)

	var emitter := SensoryEmitterComponent.new()
	emitter.noise_radius_m = radius_m
	ECSManager.emitters[row] = emitter
	ECSManager.add_component_bit(row, ComponentMask.SENSORY_EMITTER)
	return handle


## Spawns an expanding tag-applying aura. Bard morale, guard alerts, and magic all use this.
static func spawn_aura(
	position: Vector3, tags: Array[StringName], radius_m: float, ttl: float, source: int
) -> int:
	var handle: int = ECSManager.allocate_entity()
	var row: int = EH.index_of(handle)
	ECSManager.set_position(row, position)
	ECSManager.add_component_bit(row, ComponentMask.POSITION)

	var ephemeral := EphemeralComponent.new()
	ephemeral.time_to_live = ttl
	ephemeral.radius_m = radius_m
	ephemeral.applies_tags = tags
	ephemeral.source_entity = source
	ECSManager.ephemerals[row] = ephemeral
	ECSManager.add_component_bit(row, ComponentMask.EPHEMERAL)
	return handle


func counters() -> Dictionary:
	return {"ephemerals_active": active, "ephemerals_expired": expired, "aura_tags": tags_applied}
