class_name Hose
extends MeshInstance3D
## A tube that sags between two points in world space and rests on the ground where it would
## sink below it. Greybox: rebuilt as a simple mesh each frame while visible.

const SEGMENTS: int = 16
const SIDES: int = 6
## Two triangles per quad, as (ring, side) offsets from the quad's first corner.
const QUAD_CORNERS: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 0), Vector2i(1, 1), Vector2i(0, 1)
]

@export var radius: float = 0.06
## How far the middle sags below the straight line, relative to the hose length.
@export var sag: float = 0.25

var _mesh := ImmediateMesh.new()


func _ready() -> void:
	# The hose is built in world space, whatever its parent does.
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _mesh


## Rebuilds the tube from `from` to `to`; no point of it goes below `floor_y`.
func build(from: Vector3, to: Vector3, floor_y: float) -> void:
	var control: Vector3 = (from + to) * 0.5 + Vector3.DOWN * sag * 2.0 * from.distance_to(to)
	var rings: Array[PackedVector3Array] = []
	var normals: Array[PackedVector3Array] = []
	for i: int in SEGMENTS + 1:
		var t: float = float(i) / SEGMENTS
		var center: Vector3 = from.lerp(control, t).lerp(control.lerp(to, t), t)
		center.y = maxf(center.y, floor_y + radius)
		var tangent: Vector3 = (control - from).lerp(to - control, t)
		var side: Vector3 = tangent.cross(Vector3.UP)
		if side.length_squared() < 0.0001:
			side = Vector3.RIGHT
		side = side.normalized()
		var up: Vector3 = side.cross(tangent).normalized()
		var ring := PackedVector3Array()
		var ring_normals := PackedVector3Array()
		for j: int in SIDES:
			var angle: float = TAU * j / SIDES
			var normal: Vector3 = side * cos(angle) + up * sin(angle)
			ring.append(center + normal * radius)
			ring_normals.append(normal)
		rings.append(ring)
		normals.append(ring_normals)

	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in SEGMENTS:
		for j: int in SIDES:
			for corner: Vector2i in QUAD_CORNERS:
				var ring: int = i + corner.x
				var side: int = (j + corner.y) % SIDES
				_mesh.surface_set_normal(normals[ring][side])
				_mesh.surface_add_vertex(rings[ring][side])
	_mesh.surface_end()
