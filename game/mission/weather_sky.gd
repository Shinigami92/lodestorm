class_name WeatherSky
extends RefCounted
## The sky's material (`assets/shaders/sky.gdshader`), set by the `Weather`: the body's sky and
## star, a moon's planet and the other planets as points (from the star system), the biome's haze
## and weather overhead, the storm's wall and cover, and space during flights. Only changed values
## reach the shader, so the sky's radiance map isn't redrawn in calm weather.

## The most other planets shown as points (the shader's array).
const MAX_POINTS: int = 8
## How bright the other planets' points are at most, and the least.
const POINT_BRIGHTNESS: Vector2 = Vector2(0.4, 2.5)
## How fast the clouds' pattern drifts with the wind (pattern units per m/s and s).
const CLOUD_DRIFT: float = 0.0006

var material := ShaderMaterial.new()

var _values: Dictionary[StringName, Variant] = {}
var _cloud_offset := Vector2.ZERO


func _init() -> void:
	material.shader = preload("res://assets/shaders/sky.gdshader")


## Shows `body`'s sky (its `light`, or `fallback` without one) in `system`, the sun standing
## towards `to_sun`; the other planets' points come from where the bodies sit in the system.
func show_body(body: CelestialBody, light: BodyLight, system: StarSystem, to_sun: Vector3) -> void:
	set_value(&"sun_direction", to_sun)
	set_value(&"sun_radius", deg_to_rad(light.star_size) * 0.5)
	set_value(&"sun_color", light.star_color)
	set_value(&"glare", light.star_glare)
	var flat_sun: Vector2 = Vector2(to_sun.x, to_sun.z).normalized()
	var planet_radius: float = 0.0
	if body and body.orbits and light.planet_size > 0.0:
		planet_radius = deg_to_rad(light.planet_size) * 0.5
		set_value(&"planet_disc_color", body.orbits.color)
		set_value(
			&"planet_direction",
			_direction(
				flat_sun, deg_to_rad(light.planet_bearing), deg_to_rad(light.planet_elevation)
			)
		)
	set_value(&"planet_radius", planet_radius)
	set_value(&"points", _points(body, system, flat_sun))


## Shows the sky's colors: the body's zenith and horizon, the haze at the horizon (`haze` its
## share of the far view), the weather overhead.
func show_colors(
	zenith: Color, horizon: Color, haze_color: Color, haze: float, cloud: Color, cover: float
) -> void:
	set_value(&"zenith_color", zenith)
	set_value(&"horizon_color", horizon)
	set_value(&"haze_color", haze_color)
	set_value(&"haze_reach", lerpf(0.08, 0.35, haze))
	set_value(&"cloud_color", cloud)
	set_value(&"cloud_cover", cover)


## Shows the storm from `toward` (horizontal): its wall rising (0–1) and its cover over the sky.
func show_storm(toward: Vector3, color: Color, wall: float, cover: float) -> void:
	set_value(&"storm_direction", toward)
	set_value(&"storm_color", color)
	set_value(&"storm_wall", snappedf(wall, 0.002))
	set_value(&"storm_cover", snappedf(cover, 0.002))


## Moves the clouds' pattern with the wind (`wind`: m/s on the ground, horizontal) over `delta` s.
func drift(wind: Vector2, delta: float) -> void:
	if wind == Vector2.ZERO:
		return
	_cloud_offset += wind * CLOUD_DRIFT * delta
	# Small steps: the radiance map is redrawn only when the pattern moved noticeably.
	set_value(&"cloud_offset", _cloud_offset.snapped(Vector2.ONE * 0.002))


## Sets a shader parameter if it changed.
func set_value(parameter: StringName, value: Variant) -> void:
	if _values.get(parameter) == value:
		return
	_values[parameter] = value
	material.set_shader_parameter(parameter, value)


## A direction at `bearing` (radians, around up, from `flat_sun`) and `elevation` (radians).
static func _direction(flat_sun: Vector2, bearing: float, elevation: float) -> Vector3:
	var flat: Vector2 = flat_sun.rotated(bearing)
	return Vector3(flat.x * cos(elevation), sin(elevation), flat.y * cos(elevation)).normalized()


## The other planets (and gas giants) as points: their bearing from where they sit in the system
## view, at a low height above the horizon (the plane the bodies orbit in), brighter when big
## and close. A moon doesn't show its own planet as a point (it's the disc).
func _points(body: CelestialBody, system: StarSystem, flat_sun: Vector2) -> Array[Vector4]:
	var points: Array[Vector4] = []
	points.resize(MAX_POINTS)
	if not body or not system:
		return points
	var here: Vector2 = _system_position(body)
	var count: int = 0
	for other: CelestialBody in system.bodies:
		if count >= MAX_POINTS or other == body or other == body.orbits:
			continue
		if other.kind not in [CelestialBody.Kind.PLANET, CelestialBody.Kind.GAS_GIANT]:
			continue
		var offset: Vector2 = _system_position(other) - here
		if offset.length() < 0.01:
			continue
		# The star stands at the system's center: bearings count from the way towards it.
		var bearing: float = (-here).angle_to(offset) if here.length() > 0.001 else offset.angle()
		var elevation: float = deg_to_rad(8.0 + 24.0 * fposmod(other.orbit_angle * 0.37, 1.0))
		var brightness: float = clampf(
			other.size / (offset.length() * 3.0), POINT_BRIGHTNESS.x, POINT_BRIGHTNESS.y
		)
		var toward: Vector3 = _direction(flat_sun, bearing, elevation)
		points[count] = Vector4(toward.x, toward.y, toward.z, brightness)
		count += 1
	return points


## Where `body` sits in the system view (a moon or station where its planet does).
static func _system_position(body: CelestialBody) -> Vector2:
	var at: CelestialBody = body
	while at.orbits:
		at = at.orbits
	return Vector2.from_angle(deg_to_rad(at.orbit_angle)) * at.orbit_radius
