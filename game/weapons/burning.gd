class_name Burning
extends CPUParticles3D
## Fire on an alien or a nest (Scald's flame, see `BurnEffect`): a child of what burns, with
## flames licking up from it, dealing its damage every `TICK` seconds (past armor: fire finds the
## gaps) until it burns out or its target dies. A new flame on something already burning refreshes
## it, the stronger damage and the longer time winning; burns don't add up and don't spread. An
## alien burrowing puts it out. All values TBD (playtest).

## Seconds between its damage, so the damage readout counts up in steps.
const TICK: float = 0.5
const NODE_NAME: StringName = &"Burning"
const COLOR_HOT := Color(2.2, 1.5, 0.6)
const COLOR_FLAME := Color(1.6, 0.55, 0.12, 0.9)
const COLOR_GONE := Color(0.5, 0.08, 0.02, 0.0)

static var _flame_mesh: Mesh

## Damage per second, and the seconds it burns on.
var damage_per_second: float = 0.0
var time_left: float = 0.0
## Who set it burning (for the damage readout), or null.
var by: Node

var _since_tick: float = 0.0


## Sets `target` (an alien or a destructible) burning for `seconds` at `damage` per second, set by
## `by`, or refreshes the fire on it.
static func ignite(target: Node3D, damage: float, seconds: float, by_whom: Node) -> void:
	if _is_out(target):
		return
	var burning := target.get_node_or_null(NodePath(NODE_NAME)) as Burning
	if not burning:
		burning = Burning.new()
		burning.name = NODE_NAME
		target.add_child(burning)
		burning.global_position = _flame_point(target)
	burning.damage_per_second = maxf(burning.damage_per_second, damage)
	burning.time_left = maxf(burning.time_left, seconds)
	burning.by = by_whom


## Whether `target` is burning right now.
static func is_burning(target: Node3D) -> bool:
	return target.get_node_or_null(NodePath(NODE_NAME)) != null


func _init() -> void:
	layers = RenderLayers.EFFECTS
	amount = 18
	lifetime = 0.55
	local_coords = false
	emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	emission_sphere_radius = 0.35
	direction = Vector3.UP
	spread = 20.0
	gravity = Vector3.UP * 1.5
	initial_velocity_min = 0.6
	initial_velocity_max = 1.4
	scale_amount_min = 0.6
	scale_amount_max = 1.1
	var fade := Gradient.new()
	fade.set_color(0, COLOR_HOT)
	fade.add_point(0.35, COLOR_FLAME)
	fade.set_color(fade.get_point_count() - 1, COLOR_GONE)
	color_ramp = fade
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 0.6))
	shrink.add_point(Vector2(0.3, 1.0))
	shrink.add_point(Vector2(1.0, 0.2))
	scale_amount_curve = shrink
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh = _flame()


func _physics_process(delta: float) -> void:
	var target := get_parent() as Node3D
	if _is_out(target):
		queue_free()
		return
	time_left -= delta
	_since_tick += delta
	if _since_tick >= TICK or time_left <= 0.0:
		# The last step burns only until it burned out.
		_burn(target, damage_per_second * (_since_tick + minf(time_left, 0.0)))
		_since_tick = 0.0
	if time_left <= 0.0:
		queue_free()


func _burn(target: Node3D, amount_dealt: float) -> void:
	if target is Alien:
		(target as Alien).take_damage(amount_dealt)
	elif target is Destructible:
		(target as Destructible).take_damage(amount_dealt, by)
	DamageNumber.show_hit(by, target, amount_dealt)


## Whether `target` can't burn (anymore): dead, destroyed or under the ground.
static func _is_out(target: Node3D) -> bool:
	if target is Alien:
		var alien := target as Alien
		return alien.dead or alien.underground
	if target is Destructible:
		return (target as Destructible).dead
	return true


## Where the flames sit on `target`: its middle.
static func _flame_point(target: Node3D) -> Vector3:
	if target is Alien:
		return (target as Alien).get_aim_point()
	if target is Destructible:
		return (target as Destructible).get_aim_point()
	return target.global_position


static func _flame() -> Mesh:
	if not _flame_mesh:
		var quad := QuadMesh.new()
		quad.size = Vector2(0.4, 0.55)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		material.vertex_color_use_as_albedo = true
		material.albedo_texture = soft_dot()
		quad.material = material
		_flame_mesh = quad
	return _flame_mesh


## A white dot fading out to its edge, for soft glowing particles (flames, beams' ends).
static func soft_dot() -> Texture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = 32
	texture.height = 32
	return texture
