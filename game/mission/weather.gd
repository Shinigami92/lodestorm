class_name Weather
extends Node
## The light and weather outside, and the storm in the world, so the mission time is visible
## without a HUD. Each body has its light and sky (`CelestialBody.light`, a `BodyLight`), each
## biome its weather on top (`LocationBiome.weather`, a `BiomeWeather`): haze in the distance, mist
## in the hollows, a tint, what hangs overhead and particles around the viewer (`WeatherEffects`).
## The sky is one shader (`WeatherSky`).
## The storm: in the mission's warning time the sun dims step by step (to `warning_sun`) while a
## wall of cloud rises on the storm's side and the haze builds up in the distance; when the timer
## runs out the sun drops to `storm_sun`, the haze gets thick within a few seconds and the storm's
## particles take over from the biome's. Emissives and the rim light don't dim. The ambient light
## never drops below the darkness floor (`min_ambient_energy`), so the ground's shapes stay
## readable. A new mission (picked, so the ship flew to its location) and the next run start in
## clear weather. While the `viewer` is aboard the ship (or inside a docked station), the haze, the
## mist, the particles and the tinted ambient light fade out, so the inside stays clear; the dim
## sun still shows the storm outside. Aboard, the ambient light also turns up to
## `indoor_ambient_energy`: the cut-away roof still shades the rooms, and the dark outside lighting
## would leave them murky.
## It also shows the ship's flight (`ShipFlight`): the sky turns to space with stars (and the
## ambient light colder), and in the clouds the sky takes their color and a thick fog below the
## decks hides the ground until the touchdown clears it.
## Its `MissionSounds` child plays the storm, its warning and the countdown for the `viewer`.
## All values TBD (playtest).

## How much of the storm's haze shows when the timer runs out (0–1); the rest comes with the storm.
const BUILD_UP: float = 0.4
## Seconds the weather takes to go from calm to full storm once the storm hits.
const RISE_TIME: float = 3.0
## Seconds one of the sun's steps takes to dim.
const STEP_TIME: float = 2.0
## Seconds the haze takes to fade out when the viewer goes aboard, and back in when they leave.
const INDOOR_FADE_TIME: float = 0.5
## World height below which the clouds' fog lies (just under the lower deck's floor).
const CLOUD_FOG_HEIGHT: float = 1.5
## How fast the clouds' fog thickens below `CLOUD_FOG_HEIGHT`, in thick clouds.
const CLOUD_FOG_DENSITY: float = 1.5
## Where the storm's haze starts and is thickest, in m from the camera.
const STORM_HAZE: Vector2 = Vector2(30.0, 80.0)
## The star's brightness in the sky, relative to the sun's light.
const STAR_ENERGY: float = 5.0

@export var mission: Mission
@export var voyage: Voyage
@export var environment: WorldEnvironment
@export var sun: DirectionalLight3D
## The local player the camera follows.
@export var viewer: Player
@export var storm_color := Color(0.42, 0.27, 0.2)
## How much the fog covers the far distance in a full storm (0–1).
@export var max_fog: float = 0.9
## The sun's energy at the end of the warning and in the storm, relative to the calm one, and in
## how many steps it dims during the warning.
@export var warning_sun: float = 0.4
@export var storm_sun: float = 0.25
@export var sun_steps: int = 4
## The darkness floor: the ambient light's least energy outside.
@export var min_ambient_energy: float = 0.4
## Ambient light energy while the viewer is aboard.
@export var indoor_ambient_energy: float = 1.7
## Sky color in the clouds.
@export var cloud_color := Color(0.27, 0.25, 0.24)
## Ambient light color in space.
@export var space_ambient := Color(0.22, 0.27, 0.4)
## The light where the body has none of its own (a station, the test location).
@export var default_light: BodyLight
## The storm's particles (they take over from the biome's).
@export var storm_particles: Array[WeatherParticles] = []

## How stormy it is, from 0 (calm) to 1 (full storm).
var intensity: float = 0.0
## How far the view is inside the ship, from 0 (outside) to 1 (aboard).
var indoors: float = 0.0
## The sun's energy relative to the body's calm one (dims in steps with the storm).
var sun_share: float = 1.0
## The light and weather shown now (the weather null: none, e.g. at a station).
var light: BodyLight
var biome_weather: BiomeWeather

var _sky := WeatherSky.new()
var _effects := WeatherEffects.new()
## The way towards the sun along the ground (its compass direction stays, its height is the body's).
var _sun_bearing := Vector2(0.5, 0.87)
## The way towards the storm, along the ground.
var _storm_from := Vector3.RIGHT
var _shown_location: Node3D
var _shown_body: CelestialBody


func _ready() -> void:
	# Its own copy: the scene's environment resource is shared by every instance of the map.
	var env: Environment = environment.environment.duplicate()
	environment.environment = env
	if not default_light:
		default_light = BodyLight.new()
	light = default_light
	var back: Vector3 = sun.global_basis.z
	_sun_bearing = Vector2(back.x, back.z).normalized()
	env.fog_mode = Environment.FOG_MODE_DEPTH
	# The sky draws its own haze (`WeatherSky`), so the star and the storm's wall show through.
	env.fog_sky_affect = 0.0
	var sky := Sky.new()
	sky.sky_material = _sky.material
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	_effects.name = "Effects"
	_effects.top_level = true
	add_child(_effects)
	_effects.show_storm(storm_particles, _storm_from)
	mission.opened.connect(_clear)
	voyage.selected.connect(_clear.unbind(1))
	var sounds := MissionSounds.new()
	sounds.name = "Sounds"
	sounds.weather = self
	add_child(sounds)
	_show_place()
	_apply()


func _process(delta: float) -> void:
	if voyage.location != _shown_location or voyage.ship_body() != _shown_body:
		_show_place()
	var target: float = intensity
	var sun_target: float = 1.0
	match mission.state:
		Mission.State.CLOSED, Mission.State.OPEN:
			target = 0.0
		Mission.State.RUNNING:
			var warned: float = clampf(1.0 - mission.time_left / mission.warning_time(), 0.0, 1.0)
			target = BUILD_UP * warned
			sun_target = lerpf(1.0, warning_sun, ceilf(warned * sun_steps) / sun_steps)
		Mission.State.STORM, Mission.State.LOST:
			target = 1.0
			sun_target = storm_sun
		Mission.State.RETURNED:
			# Keeps the weather the players escaped from.
			sun_target = sun_share
	intensity = move_toward(intensity, target, delta / RISE_TIME)
	sun_share = move_toward(
		sun_share, sun_target, delta * (1.0 - warning_sun) / sun_steps / STEP_TIME
	)
	if target == 1.0:
		sun_share = minf(
			sun_share, lerpf(warning_sun, storm_sun, (intensity - BUILD_UP) / (1.0 - BUILD_UP))
		)
	var station := voyage.location as SpaceStation
	var aboard: bool = (
		viewer != null
		and (mission.ship.is_aboard(viewer) or (station != null and station.is_inside(viewer)))
	)
	indoors = move_toward(indoors, 1.0 if aboard else 0.0, delta / INDOOR_FADE_TIME)
	if biome_weather:
		var wind: Vector3 = biome_weather.wind_direction()
		_sky.drift(Vector2(wind.x, wind.z), delta)
	if viewer:
		_effects.follow(viewer.global_position)
	_apply()


## The direction towards the sun (unit vector, world space).
func to_sun() -> Vector3:
	var elevation: float = deg_to_rad(light.sun_elevation)
	return (
		Vector3(_sun_bearing.x * cos(elevation), sin(elevation), _sun_bearing.y * cos(elevation))
		. normalized()
	)


## Takes the light of the body the ship is at and the weather of the location's biome.
func _show_place() -> void:
	_shown_location = voyage.location
	_shown_body = voyage.ship_body()
	light = _shown_body.light if _shown_body and _shown_body.light else default_light
	var generated := _shown_location as GeneratedLocation
	biome_weather = generated.biome.weather if generated and generated.biome else null
	# The storm comes from a side of its own at every location.
	var seed_of_world: int = generated.world_seed if generated else 0
	_storm_from = Vector3.FORWARD.rotated(Vector3.UP, fposmod(seed_of_world * 0.618034, 1.0) * TAU)
	sun.light_color = light.sun_color
	sun.shadow_blur = light.shadow_softness
	sun.look_at_from_position(sun.global_position, sun.global_position - to_sun())
	var system: StarSystem = voyage.settings.system if voyage.settings else null
	_sky.show_body(_shown_body, light, system, to_sun())
	var particles: Array[WeatherParticles] = []
	var wind: Vector3 = Vector3.BACK
	if biome_weather:
		particles = biome_weather.particles
		wind = biome_weather.wind_direction()
	_effects.show_biome(particles, wind)
	_effects.show_storm(storm_particles, _storm_from)


func _apply() -> void:
	var env: Environment = environment.environment
	var outside: float = 1.0 - indoors
	var haze: float = intensity * outside
	var space: float = voyage.flight.space_amount()
	var clouds: float = voyage.flight.cloud_amount()
	var calm_haze: float = biome_weather.haze * outside if biome_weather else 0.0
	var haze_color: Color = biome_weather.haze_color if biome_weather else storm_color
	var fog_color: Color = haze_color.lerp(storm_color, _warned())
	env.fog_density = lerpf(calm_haze, max_fog, haze)
	var begin: Vector2 = (
		Vector2(biome_weather.haze_begin, biome_weather.haze_end) if biome_weather else STORM_HAZE
	)
	env.fog_depth_begin = lerpf(begin.x, STORM_HAZE.x, intensity)
	env.fog_depth_end = lerpf(begin.y, STORM_HAZE.y, intensity)
	var mist: float = biome_weather.mist_density * outside if biome_weather else 0.0
	env.fog_height = CLOUD_FOG_HEIGHT
	env.fog_height_density = CLOUD_FOG_DENSITY * clouds
	if clouds == 0.0 and mist > 0.0:
		var floor_height: float = voyage.location.global_position.y if voyage.location else 0.0
		env.fog_height = floor_height + biome_weather.mist_height
		env.fog_height_density = mist
	env.fog_enabled = env.fog_density > 0.0 or env.fog_height_density > 0.0
	# The storm and the clouds don't meet: the storm haze is gone aboard, and only the clouds' fog
	# lies outside during the flight.
	env.fog_light_color = cloud_color if clouds > 0.0 else fog_color
	var glare: float = biome_weather.glare if biome_weather else 0.0
	env.fog_sun_scatter = maxf(glare, light.star_glare * 0.3) * (1.0 - intensity)
	var tint: Color = biome_weather.ambient_tint if biome_weather else Color.WHITE
	var ambient: Color = light.ambient_color * tint
	env.ambient_light_color = ambient.lerp(storm_color * 1.6, haze).lerp(
		space_ambient, space * outside
	)
	var ambient_energy: float = maxf(light.ambient_energy, min_ambient_energy)
	env.ambient_light_energy = lerpf(ambient_energy, indoor_ambient_energy, indoors)
	sun.light_energy = light.sun_energy * sun_share
	_show_sky(haze_color, calm_haze, space, clouds)
	_effects.light = _ground_light(light) * sun_share / _ground_light(default_light)
	var calm_effects: float = outside * (1.0 - space) * (1.0 - clouds)
	var storm_share: float = _storm_share()
	_effects.set_amounts(calm_effects * (1.0 - storm_share), calm_effects * storm_share)


## How far the weather has built up towards the storm (0–1, full at `BUILD_UP`).
func _warned() -> float:
	return clampf(intensity / BUILD_UP, 0.0, 1.0)


## How far the storm itself has come in (0–1, from `BUILD_UP` on).
func _storm_share() -> float:
	return clampf((intensity - BUILD_UP) / (1.0 - BUILD_UP), 0.0, 1.0)


## How brightly the sun of `body_light` lights flat ground.
static func _ground_light(body_light: BodyLight) -> float:
	return maxf(body_light.sun_energy * sin(deg_to_rad(body_light.sun_elevation)), 0.01)


func _show_sky(haze_color: Color, calm_haze: float, space: float, clouds: float) -> void:
	var zenith: Color = light.zenith_color
	var horizon: Color = light.horizon_color
	var overhead: Color = biome_weather.cloud_color if biome_weather else cloud_color
	var cover: float = biome_weather.cloud_cover if biome_weather else 0.0
	var haze_amount: float = maxf(calm_haze, intensity * BUILD_UP)
	if clouds > 0.0:
		zenith = zenith.lerp(cloud_color, clouds)
		horizon = horizon.lerp(cloud_color, clouds)
		haze_color = haze_color.lerp(cloud_color, clouds)
	_sky.show_colors(zenith, horizon, haze_color, haze_amount, overhead, cover)
	var storm_share: float = _storm_share()
	_sky.show_storm(_storm_from, storm_color, _warned(), storm_share)
	_sky.set_value(&"sun_energy", STAR_ENERGY * sun_share * (1.0 - storm_share))
	_sky.set_value(&"space", space)


func _clear() -> void:
	intensity = 0.0
	sun_share = 1.0
	_apply()
