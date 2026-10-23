class_name ScreamWave
extends Node3D
## A shrieker's scream sweeping over the ground (`AlienScream`): a ring in the hive's yellow-green
## that grows from the shrieker to the scream's reach and fades, so players see which aliens it
## reached. Greybox look, TBD (playtest).

## Seconds the ring takes to reach its full size.
const DURATION: float = 0.6
## Width of the ring (m).
const WIDTH: float = 0.35

var radius: float = 15.0

var _elapsed: float = 0.0
var _material := StandardMaterial3D.new()
var _ring: MeshInstance3D


## A wave at `point` (global) in `parent`, reaching `reach` m.
static func spawn(parent: Node, point: Vector3, reach: float) -> ScreamWave:
	var wave := ScreamWave.new()
	wave.radius = reach
	parent.add_child(wave)
	wave.global_transform = Transform3D(Basis.IDENTITY, point)
	return wave


func _ready() -> void:
	_material.albedo_color = Color(Alien.COLOR_GLOW, 0.8)
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var torus := TorusMesh.new()
	torus.outer_radius = 1.0
	torus.inner_radius = 1.0 - WIDTH / radius
	torus.rings = 48
	torus.ring_segments = 4
	torus.material = _material
	_ring = MeshInstance3D.new()
	_ring.name = "Ring"
	_ring.mesh = torus
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.position.y = 0.15
	add_child(_ring)
	_update()
	RenderLayers.put(self, RenderLayers.EFFECTS)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= DURATION:
		queue_free()
		return
	_update()


func _update() -> void:
	var t: float = _elapsed / DURATION
	var size: float = lerpf(1.0, radius, 1.0 - (1.0 - t) * (1.0 - t))
	_ring.scale = Vector3(size, 0.4, size)
	_material.albedo_color.a = 0.8 * (1.0 - t)
