class_name TargetMarker
extends MeshInstance3D
## The target lock on the ground (a child of the player, see GAME_DESIGN.md, UI): four corner
## brackets around the alien or nest the player locked on (`PlayerAim.target`), in the player's
## color, sized to its body and kept square to the screen like the suit ring. Drawn over the
## ground and low plants, hidden by cliffs and props.

## Space between the alien's body and the brackets (m). TBD (playtest).
const MARGIN: float = 0.4
## The brackets' size for a target without a known body.
const DEFAULT_RADIUS: float = 0.5
const ALPHA: float = 0.95

var _material := ShaderMaterial.new()
var _plane := PlaneMesh.new()

@onready var _player: Player = get_parent() as Player


func _ready() -> void:
	top_level = true
	mesh = _plane
	_material.shader = preload("res://assets/shaders/target_brackets.gdshader")
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	layers = RenderLayers.MARKINGS
	visible = false


func _process(_delta: float) -> void:
	var target: Node3D = _player.aim.target
	visible = PlayerAim.is_lockable(target) and not _player.dead and _player.local
	if not visible:
		return
	var half_size: float = body_radius(target) + MARGIN
	var extent: float = half_size + 0.2
	_plane.size = Vector2.ONE * extent * 2.0
	_material.set_shader_parameter(&"extent", extent)
	_material.set_shader_parameter(&"half_size", half_size)
	_material.set_shader_parameter(&"arm", half_size * 0.4)
	_material.set_shader_parameter(&"color", Color(_player.color(), ALPHA))
	var camera: Camera3D = get_viewport().get_camera_3d()
	var forward := Vector3.FORWARD
	if camera:
		forward = -camera.global_basis.z
		forward.y = 0.0
	if forward.length() < 0.001:
		forward = Vector3.FORWARD
	global_transform = Transform3D(
		Basis.looking_at(forward.normalized(), Vector3.UP),
		target.global_position + Vector3.UP * 0.05
	)


## The radius of `target`'s body on the ground (its collision shape), in m.
static func body_radius(target: Node3D) -> float:
	var shape_node := target.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	var shape: Shape3D = shape_node.shape if shape_node else null
	if shape is CapsuleShape3D:
		return (shape as CapsuleShape3D).radius
	if shape is SphereShape3D:
		return (shape as SphereShape3D).radius
	if shape is CylinderShape3D:
		return (shape as CylinderShape3D).radius
	if shape is BoxShape3D:
		var size: Vector3 = (shape as BoxShape3D).size
		return maxf(size.x, size.z) * 0.5
	return DEFAULT_RADIUS
