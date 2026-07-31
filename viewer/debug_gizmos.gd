## Wireframe overlays for the things the rules use but the screen never showed: which way you are
## facing, how far your swing reaches, how wide its arc is, and how far you can interact.
##
## Every number drawn here is READ from the systems that enforce it — `PickSystem.MELEE_REACH_M`,
## `INTERACT_DIST_M`, the 60-degree half-arc — so a gizmo can never disagree with the rule. Drawing
## hard-coded copies would produce a diagram that is reassuring and wrong.
##
## Pure viewer. Reads ECS state, writes none. Toggled with `G`.
class_name DebugGizmos
extends Node3D

## Drawn just above the floor so the lines are not swallowed by the terrain mesh.
const GROUND_LIFT_M: float = 0.05

## Segments per arc. 24 is smooth enough at these radii and costs nothing.
const ARC_SEGMENTS: int = 24

## The melee test rejects anything more than 60 degrees off the swing vector, which is the
## 120-degree arc the roadmap describes. Kept beside the drawing that depends on it.
const MELEE_HALF_ARC_DEG: float = 60.0

const COLOUR_FACING := Color(1.0, 0.95, 0.3)
const COLOUR_MELEE := Color(1.0, 0.35, 0.3, 0.9)
const COLOUR_INTERACT := Color(0.4, 0.9, 1.0, 0.9)
const COLOUR_SIGHT := Color(0.6, 0.5, 1.0, 0.7)

@export var input_bridge_path: NodePath

var _mesh: ImmediateMesh = null
var _bridge: PlayerInputBridge = null


func _ready() -> void:
	_mesh = ImmediateMesh.new()
	var instance := MeshInstance3D.new()
	instance.mesh = _mesh
	# Unshaded and depth-test-disabled: a debug gizmo that is hidden behind the floor it describes
	# is worse than no gizmo, because you cannot tell "off" from "occluded".
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	instance.material_override = material
	add_child(instance)

	if not input_bridge_path.is_empty():
		_bridge = get_node_or_null(input_bridge_path)
	visible = DebugFlags.gizmos_enabled


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_gizmos"):
		visible = not visible
		DebugFlags.gizmos_enabled = visible
		DebugFlags.save_config()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	_mesh.clear_surfaces()
	if not visible or not World.booted:
		return
	var row: int = ECSManager.resolve(ECSManager.player_handle())
	if row < 0:
		return

	var origin: Vector3 = ECSManager.position_of(row)
	origin.y -= _half_height(row)
	origin.y += GROUND_LIFT_M
	var aim: Vector3 = _aim()

	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_draw_circle(origin, PickSystem.INTERACT_DIST_M, COLOUR_INTERACT)
	_draw_wedge(origin, aim, PickSystem.MELEE_REACH_M, MELEE_HALF_ARC_DEG, COLOUR_MELEE)
	_draw_facing(origin, aim)
	_draw_sight(row, origin, aim)
	_mesh.surface_end()


## An arrow, because "which way am I pointing" had no answer on screen at all — the player is a
## featureless box and the aim vector lives only in the input bridge.
func _draw_facing(origin: Vector3, aim: Vector3) -> void:
	var tip: Vector3 = origin + aim * (PickSystem.MELEE_REACH_M + 0.6)
	_line(origin, tip, COLOUR_FACING)
	var back: Vector3 = tip - aim * 0.4
	var side: Vector3 = aim.cross(Vector3.UP).normalized() * 0.25
	_line(tip, back + side, COLOUR_FACING)
	_line(tip, back - side, COLOUR_FACING)


## Perception radius, drawn only when the entity actually has a PerceptionComponent, so an
## absent sense is visibly absent rather than silently assumed.
func _draw_sight(row: int, origin: Vector3, _aim: Vector3) -> void:
	var perception: PerceptionComponent = ECSManager.perceptions.get(row)
	if perception == null:
		return
	_draw_circle(origin, perception.sight_range_m, COLOUR_SIGHT)


func _draw_wedge(
	origin: Vector3, aim: Vector3, radius: float, half_arc_deg: float, colour: Color
) -> void:
	var base: float = atan2(aim.z, aim.x)
	var half: float = deg_to_rad(half_arc_deg)
	var previous: Vector3 = _on_arc(origin, base - half, radius)
	_line(origin, previous, colour)
	for step in ARC_SEGMENTS:
		var t: float = float(step + 1) / float(ARC_SEGMENTS)
		var point: Vector3 = _on_arc(origin, base - half + 2.0 * half * t, radius)
		_line(previous, point, colour)
		previous = point
	_line(origin, previous, colour)


func _draw_circle(origin: Vector3, radius: float, colour: Color) -> void:
	var previous: Vector3 = _on_arc(origin, 0.0, radius)
	for step in ARC_SEGMENTS:
		var angle: float = TAU * float(step + 1) / float(ARC_SEGMENTS)
		var point: Vector3 = _on_arc(origin, angle, radius)
		_line(previous, point, colour)
		previous = point


func _on_arc(origin: Vector3, angle: float, radius: float) -> Vector3:
	return origin + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)


func _line(from: Vector3, to: Vector3, colour: Color) -> void:
	_mesh.surface_set_color(colour)
	_mesh.surface_add_vertex(from)
	_mesh.surface_set_color(colour)
	_mesh.surface_add_vertex(to)


func _aim() -> Vector3:
	if _bridge != null and _bridge.last_aim.length() > 0.01:
		return _bridge.last_aim.normalized()
	return Vector3(0.0, 0.0, 1.0)


func _half_height(row: int) -> float:
	var bounds: BoundsComponent = ECSManager.bounds.get(row)
	return 0.0 if bounds == null else bounds.half_extents.y
