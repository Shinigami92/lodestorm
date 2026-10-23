class_name FlameJet
extends WeaponStream
## Scald's flame (see `ConeDelivery`): a jet of fire from the muzzle filling the cone, out to its
## reach, with a flickering light on the ground around it. Placed at the muzzle, along -Z. Greybox
## until the art pass.

## Seconds a flame lives (it reaches the cone's end then).
const LIFETIME: float = 0.35
const COLOR_HOT := Color(2.4, 1.9, 1.1)
const COLOR_FLAME := Color(1.9, 0.75, 0.18, 0.85)
const COLOR_SMOKE := Color(0.35, 0.08, 0.02, 0.0)

## The light's color and its energy while it burns.
@export var light_color := Color(1.0, 0.55, 0.2)
@export var light_energy: float = 2.5

var _flames: CPUParticles3D
var _light: OmniLight3D


func _ready() -> void:
	var delivery := weapon.type.delivery as ConeDelivery
	var reach: float = delivery.reach if delivery else 5.0
	var width: float = delivery.angle if delivery else 40.0
	# Made here, not with the node: a weapon freed without entering the tree would leak them.
	_flames = CPUParticles3D.new()
	_light = OmniLight3D.new()
	_flames.emitting = false
	_flames.amount = 48
	_flames.lifetime = LIFETIME
	_flames.local_coords = false
	_flames.direction = Vector3.FORWARD
	_flames.spread = width * 0.5
	_flames.gravity = Vector3.UP * 2.0
	_flames.initial_velocity_min = reach / LIFETIME * 0.8
	_flames.initial_velocity_max = reach / LIFETIME
	_flames.scale_amount_min = 0.8
	_flames.scale_amount_max = 1.3
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.25))
	grow.add_point(Vector2(1.0, 1.0))
	_flames.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, COLOR_HOT)
	fade.add_point(0.3, COLOR_FLAME)
	fade.set_color(fade.get_point_count() - 1, COLOR_SMOKE)
	_flames.color_ramp = fade
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.9)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = Burning.soft_dot()
	quad.material = material
	_flames.mesh = quad
	_flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flames)
	_light.light_color = light_color
	_light.omni_range = reach * 0.8
	_light.position = Vector3.FORWARD * reach * 0.4
	_light.shadow_enabled = false
	_light.visible = false
	add_child(_light)
	RenderLayers.put(self, RenderLayers.EFFECTS)


func _show(on: bool, _delta: float) -> void:
	_flames.emitting = on
	_light.visible = on
	if on:
		_light.light_energy = light_energy * randf_range(0.75, 1.1)
