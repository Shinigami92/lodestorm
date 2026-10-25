@tool
class_name NeonSign
extends Node3D
## A sign aboard like bent neon tubes on a dark backing (docs/planned/ship-interior.md): a room's
## name in its accent color on its wall, or a guide in amber with an arrow. The text is translated
## (Label3D) and the backing grows with it; a faint light throws the color on the wall. Faces +z
## (its wall behind it).

enum Arrow { NONE, LEFT, RIGHT, UP, DOWN }

const FONT: FontFile = preload("res://assets/fonts/tilt_neon/TiltNeon.ttf")
const PIXEL_SIZE: float = 0.01
const MARGIN: float = 0.12
const ARROW_LENGTH: float = 0.6
const TUBE: float = 0.035
const BACKING_COLOR := Color(0.035, 0.035, 0.04)

@export var text: String = "":
	set(value):
		text = value
		_rebuild()
@export var color: Color = Color(1.0, 0.6, 0.16):
	set(value):
		color = value
		_rebuild()
## Letter height in pixels of `PIXEL_SIZE` m.
@export var font_size: int = 48:
	set(value):
		font_size = value
		_rebuild()
@export var arrow: Arrow = Arrow.NONE:
	set(value):
		arrow = value
		_rebuild()
## Now and then dims for a moment, like an old tube.
@export var flickers: bool = false
## How bright the tubes are (above the environment's glow threshold, so they glow).
@export var energy: float = 2.6

var _label: Label3D
var _parts: Node3D
var _flicker_wait: float = 0.0
var _flicker_left: float = 0.0


func _ready() -> void:
	_rebuild.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_rebuild.call_deferred()


func _process(delta: float) -> void:
	if not flickers or Engine.is_editor_hint() or not _label:
		return
	if _flicker_left > 0.0:
		_flicker_left -= delta
		_label.modulate.a = 0.35 if fmod(_flicker_left, 0.1) < 0.05 else 1.0
		if _flicker_left <= 0.0:
			_label.modulate.a = 1.0
		return
	_flicker_wait -= delta
	if _flicker_wait <= 0.0:
		_flicker_wait = randf_range(4.0, 12.0)
		_flicker_left = randf_range(0.15, 0.4)


## The sign's width in meters (text, arrow and margins).
func get_width() -> float:
	return _text_width() + (_arrow_space() if arrow != Arrow.NONE else 0.0) + 2.0 * MARGIN


func _text_width() -> float:
	if text.is_empty():
		return 0.0
	return FONT.get_string_size(tr(text), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x * PIXEL_SIZE


func _arrow_space() -> float:
	return ARROW_LENGTH * 0.6 + (0.15 if not text.is_empty() else 0.0)


func _rebuild() -> void:
	if not is_node_ready():
		return
	if _parts:
		_parts.free()
	_parts = Node3D.new()
	_parts.name = "Parts"
	add_child(_parts, false, INTERNAL_MODE_FRONT)
	var tube := Color(color.r, color.g, color.b) * energy
	var height: float = maxf(font_size * PIXEL_SIZE * 0.85, ARROW_LENGTH * 0.6) + 2.0 * MARGIN
	var width: float = get_width()
	var backing := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, height, 0.05)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = BACKING_COLOR
	dark.metallic = 0.5
	dark.roughness = 0.5
	box.material = dark
	backing.mesh = box
	backing.position.z = -0.025
	_parts.add_child(backing)
	var left: float = -width / 2.0 + MARGIN
	_label = Label3D.new()
	_label.text = text
	_label.font = FONT
	_label.font_size = font_size
	_label.pixel_size = PIXEL_SIZE
	_label.modulate = tube
	_label.outline_size = maxi(4, roundi(font_size / 6.0))
	_label.outline_modulate = Color(tube.r * 0.6, tube.g * 0.6, tube.b * 0.6, 0.7)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_label.position = Vector3(left, 0.0, 0.03)
	_label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_label.layers = RenderLayers.EFFECTS
	_parts.add_child(_label)
	if arrow != Arrow.NONE:
		var at := Vector3(width / 2.0 - MARGIN - ARROW_LENGTH * 0.3, 0.0, 0.04)
		if text.is_empty():
			at.x = 0.0
		_add_arrow(at, tube)
	var glow := OmniLight3D.new()
	glow.light_color = Color(color.r, color.g, color.b)
	glow.light_energy = 0.5
	glow.omni_range = maxf(2.0, width)
	glow.position = Vector3(0.0, 0.0, 0.4)
	_parts.add_child(glow)


func _add_arrow(at: Vector3, tube: Color) -> void:
	var angle: float = 0.0
	match arrow:
		Arrow.LEFT:
			angle = PI
		Arrow.UP:
			angle = PI / 2.0
		Arrow.DOWN:
			angle = -PI / 2.0
	var glowing := StandardMaterial3D.new()
	glowing.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glowing.albedo_color = tube
	var length: float = ARROW_LENGTH * 0.6
	var pieces: Array[Array] = [
		[Vector3(0, 0, 0), length, 0.0],
		[Vector3(length / 2.0 - 0.106, 0.106, 0), 0.3, PI * 0.75],
		[Vector3(length / 2.0 - 0.106, -0.106, 0), 0.3, -PI * 0.75],
	]
	var turn := Basis(Vector3.BACK, angle)
	for piece: Array in pieces:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(piece[1] as float, TUBE, TUBE)
		box.material = glowing
		mesh.mesh = box
		var offset: Vector3 = piece[0]
		mesh.transform = Transform3D(
			turn * Basis(Vector3.BACK, piece[2] as float), at + turn * offset
		)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.layers = RenderLayers.EFFECTS
		_parts.add_child(mesh)
