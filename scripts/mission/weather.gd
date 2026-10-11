class_name Weather
extends Node
## Shows the storm in the world, so the mission time is visible without a HUD: haze and darker
## light build up during the mission's warning time and the storm rages once the timer ran out.
## The next run starts in clear weather.

## How much of the storm shows when the timer runs out (0–1); the rest comes with the storm.
const BUILD_UP: float = 0.4
## Seconds the weather takes to go from calm to full storm once the storm hits.
const RISE_TIME: float = 3.0

@export var mission: Mission
@export var environment: WorldEnvironment
@export var sun: DirectionalLight3D
@export var storm_color := Color(0.42, 0.27, 0.2)
## How much the fog covers the far distance in a full storm (0–1).
@export var max_fog: float = 0.9
## Sun energy in a full storm, relative to the calm one.
@export var storm_sun_energy: float = 0.35

## How stormy it is, from 0 (calm) to 1 (full storm).
var intensity: float = 0.0

var _calm_background: Color
var _calm_ambient: Color
var _calm_sun_energy: float


func _ready() -> void:
	# Its own copy: the scene's environment resource is shared by every instance of the map.
	var env: Environment = environment.environment.duplicate()
	environment.environment = env
	_calm_background = env.background_color
	_calm_ambient = env.ambient_light_color
	_calm_sun_energy = sun.light_energy
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = storm_color
	env.fog_depth_begin = 30.0
	env.fog_depth_end = 80.0
	mission.opened.connect(_on_opened)
	_apply()


func _process(delta: float) -> void:
	var target: float = intensity
	match mission.state:
		Mission.State.CLOSED, Mission.State.OPEN:
			target = 0.0
		Mission.State.RUNNING:
			var warning: float = mission.settings.warning_time
			target = BUILD_UP * clampf(1.0 - mission.time_left / warning, 0.0, 1.0)
		Mission.State.STORM, Mission.State.LOST:
			target = 1.0
	# RETURNED keeps the weather the players escaped from.
	intensity = move_toward(intensity, target, delta / RISE_TIME)
	_apply()


func _apply() -> void:
	var env: Environment = environment.environment
	env.fog_enabled = intensity > 0.0
	env.fog_density = max_fog * intensity
	env.background_color = _calm_background.lerp(storm_color, intensity)
	env.ambient_light_color = _calm_ambient.lerp(storm_color * 1.6, intensity)
	sun.light_energy = lerpf(_calm_sun_energy, _calm_sun_energy * storm_sun_energy, intensity)


func _on_opened() -> void:
	intensity = 0.0
	_apply()
