## Read-only observability surface (debugging spec section 9, Sprint 1 deliverable).
##
## Reads ECS state and NEVER mutates it. The UI is a dumb listener.
##
## Without an entity inspector every bug is a print-statement expedition, so the inspector is the
## highest-value item here, and it selects THROUGH PickSystem so it dogfoods the pick path.
class_name DebugOverlay
extends CanvasLayer

const REFRESH_INTERVAL_S: float = 0.25

var _label: Label = null
var _selected_row: int = -1
var _accumulator: float = 0.0


func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(12, 12)
	_label.add_theme_font_size_override("font_size", 13)
	add_child(_label)
	visible = DebugFlags.tick_counters_enabled


func _process(delta: float) -> void:
	if not visible:
		return
	_accumulator += delta
	if _accumulator < REFRESH_INTERVAL_S:
		return
	_accumulator = 0.0
	_label.text = _compose()


func _compose() -> String:
	var counters: Dictionary = GameLoopManager.counters()
	var lines: Array[String] = []
	lines.append("%s  |  scenario %s" % [counters["clock"], World.scenario])
	lines.append(_player_location())
	lines.append(_cursor_location())
	lines.append(
		"micro %.2fms / %.1fms budget%s   sim %.2fms   fluid %.2fms   spatial %.2fms" % [
			counters["last_micro_ms"],
			counters["micro_budget_ms"],
			"  << OVER" if counters["over_micro_budget"] else "",
			counters["last_sim_ms"],
			counters["last_fluid_ms"],
			counters["last_spatial_ms"],
		]
	)
	lines.append(
		"entities alive %d (active %d / cap %d)   rows %d   free %d" % [
			counters["alive_count"],
			counters.get("lod_active_entities", 0),
			WorldConstants.ACTIVE_ENTITY_HARD_CAP,
			counters["row_capacity"],
			counters["free_rows"],
		]
	)
	lines.append(
		"movers %d  substeps %d  tile-hits %d  entity-hits %d" % [
			counters.get("movers_processed", 0),
			counters.get("substeps_run", 0),
			counters.get("tile_collisions", 0),
			counters.get("entity_collisions", 0),
		]
	)
	lines.append(
		"CA updates %d  dirty %d%s   pumped %d" % [
			counters.get("ca_cell_updates", 0),
			counters.get("ca_dirty_cells", 0),
			"  << BUDGET" if counters.get("ca_budget_exhausted", false) else "",
			counters.get("ca_pumped_units", 0),
		]
	)
	lines.append(
		"LoS marches %d (cache %d, fail %d)  perceived %d  witnesses %d" % [
			counters.get("los_marches", 0),
			counters.get("los_cache_hits", 0),
			counters.get("los_failures", 0),
			counters.get("targets_perceived", 0),
			counters.get("witness_events", 0),
		]
	)
	lines.append(
		"stale-handle rejections %d   destroys %d   query rebuilds %d" % [
			counters["stale_handle_rejections"],
			counters["destroy_count"],
			counters["query_cache_rebuilds"],
		]
	)
	if _selected_row >= 0:
		lines.append("")
		lines.append(_inspect(_selected_row))
	return "\n".join(lines)


## Selects an entity for inspection. Called by the input bridge via PickSystem.
func select_row(row: int) -> void:
	_selected_row = row


## Where the player is, in BOTH coordinate systems. Every arena feature is specified in tile
## coordinates (`ecs/world/test_arena.gd`, and the table in RUNNING.md), but the ECS stores
## metres — so without this line neither number can be checked against the other, and "walk to
## the ledge and confirm the step rule" is not a runnable instruction.
func _player_location() -> String:
	var row: int = ECSManager.resolve(ECSManager.player_handle())
	if row < 0:
		return "you: <no player entity>"
	var pos: Vector3 = ECSManager.position_of(row)
	var chunk: ChunkData = World.active_chunk
	if chunk == null:
		return "you: world (%.2f, %.2f, %.2f)   <no active chunk>" % [pos.x, pos.y, pos.z]
	var tile: Vector2i = chunk.world_to_tile(pos)
	return "you: tile %s   world (%.2f, %.2f, %.2f)   %s" % [
		_format_tile(tile), pos.x, pos.y, pos.z, _tile_readout(chunk, tile)
	]


## The tile under the mouse, so the arena map can be checked without walking the whole grid.
##
## Derived from the camera ray against the y=0 GROUND PLANE, not from PickSystem: the DDA march
## only registers a hit on SOLID tiles, so over open floor it correctly returns no tile at all.
## On the raised ledge and in the pit this therefore reads one tile or two off — labelled below
## rather than silently wrong.
func _cursor_location() -> String:
	var chunk: ChunkData = World.active_chunk
	var camera: Camera3D = get_viewport().get_camera_3d()
	if chunk == null or camera == null:
		return "cursor: <no camera>"
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var origin: Vector3 = camera.project_ray_origin(mouse)
	var direction: Vector3 = camera.project_ray_normal(mouse)
	if absf(direction.y) < 0.0001:
		return "cursor: <ray parallel to ground>"
	var distance: float = -origin.y / direction.y
	if distance < 0.0:
		return "cursor: <pointing at the sky>"
	var tile: Vector2i = chunk.world_to_tile(origin + direction * distance)
	return "cursor (ground plane): tile %s   %s" % [
		_format_tile(tile), _tile_readout(chunk, tile)
	]


## Kind, elevation and fluid for one tile. Elevation is what the step-up and drop rules read,
## and fluid is what the CA moves, so these are the two numbers worth seeing while walking.
func _tile_readout(chunk: ChunkData, tile: Vector2i) -> String:
	if not _in_chunk(tile):
		return "<outside chunk>"
	var units: int = chunk.fluid_at(tile.x, tile.y)
	return "%s  elev %+.2fm  fluid %d" % [
		"SOLID" if chunk.is_solid(tile.x, tile.y) else "open",
		chunk.height_at(tile.x, tile.y),
		units,
	]


func _in_chunk(tile: Vector2i) -> bool:
	return (
		tile.x >= 0
		and tile.y >= 0
		and tile.x < WorldConstants.CHUNK_TILES
		and tile.y < WorldConstants.CHUNK_TILES
	)


func _format_tile(tile: Vector2i) -> String:
	return "(%d, %d)" % [tile.x, tile.y]


## "Why did this entity do that?" — the explainability record.
func _inspect(row: int) -> String:
	var handle: int = ECSManager.handle_of(row)
	if not EH.is_valid(handle):
		return "inspector: <stale row %d>" % row
	var lines: Array[String] = []
	lines.append("--- %s ---" % EH.to_debug_string(handle))
	lines.append("components: %s" % ComponentMask.describe(ECSManager.mask_of(row)))
	var pos: Vector3 = ECSManager.position_of(row)
	var chunk: ChunkData = World.active_chunk
	var tile_text: String = ""
	if chunk != null:
		tile_text = "  tile %s" % _format_tile(chunk.world_to_tile(pos))
	lines.append("pos %v%s   vel %v" % [pos, tile_text, ECSManager.velocity_of(row)])

	var body: BodyComponent = ECSManager.bodies.get(row)
	if body != null:
		lines.append(
			"health %.1f/%.1f  stamina %.1f  strength %.1f" % [
				body.health, body.max_health, body.stamina, body.strength
			]
		)
	var need: NeedsComponent = ECSManager.needs.get(row)
	if need != null:
		lines.append(
			"hunger %.1f  energy %.1f  morale %.1f" % [need.hunger, need.energy, need.morale]
		)
	var physical: PhysicalPropertyComponent = ECSManager.physicals.get(row)
	if physical != null:
		lines.append(
			"mass %.3fkg  vol %.0fcm3  temp %.1fC  phase %d  qty %d" % [
				physical.mass_kg,
				physical.volume_cm3,
				physical.temperature_c(),
				physical.phase,
				physical.quantity,
			]
		)
	var chemistry: ChemistryComponent = ECSManager.chemistries.get(row)
	if chemistry != null and not chemistry.active_tags.is_empty():
		lines.append("tags: %s" % ", ".join(chemistry.active_tags))
	var perception: PerceptionComponent = ECSManager.perceptions.get(row)
	if perception != null:
		lines.append(
			"awareness %d  known targets %d" % [
				perception.awareness_state, perception.last_known_targets.size()
			]
		)
	var job: JobComponent = ECSManager.jobs.get(row)
	if job != null:
		lines.append(
			"job %s  status %d  score %.2f" % [job.current_action, job.status, job.score_at_claim]
		)
	return "\n".join(lines)
