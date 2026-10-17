class_name Weather
extends Node
## Shows the storm in the world, so the mission time is visible without a HUD: haze and darker
## light build up during the mission's warning time and the storm rages once the timer ran out.
## A new mission (picked, so the ship flew to its location) and the next run start in clear
## weather. While the `viewer` is aboard the ship, the haze and the tinted ambient light fade out,
## so the inside stays clear; the dim sun still shows the storm outside. Aboard, the ambient light
## also turns up to `indoor_ambient_energy`: the cut-away roof still shades the rooms, and the
## dark outside lighting would leave them murky.
## It also shows the ship's flight (`ShipFlight`): the sky turns to space with stars (and the
## ambient light colder), and in the clouds the sky takes their color and a thick fog below the
## decks hides the ground until the touchdown clears it.

## How much of the storm shows when the timer runs out (0–1); the rest comes with the storm.
const BUILD_UP: float = 0.4
## Seconds the weather takes to go from calm to full storm once the storm hits.
const RISE_TIME: float = 3.0
## Seconds the haze takes to fade out when the viewer goes aboard, and back in when they leave.
const INDOOR_FADE_TIME: float = 0.5
## World height below which the clouds' fog lies (just under the lower deck's floor).
const CLOUD_FOG_HEIGHT: float = 1.5
## How fast the clouds' fog thickens below `CLOUD_FOG_HEIGHT`, in thick clouds.
const CLOUD_FOG_DENSITY: float = 1.5

@export var mission: Mission
@export var environment: WorldEnvironment
@export var sun: DirectionalLight3D
## The local player the camera follows.
@export var viewer: Player
@export var storm_color := Color(0.42, 0.27, 0.2)
## How much the fog covers the far distance in a full storm (0–1).
@export var max_fog: float = 0.9
## Sun energy in a full storm, relative to the calm one.
@export var storm_sun_energy: float = 0.35
## Ambient light energy while the viewer is aboard.
@export var indoor_ambient_energy: float = 1.7
## Sky color in the clouds.
@export var cloud_color := Color(0.27, 0.25, 0.24)
## Ambient light color in space.
@export var space_ambient := Color(0.22, 0.27, 0.4)

## How stormy it is, from 0 (calm) to 1 (full storm).
var intensity: float = 0.0
## How far the view is inside the ship, from 0 (outside) to 1 (aboard).
var indoors: float = 0.0

var _calm_background: Color
var _calm_ambient: Color
var _calm_ambient_energy: float
var _calm_sun_energy: float
var _sky_material := ShaderMaterial.new()


func _ready() -> void:
	# Its own copy: the scene's environment resource is shared by every instance of the map.
	var env: Environment = environment.environment.duplicate()
	environment.environment = env
	_calm_background = env.background_color
	_calm_ambient = env.ambient_light_color
	_calm_ambient_energy = env.ambient_light_energy
	_calm_sun_energy = sun.light_energy
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = storm_color
	env.fog_depth_begin = 30.0
	env.fog_depth_end = 80.0
	env.fog_height = CLOUD_FOG_HEIGHT
	_sky_material.shader = preload("res://assets/shaders/space_sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = _sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	mission.opened.connect(_clear)
	mission.selected.connect(_clear.unbind(1))
	_apply()


func _process(delta: float) -> void:
	var target: float = intensity
	match mission.state:
		Mission.State.CLOSED, Mission.State.OPEN:
			target = 0.0
		Mission.State.RUNNING:
			var warning: float = mission.warning_time()
			target = BUILD_UP * clampf(1.0 - mission.time_left / warning, 0.0, 1.0)
		Mission.State.STORM, Mission.State.LOST:
			target = 1.0
	# RETURNED keeps the weather the players escaped from.
	intensity = move_toward(intensity, target, delta / RISE_TIME)
	var aboard: bool = viewer != null and mission.ship.is_aboard(viewer)
	indoors = move_toward(indoors, 1.0 if aboard else 0.0, delta / INDOOR_FADE_TIME)
	_apply()


func _apply() -> void:
	var env: Environment = environment.environment
	var haze: float = intensity * (1.0 - indoors)
	var space: float = mission.flight.space_amount()
	var clouds: float = mission.flight.cloud_amount()
	env.fog_enabled = haze > 0.0 or clouds > 0.0
	env.fog_density = max_fog * haze
	env.fog_height_density = CLOUD_FOG_DENSITY * clouds
	# The storm and the clouds don't meet: the storm haze is gone aboard, and only the clouds' fog
	# lies outside during the flight.
	env.fog_light_color = cloud_color if clouds > 0.0 else storm_color
	env.background_color = _calm_background.lerp(storm_color, intensity).lerp(cloud_color, clouds)
	_sky_material.set_shader_parameter(&"atmosphere_color", env.background_color)
	_sky_material.set_shader_parameter(&"space", space)
	env.ambient_light_color = (_calm_ambient.lerp(storm_color * 1.6, haze).lerp(
		space_ambient, space * (1.0 - indoors)
	))
	env.ambient_light_energy = lerpf(_calm_ambient_energy, indoor_ambient_energy, indoors)
	sun.light_energy = lerpf(_calm_sun_energy, _calm_sun_energy * storm_sun_energy, intensity)


func _clear() -> void:
	intensity = 0.0
	_apply()
