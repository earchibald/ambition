## Read-only observability surface (debugging spec section 9, Sprint 1 deliverable).
##
## Reads ECS state and NEVER mutates it. The UI is a dumb listener.
##
## Without an entity inspector every bug is a print-statement expedition, so the inspector is the
## highest-value item here, and it selects THROUGH PickSystem so it dogfoods the pick path.
class_name DebugOverlay
extends CanvasLayer

const REFRESH_INTERVAL_S: float = 0.25

## How far the cursor ray is marched, and how finely. 0.25 m is a quarter tile, which is well
## under the smallest feature in the arena, and 240 samples at 4 Hz costs nothing.
const CURSOR_MAX_DIST_M: float = 60.0
const CURSOR_STEP_M: float = 0.25

## How many outcome events the feed keeps. Enough to see a fight, short enough to read.
const FEED_CAPACITY: int = 8

var _label: Label = null
var _selected_row: int = -1
var _accumulator: float = 0.0
var _feed: Array[String] = []
var _remembered_names: Dictionary = {}
var _lmb_presses: int = 0
var _rmb_presses: int = 0


func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(12, 12)
	# Dark outline: the overlay is drawn over a mid-grey stone floor, and unoutlined light text
	# on it is barely readable regardless of size.
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 6)
	_apply_font_size()
	add_child(_label)
	visible = DebugFlags.tick_counters_enabled

	# Listen only. The overlay never writes ECS state (Prime Directive / invariants §2).
	ECSEvents.entity_damaged.connect(_on_damaged)
	ECSEvents.entity_died.connect(_on_died)
	ECSEvents.item_taken.connect(_on_taken)
	ECSEvents.action_rejected.connect(_on_rejected)
	ECSEvents.entity_landed.connect(_on_landed)
	ECSEvents.faction_decided.connect(_on_faction_decided)


## Text size is adjustable at runtime, because "edit a JSON file in the user data directory and
## restart" is not a real answer to "I cannot read this".
func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_pressed():
		return
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.button_index == MOUSE_BUTTON_LEFT:
			_lmb_presses += 1
		elif button.button_index == MOUSE_BUTTON_RIGHT:
			_rmb_presses += 1
		return
	var delta: int = 0
	if event.is_action(&"overlay_text_bigger"):
		delta = 2
	elif event.is_action(&"overlay_text_smaller"):
		delta = -2
	if delta == 0:
		return
	DebugFlags.overlay_font_size = clampi(
		DebugFlags.overlay_font_size + delta,
		DebugFlags.MIN_OVERLAY_FONT_SIZE,
		DebugFlags.MAX_OVERLAY_FONT_SIZE
	)
	_apply_font_size()
	DebugFlags.save_config()
	get_viewport().set_input_as_handled()


func _apply_font_size() -> void:
	if _label == null:
		return
	_label.add_theme_font_size_override("font_size", DebugFlags.overlay_font_size)


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
	lines.append(_vitals())
	lines.append(_mouse_state())
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
	if not _feed.is_empty():
		lines.append("")
		lines.append("recent events (newest first):")
		for entry in _feed:
			lines.append("  " + entry)
	return "\n".join(lines)


## Health, stamina and airborne state. Fall damage was resolving correctly and reporting nowhere,
## so a 2.5 m drop and a 0.4 m step looked identical from the player's seat.
func _vitals() -> String:
	var row: int = ECSManager.resolve(ECSManager.player_handle())
	if row < 0:
		return "vitals: <no player>"
	var body: BodyComponent = ECSManager.bodies.get(row)
	if body == null:
		return "vitals: <no body>"
	var velocity: Vector3 = ECSManager.velocity_of(row)
	var state: String = "grounded"
	if velocity.y < -0.05:
		state = "FALLING %.1f m/s" % -velocity.y
	elif velocity.y > 0.05:
		state = "rising"
	return "vitals: health %.1f/%.1f   stamina %.1f   %s   (safe fall < %.0f m/s)" % [
		body.health, body.max_health, body.stamina, state, WorldConstants.SAFE_FALL_MPS
	]


## Raw mouse-button state. Requested during play-testing, and immediately useful: it separates
## "the click never registered" from "the click registered and the action was refused".
func _mouse_state() -> String:
	var left: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var right: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	return "mouse: LMB %s  RMB %s   attack-presses %d  interact-presses %d" % [
		"HELD" if left else "up",
		"HELD" if right else "up",
		_lmb_presses,
		_rmb_presses,
	]


## Newest-first ring of outcome events. Bounded, so a long session cannot grow it without limit.
func _remember(text: String) -> void:
	_feed.push_front("%s  %s" % [GameClock.to_display_string(), text])
	while _feed.size() > FEED_CAPACITY:
		_feed.pop_back()


func _on_damaged(entity: int, amount: float, remaining: float, cause: StringName) -> void:
	# Falls are reported by `_on_landed`, which knows the impact speed as well as the damage.
	# Reporting both would print two lines for one event.
	if cause == &"fall":
		return
	_remember(
		"%s took %.1f damage (%s), %.1f left"
		% [_name_of(entity), amount, cause, remaining]
	)


## A survivable fall is a RESULT, not an absence of one. Reporting only damaging landings made
## "I fell and nothing happened" indistinguishable from "the fall was never detected" — which is
## precisely how the fall system looked while it was genuinely broken.
func _on_landed(entity: int, speed_mps: float, damage: float) -> void:
	if damage > 0.0:
		_remember("%s landed at %.1f m/s — %.1f damage" % [_name_of(entity), speed_mps, damage])
		return
	_remember(
		"%s landed at %.1f m/s — unhurt (safe below %.0f)"
		% [_name_of(entity), speed_mps, WorldConstants.SAFE_FALL_MPS]
	)


func _on_died(entity: int, cause: StringName) -> void:
	_remember("%s DIED (%s)" % [_name_of(entity), cause])


func _on_taken(taker: int, item: int, _reason: StringName) -> void:
	_remember("%s picked up %s" % [_name_of(taker), _name_of(item)])


func _on_rejected(actor: int, action: StringName, reason: StringName) -> void:
	_remember("%s: %s refused — %s" % [_name_of(actor), action, reason])


## Factions talk. Without this the entire reasoning layer runs invisibly and the only evidence
## it exists at all is that NPCs occasionally walk somewhere different.
func _on_faction_decided(faction_id: int, objective: String, declaration: String) -> void:
	if declaration == "":
		_remember("faction %d -> %s" % [faction_id, objective])
		return
	_remember("faction %d -> %s: \"%s\"" % [faction_id, objective, declaration])


## A handle is not a name. Without this the feed reads "entity 4294967296 took 3.2 damage".
##
## Names are REMEMBERED, because the interesting events are exactly the ones that end an entity.
## A stack that merges on pickup is destroyed inside the operation that reports it, so resolving
## the handle afterwards yields nothing and the log read "you picked up <gone>". The last known
## name is the honest answer.
func _name_of(entity: int) -> String:
	var row: int = ECSManager.resolve(entity)
	if row < 0:
		return _remembered_names.get(EH.index_of(entity), "<gone>")
	var name: String = _describe(row)
	_remembered_names[row] = name
	return name


## What a thing IS, in words. Material and count first for items, because "618 x MAT_CLOTH" is
## the answer to "what is this" and a component list is not.
func _label_for(row: int) -> String:
	var chemistry: ChemistryComponent = ECSManager.chemistries.get(row)
	if chemistry != null and chemistry.active_tags.has(&"Corpse"):
		return "corpse"
	if row == 0:
		return "you"

	var policy: MaterializationComponent = ECSManager.materializations.get(row)
	if policy != null and policy.item_class == &"Citizen":
		return "villager"
	if ECSManager.has_components(row, ComponentMask.FACTION_CORE):
		return "faction ledger"
	if ECSManager.bodies.has(row):
		return "creature"
	return _describe_stack(row, policy)


## Items read as "618 x MAT_CLOTH (Commodity)" — the count and the material ARE the answer to
## "what is this", where a component list is not.
func _describe_stack(row: int, policy: MaterializationComponent) -> String:
	var physical: PhysicalPropertyComponent = ECSManager.physicals.get(row)
	var composition: MaterialCompositionComponent = ECSManager.materials.get(row)
	if physical == null or composition == null:
		return "object"
	var kind: String = ""
	if policy != null and policy.item_class != &"":
		kind = " (%s)" % policy.item_class
	return "%d x %s%s" % [physical.quantity, composition.dominant_material(), kind]


func _describe(row: int) -> String:
	if row == 0:
		return "you"
	var chemistry: ChemistryComponent = ECSManager.chemistries.get(row)
	if chemistry != null and chemistry.active_tags.has(&"Corpse"):
		return "corpse #%d" % row
	if ECSManager.bodies.has(row):
		return "creature #%d" % row
	return "item #%d" % row


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
	var chunk: ChunkData = World.chunk_containing(pos)
	if chunk == null:
		return "you: world (%.2f, %.2f, %.2f)   <no active chunk>" % [pos.x, pos.y, pos.z]
	var tile: Vector2i = chunk.world_to_tile(pos)
	return "you: tile %s   world (%.2f, %.2f, %.2f)   %s" % [
		_format_tile(tile), pos.x, pos.y, pos.z, _tile_readout(chunk, tile)
	]


## The tile under the mouse. This is a SURVEY tool: it answers "what is over there" for any tile
## on screen, with no walking involved. Walking is only needed to test the movement RULES, which
## are a separate question — see the two tables in RUNNING.md.
##
## Marched against the actual height map rather than intersected with the y=0 plane. A flat-plane
## approximation is wrong at exactly the two places worth inspecting — the raised ledge and the
## pit — because those are the only tiles whose elevation is not zero.
##
## Not routed through PickSystem: the DDA march registers a hit only on SOLID tiles, so over open
## floor it correctly reports nothing at all, which is useless for a terrain survey.
func _cursor_location() -> String:
	var chunk: ChunkData = World.active_chunk
	var camera: Camera3D = get_viewport().get_camera_3d()
	if chunk == null or camera == null:
		return "cursor: <no camera>"
	var tile: Vector2i = _cursor_tile(chunk, camera)
	if tile.x < 0:
		return "cursor: <not over the world>"
	var owner: ChunkData = World.chunk_containing(
		chunk.tile_to_world(tile.x, tile.y)
	) if World.grid == null else _owner_for(camera)
	return "cursor: tile %s   %s" % [
		_format_tile(tile), _tile_readout(owner if owner != null else chunk, tile)
	]


## The chunk under the cursor, so the readout describes the tile it names.
func _owner_for(camera: Camera3D) -> ChunkData:
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var hit: Dictionary = GameLoopManager.picking.ground_hit(
		camera.project_ray_origin(mouse), camera.project_ray_normal(mouse), World.sampler()
	)
	return null if not hit["hit"] else World.chunk_containing(hit["point"])


## Steps along the camera ray until it meets terrain: either the side of a solid tile, or the
## floor surface of an open one. Returns (-1, -1) if it leaves the chunk without hitting.
func _cursor_tile(_chunk: ChunkData, camera: Camera3D) -> Vector2i:
	var mouse: Vector2 = get_viewport().get_mouse_position()
	# Marched through the SAMPLER, so the readout stays correct across a chunk seam rather than
	# reporting "outside chunk" the moment the cursor leaves the player's own chunk.
	var hit: Dictionary = GameLoopManager.picking.ground_hit(
		camera.project_ray_origin(mouse), camera.project_ray_normal(mouse), World.sampler()
	)
	if not hit["hit"]:
		return Vector2i(-1, -1)
	var owner: ChunkData = World.chunk_containing(hit["point"])
	return Vector2i(-1, -1) if owner == null else owner.world_to_tile(hit["point"])


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
	# The handle SECOND. "e51:g1" told a play-tester nothing about what they were looking at, and
	# an inspector whose first line is an opaque id makes them work out the answer some other way.
	lines.append("--- %s  [%s] ---" % [_label_for(row), EH.to_debug_string(handle)])
	lines.append("components: %s" % ComponentMask.describe(ECSManager.mask_of(row)))
	var pos: Vector3 = ECSManager.position_of(row)
	var chunk: ChunkData = World.chunk_containing(pos)
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
			"mass %.3fkg  vol %.0fcm3  temp %.1fC  phase %s  qty %d" % [
				physical.mass_kg,
				physical.volume_cm3,
				physical.temperature_c(),
				_enum_name(ECSEnums.Phase, physical.phase),
				physical.quantity,
			]
		)
	var chemistry: ChemistryComponent = ECSManager.chemistries.get(row)
	if chemistry != null and not chemistry.active_tags.is_empty():
		lines.append("tags: %s" % ", ".join(chemistry.active_tags))
	var perception: PerceptionComponent = ECSManager.perceptions.get(row)
	if perception != null:
		lines.append(
			"awareness %s  known targets %d" % [
				_enum_name(ECSEnums.AwarenessState, perception.awareness_state),
				perception.last_known_targets.size(),
			]
		)
	var job: JobComponent = ECSManager.jobs.get(row)
	if job != null:
		lines.append(
			"job %s  status %s  score %.2f" % [
				job.current_action,
				_enum_name(ECSEnums.JobStatus, job.status),
				job.score_at_claim,
			]
		)
	var lod: LoDComponent = ECSManager.lods.get(row)
	if lod != null:
		lines.append("LoD %s" % _enum_name(ECSEnums.LoD, lod.current_state))
	return "\n".join(lines)


## Enums printed as raw integers are unreadable, and worse, they invite guesses: `awareness 0`
## was read during play-testing as the entity being asleep. It is UNAWARE, and there is no sleep
## state in Sprint 1 at all.
func _enum_name(enum_dict: Dictionary, value: int) -> String:
	for key in enum_dict:
		if enum_dict[key] == value:
			return "%s(%d)" % [key, value]
	return "UNKNOWN(%d)" % value
