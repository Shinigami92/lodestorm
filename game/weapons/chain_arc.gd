class_name ChainArc
extends Node3D
## Fulgen's lightning (see `ChainDelivery`): a jagged bolt along the points an attack passed (the
## muzzle, then every alien it jumped to), flickering into a new shape every frame and fading within
## `DURATION`, with a flash of light at the muzzle. A child named `Arc` of the weapon's scene;
## teammates see it too. Greybox until the art pass.

## Seconds a bolt lasts.
const DURATION: float = 0.14
## Pieces per link between two points, and how far a piece's joint strays from the straight line,
## as a share of the link's length (at most `MAX_JAG` m).
const PIECES: int = 7
const JAG: float = 0.12
const MAX_JAG: float = 0.45

## The bolt's color and thickness (m).
@export var color := Color(1.0, 0.86, 0.66)
@export var width: float = 0.05
@export var light_energy: float = 3.0

var _points := PackedVector3Array()
var _left: float = 0.0
var _bolt: MultiMeshInstance3D
var _light: OmniLight3D
var _material := StandardMaterial3D.new()


func _ready() -> void:
	# Made here, not with the node: a weapon freed without entering the tree would leak them.
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	box.material = _material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = box
	_bolt = MultiMeshInstance3D.new()
	_bolt.multimesh = multimesh
	_bolt.top_level = true
	_bolt.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bolt.visible = false
	add_child(_bolt)
	_light = OmniLight3D.new()
	_light.light_color = color
	_light.omni_range = 6.0
	_light.light_energy = 0.0
	add_child(_light)


func _process(delta: float) -> void:
	_left = maxf(_left - delta, 0.0)
	var on: bool = _left > 0.0 and _points.size() >= 2 and is_visible_in_tree()
	_bolt.visible = on
	_light.light_energy = light_energy * _left / DURATION if on else 0.0
	if on:
		_shape()


## Shows a bolt through `points` (global: the muzzle first).
func strike(points: PackedVector3Array) -> void:
	_points = points
	_left = DURATION
	_bolt.global_transform = Transform3D.IDENTITY
	_shape()


## Lays out the bolt's pieces anew, jagged at random, and fades it.
func _shape() -> void:
	var multimesh: MultiMesh = _bolt.multimesh
	var count: int = (_points.size() - 1) * PIECES
	if multimesh.instance_count != count:
		multimesh.instance_count = count
	var index: int = 0
	for link: int in _points.size() - 1:
		var from: Vector3 = _points[link]
		var to: Vector3 = _points[link + 1]
		var jag: float = minf(from.distance_to(to) * JAG, MAX_JAG)
		var previous: Vector3 = from
		for piece: int in PIECES:
			var t: float = float(piece + 1) / PIECES
			var next: Vector3 = from.lerp(to, t)
			if piece < PIECES - 1:
				next += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * jag
			multimesh.set_instance_transform(index, _piece(previous, next))
			previous = next
			index += 1
	var glow: Color = color * 2.5
	glow.a = clampf(_left / DURATION, 0.0, 1.0) * randf_range(0.7, 1.0)
	_material.albedo_color = glow


## A box stretched from `from` to `to`.
func _piece(from: Vector3, to: Vector3) -> Transform3D:
	var length: float = maxf(from.distance_to(to), 0.001)
	var direction: Vector3 = (to - from) / length
	var up: Vector3 = Vector3.UP if absf(direction.y) < 0.99 else Vector3.RIGHT
	return Transform3D(
		Basis.looking_at(direction, up).scaled_local(Vector3(width, width, length)),
		from.lerp(to, 0.5)
	)
