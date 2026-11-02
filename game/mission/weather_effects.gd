class_name WeatherEffects
extends Node3D
## The weather's particles around the viewer (`WeatherParticles`): the biome's (sand, spores,
## mist, snow, ash, embers, glints, heat shimmer) and the storm's, which take over as it comes.
## It follows the viewer's feet. The particles move in world space (walking doesn't drag them) and
## their shader (`assets/shaders/weather_particle.gdshader`) wraps each into a box around the
## viewer, so the field stays full wherever the viewer walks or jumps to. Unlit and dimmed with
## the outside light (`light`), so they never outshine the ore; gone aboard and in flight. Set by
## the `Weather`.

const PARTICLE_SHADER: Shader = preload("res://assets/shaders/weather_particle.gdshader")
const SHIMMER_SHADER: Shader = preload("res://assets/shaders/heat_shimmer.gdshader")
## How long the particles fade in and out, as a share of their life.
const FADE: Vector2 = Vector2(0.15, 0.25)
## How far above the ground a mist sheet fades in, in m.
const MIST_GROUND_FADE: float = 0.8

## The outside light's brightness the particles take (1: the calm sun).
var light: float = 1.0

var _biome_layers: Array[GPUParticles3D] = []
var _storm_layers: Array[GPUParticles3D] = []
var _biome_types: Array[WeatherParticles] = []


## Shows `layers` as the biome's particles, blown towards `wind_bearing` (degrees); replaces the
## ones before.
func show_biome(layers: Array[WeatherParticles], wind_bearing: float) -> void:
	if layers == _biome_types:
		return
	for old: GPUParticles3D in _biome_layers:
		old.queue_free()
	_biome_types = layers
	_biome_layers = _make_all(layers, _wind(wind_bearing))


## Shows `layers` as the storm's particles, blowing away from its side (`from`, horizontal).
func show_storm(layers: Array[WeatherParticles], from: Vector3) -> void:
	if _storm_layers.is_empty():
		_storm_layers = _make_all(layers, -from)
		return
	for i: int in _storm_layers.size():
		_blow(_storm_layers[i], layers[i], -from)


## How many of each are out (0–1): the biome's and the storm's.
func set_amounts(biome: float, storm: float) -> void:
	for layer: GPUParticles3D in _biome_layers:
		_set_amount(layer, biome)
	for layer: GPUParticles3D in _storm_layers:
		_set_amount(layer, storm)


## Follows `at` (the viewer's feet): the box the particles wrap into moves with it.
func follow(at: Vector3) -> void:
	global_position = at
	for layer: GPUParticles3D in _biome_layers + _storm_layers:
		var draw := layer.draw_pass_1.surface_get_material(0) as ShaderMaterial
		draw.set_shader_parameter(
			&"field_center", at + (layer.get_meta(&"field_offset", Vector3.ZERO) as Vector3)
		)


func _set_amount(layer: GPUParticles3D, share: float) -> void:
	# Only on a change.
	if layer.amount_ratio != share:
		layer.amount_ratio = share
	if layer.emitting != (share > 0.0):
		layer.emitting = share > 0.0
	var draw := layer.draw_pass_1.surface_get_material(0) as ShaderMaterial
	draw.set_shader_parameter(&"tint", light)
	# The ones still alive fade too, so none linger (e.g. wrapped into the ship's rooms aboard).
	draw.set_shader_parameter(&"presence", share)


func _make_all(layers: Array[WeatherParticles], wind: Vector3) -> Array[GPUParticles3D]:
	var made: Array[GPUParticles3D] = []
	for type: WeatherParticles in layers:
		var layer: GPUParticles3D = _make(type)
		_blow(layer, type, wind)
		add_child(layer)
		made.append(layer)
	return made


## The wind's way along the ground from its compass bearing.
static func _wind(bearing: float) -> Vector3:
	return Vector3(sin(deg_to_rad(bearing)), 0.0, cos(deg_to_rad(bearing)))


func _make(type: WeatherParticles) -> GPUParticles3D:
	var layer := GPUParticles3D.new()
	layer.name = WeatherParticles.Motion.find_key(type.motion) as String
	layer.amount = type.amount
	layer.lifetime = type.lifetime
	layer.preprocess = type.lifetime
	layer.randomness = 0.5
	layer.local_coords = false
	layer.emitting = false
	layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	layer.layers = RenderLayers.EFFECTS
	# The box the particles wrap into: around the viewer, from the lowest to the highest height.
	var height: float = maxf(type.heights.y - type.heights.x, 0.5)
	var offset := Vector3(0.0, (type.heights.x + type.heights.y) * 0.5, 0.0)
	var field := Vector3(type.reach * 2.0, height, type.reach * 2.0)
	layer.set_meta(&"field_offset", offset)
	layer.visibility_aabb = AABB(offset - field * 0.5, field).grow(type.size.y)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = field * 0.5
	process.emission_shape_offset = offset
	process.gravity = Vector3.ZERO
	process.scale_min = type.size.x
	process.scale_max = type.size.y
	process.color = type.color
	process.color_ramp = _fade_ramp(type.motion == WeatherParticles.Motion.GLINT)
	layer.process_material = process
	layer.draw_pass_1 = _mesh(type, field)
	return layer


## Points the particles of `type` along their motion with `wind` (horizontal unit vector).
func _blow(layer: GPUParticles3D, type: WeatherParticles, wind: Vector3) -> void:
	var process := layer.process_material as ParticleProcessMaterial
	var push: Vector3 = wind * type.wind
	var along: Vector3 = Vector3.ZERO
	var spread: float = 15.0
	match type.motion:
		WeatherParticles.Motion.FALL:
			along = push + Vector3.DOWN * type.speed
		WeatherParticles.Motion.DRIFT:
			along = wind * (type.speed + type.wind) + Vector3.UP * 0.1
			spread = 6.0
		WeatherParticles.Motion.RISE:
			along = Vector3.UP * type.speed + push
		WeatherParticles.Motion.FLOAT:
			along = push + Vector3.UP * type.speed * 0.3
			spread = 180.0
		WeatherParticles.Motion.MIST, WeatherParticles.Motion.SHIMMER:
			along = push
			spread = 40.0
		WeatherParticles.Motion.GLINT:
			along = Vector3.ZERO
	var speed: float = along.length()
	process.direction = along / speed if speed > 0.0 else Vector3.UP
	process.spread = spread
	process.initial_velocity_min = speed * 0.7
	process.initial_velocity_max = speed * 1.3
	if type.motion == WeatherParticles.Motion.FLOAT:
		process.initial_velocity_min = type.speed * 0.2
		process.initial_velocity_max = type.speed
	process.particle_flag_align_y = type.motion == WeatherParticles.Motion.DRIFT


## Fades a particle in and out over its life (a glint flashes up in the middle).
static func _fade_ramp(flash: bool) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 0))
	gradient.set_color(1, Color(1, 1, 1, 0))
	if flash:
		gradient.add_point(0.5, Color(1, 1, 1, 1))
	else:
		gradient.add_point(FADE.x, Color(1, 1, 1, 1))
		gradient.add_point(1.0 - FADE.y, Color(1, 1, 1, 1))
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


## A quad per particle (stretched along the wind for streaks) wrapped into `field`, its material
## for `type`'s look.
static func _mesh(type: WeatherParticles, field: Vector3) -> Mesh:
	var quad := QuadMesh.new()
	var draw := ShaderMaterial.new()
	draw.shader = PARTICLE_SHADER
	match type.motion:
		WeatherParticles.Motion.DRIFT:
			quad.size = Vector2(1.0 / type.stretch, 1.0)
			draw.set_shader_parameter(&"shape", 1)
		WeatherParticles.Motion.MIST:
			draw.set_shader_parameter(&"shape", 2)
			draw.set_shader_parameter(&"ground_fade", MIST_GROUND_FADE)
		WeatherParticles.Motion.SHIMMER:
			draw.shader = SHIMMER_SHADER
	draw.set_shader_parameter(&"field_size", field)
	draw.set_shader_parameter(&"glow", type.glow)
	quad.material = draw
	return quad
