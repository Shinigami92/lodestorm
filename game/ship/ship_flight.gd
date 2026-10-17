class_name ShipFlight
extends Node3D
## The ship's states between missions: in space, flying to a location, landed there, taking off.
## The ship itself never moves (everyone aboard stays put): the world changes around it. Flying to
## a location (`fly`) runs through the departure in space (stars streak past), the descent
## through the clouds (the location is placed under them, once it's ready) and the touchdown (the
## clouds clear and the ground shows); from a location, the take-off comes first (climbing through
## the clouds into space, where the location is left behind). A flight to another planet or moon
## stays longer in space (`FlightSettings.travel_time`), with the destination growing below the
## ship. `take_off` only goes back to space.
## The ramp only opens while landed. Durations in `settings`; `skip` jumps to the end (debug,
## tests). Its look: star streaks and passing clouds around the hull, and the camera shakes in the
## clouds; the sky and fog follow `space_amount` and `cloud_amount` (see `Weather`).

## Emitted when the flight enters another phase.
signal phase_changed(phase: Phase)
## Emitted at the end of the take-off, high above the location: it's left behind now.
signal left_location
## Emitted when the descent is over and the location is ready: it goes under the ship now.
signal reached_location
## Emitted when the ship stands on the ground again.
signal landed

enum Phase { SPACE, DEPARTURE, DESCENT, TOUCHDOWN, LANDED, TAKEOFF }

## Ship-local area (x, z) around the hull: streaks and clouds stay below its floor there, so
## they don't cross the rooms seen through the cut-away walls.
const HULL_FOOTPRINT := Rect2(-89.0, -26.0, 112.0, 52.0)
## Ship-local height above which nothing passes over the hull's footprint.
const HULL_BOTTOM: float = -4.0
## Ship-local box the streaks pass through (center, half size): below the decks, so they never
## come between the camera and the ship.
const STREAKS_CENTER := Vector3(-33.0, -35.0, 0.0)
const STREAKS_HALF := Vector3(150.0, 35.0, 110.0)
## Ship-local box the clouds start in (center, half size), beside the hull and far enough below
## that even the biggest puff stays under the decks while it rises (`CLOUD_LIFETIME`).
const CLOUDS_CENTER := Vector3(-33.0, -95.0, 0.0)
const CLOUDS_HALF := Vector3(130.0, 25.0, 100.0)
## Seconds a cloud puff lives.
const CLOUD_LIFETIME: float = 1.6
## Edge length of a cloud puff, in m.
const CLOUD_SIZE: float = 40.0
## Streak speed past the ship, in m/s (the ship flies nose first, to -x).
const STREAK_SPEED: float = 160.0
## Cloud speed past the ship, in m/s.
const CLOUD_SPEED: float = 20.0
## Camera shake in the thick of the clouds, in m.
const SHAKE: float = 0.05
## Ship-local spot of the destination body on the way to it (below and behind the hull, seen
## through the windows and past the decks), and its radius in m at the start and the end of the
## way.
const DESTINATION_CENTER := Vector3(-30.0, -260.0, -420.0)
const DESTINATION_RADIUS := Vector2(20.0, 160.0)

@export var settings: FlightSettings
@export var cloud_color := Color(0.5, 0.45, 0.42)

var phase: Phase = Phase.SPACE
## Seconds since the phase began.
var phase_time: float = 0.0
## Whether the location to land at is ready; the descent lasts until it is.
var destination_ready: bool = false

## Whether the flight goes on to a location after the take-off.
var _destination: bool = false
## The planet or moon the flight crosses space to, or null (a flight within the same body).
var _destination_body: CelestialBody
var _streaks: GPUParticles3D
var _clouds: GPUParticles3D
var _body_view: MeshInstance3D
var _body_material := StandardMaterial3D.new()


func _ready() -> void:
	_streaks = _make_streaks()
	add_child(_streaks)
	_clouds = _make_clouds()
	add_child(_clouds)
	_body_view = _make_body_view()
	add_child(_body_view)
	_update_look()


func _physics_process(delta: float) -> void:
	if phase in [Phase.SPACE, Phase.LANDED]:
		return
	phase_time += delta
	if phase_time >= phase_duration():
		_advance()


func _process(_delta: float) -> void:
	_update_look()


## Starts the flight to the next location: from space right away, from a location after the
## take-off. `to_body`: the planet or moon it's on when that's another one than the ship's (a
## longer way through space), else null. Returns whether it started (not while flying already).
func fly(to_body: CelestialBody = null) -> bool:
	if is_flying():
		return false
	_destination = true
	_destination_body = to_body
	_enter(Phase.TAKEOFF if phase == Phase.LANDED else Phase.DEPARTURE)
	return true


## Takes off from the location back into space. Returns whether it started (only when landed).
func take_off() -> bool:
	if phase != Phase.LANDED:
		return false
	_destination = false
	_destination_body = null
	_enter(Phase.TAKEOFF)
	return true


## Stands the ship on the ground right away (a map that starts with a location).
func land_now() -> void:
	_destination = false
	_destination_body = null
	_enter(Phase.LANDED)


## Runs through the rest of the flight at once; the descent still waits for `destination_ready`.
func skip() -> void:
	while is_flying():
		var before: Phase = phase
		phase_time = phase_duration()
		_advance()
		if phase == before:
			return


## Whether the ship is between space and the ground.
func is_flying() -> bool:
	return phase not in [Phase.SPACE, Phase.LANDED]


## Seconds the current phase takes (0 for the resting ones).
func phase_duration() -> float:
	match phase:
		Phase.DEPARTURE:
			return settings.travel_time if _destination_body else settings.departure_time
		Phase.DESCENT:
			return settings.descent_time
		Phase.TOUCHDOWN:
			return settings.touchdown_time
		Phase.TAKEOFF:
			return settings.takeoff_time
	return 0.0


## How far the current phase is, from 0 to 1.
func progress() -> float:
	var duration: float = phase_duration()
	if duration <= 0.0:
		return 1.0
	return clampf(phase_time / duration, 0.0, 1.0)


## How much of space shows around the ship, from 0 (a planet's sky) to 1 (stars).
func space_amount() -> float:
	match phase:
		Phase.SPACE, Phase.DEPARTURE:
			return 1.0
		Phase.DESCENT:
			return 1.0 - smoothstep(0.0, 0.3, progress())
		Phase.TAKEOFF:
			return smoothstep(0.6, 0.9, progress())
	return 0.0


## How thick the clouds around the ship are, from 0 to 1.
func cloud_amount() -> float:
	var at: float = progress()
	match phase:
		Phase.DESCENT:
			return smoothstep(0.05, 0.35, at)
		Phase.TOUCHDOWN:
			return 1.0 - smoothstep(0.0, 1.0, at)
		Phase.TAKEOFF:
			return smoothstep(0.1, 0.35, at) * (1.0 - smoothstep(0.65, 0.9, at))
	return 0.0


## The planet or moon the flight crosses space to, or null (within the same body, or not flying).
func get_destination_body() -> CelestialBody:
	return _destination_body if _destination else null


## How big the destination body shows below the ship, from 0 (not at all) to 1 (filling the view
## as the descent begins): it grows over the way through space to another body.
func destination_amount() -> float:
	if not get_destination_body():
		return 0.0
	match phase:
		Phase.DEPARTURE:
			return progress()
		Phase.DESCENT:
			return 1.0 - smoothstep(0.0, 0.3, progress())
	return 0.0


## How many stars streak past, from 0 to 1.
func streak_amount() -> float:
	if phase != Phase.DEPARTURE:
		return 0.0
	var at: float = progress()
	return smoothstep(0.0, 0.2, at) * (1.0 - smoothstep(0.8, 1.0, at))


## How much the hull shakes, in m of camera offset.
func shake_amount() -> float:
	match phase:
		Phase.DESCENT:
			return SHAKE * cloud_amount()
		Phase.TOUCHDOWN:
			# Calming down, with a jolt when the landing gear touches the ground.
			var at: float = progress()
			return SHAKE * (1.0 - at) + SHAKE * 2.0 * smoothstep(0.85, 0.92, at) * (1.0 - at) * 8.0
		Phase.TAKEOFF:
			return SHAKE * (1.0 - smoothstep(0.5, 0.9, progress()))
	return 0.0


func _advance() -> void:
	match phase:
		Phase.DEPARTURE:
			_enter(Phase.DESCENT)
		Phase.DESCENT:
			if destination_ready:
				reached_location.emit()
				_enter(Phase.TOUCHDOWN)
		Phase.TOUCHDOWN:
			_destination = false
			_destination_body = null
			_enter(Phase.LANDED)
			landed.emit()
		Phase.TAKEOFF:
			left_location.emit()
			_enter(Phase.DEPARTURE if _destination else Phase.SPACE)


func _enter(next: Phase) -> void:
	phase = next
	phase_time = 0.0
	phase_changed.emit(phase)


func _update_look() -> void:
	var streaks: float = streak_amount()
	_streaks.emitting = streaks > 0.0
	_streaks.amount_ratio = maxf(streaks, 0.01)
	var clouds: float = cloud_amount()
	_clouds.emitting = clouds > 0.0
	_clouds.amount_ratio = maxf(clouds, 0.01)
	# Rising past the ship on the way down, sinking on the way up.
	var rising: float = -1.0 if phase == Phase.TAKEOFF else 1.0
	(_clouds.process_material as ParticleProcessMaterial).direction = Vector3.UP * rising
	var shake: float = shake_amount()
	for rig: IsoCameraRig in get_tree().get_nodes_in_group(IsoCameraRig.GROUP):
		rig.shake = shake
	var body_amount: float = destination_amount()
	_body_view.visible = body_amount > 0.0
	if _body_view.visible:
		var shown: CelestialBody = get_destination_body()
		var grow: float = progress() if phase == Phase.DEPARTURE else 1.0
		var radius: float = lerpf(
			DESTINATION_RADIUS.x, DESTINATION_RADIUS.y, smoothstep(0.0, 1.0, grow)
		)
		_body_view.scale = Vector3.ONE * radius
		_body_material.albedo_color = Color(shown.color, body_amount)


## The destination body seen on the way: a sphere in its color, lit from the side.
func _make_body_view() -> MeshInstance3D:
	var view := MeshInstance3D.new()
	view.name = "Destination"
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 48
	mesh.rings = 24
	view.mesh = mesh
	_body_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_body_material.roughness = 0.9
	_body_material.disable_fog = true
	_body_material.disable_receive_shadows = true
	view.material_override = _body_material
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view.position = DESTINATION_CENTER
	view.visible = false
	return view


func _make_streaks() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "Streaks"
	particles.amount = 160
	particles.lifetime = 1.5
	particles.preprocess = 1.5
	particles.local_coords = true
	particles.visibility_aabb = AABB(STREAKS_CENTER - STREAKS_HALF * 2.0, STREAKS_HALF * 4.0)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	process.emission_point_texture = _points_around_hull(512, 1, STREAKS_CENTER, STREAKS_HALF)
	process.emission_point_count = 512
	process.direction = Vector3.RIGHT
	process.spread = 0.0
	process.initial_velocity_min = STREAK_SPEED
	process.initial_velocity_max = STREAK_SPEED * 1.3
	process.gravity = Vector3.ZERO
	process.color_ramp = _fade_ramp(Color(0.8, 0.9, 1.0))
	particles.process_material = process
	var mesh := BoxMesh.new()
	mesh.size = Vector3(9.0, 0.06, 0.06)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(2.0, 2.2, 2.6)
	mesh.material = material
	particles.draw_pass_1 = mesh
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.emitting = false
	return particles


func _make_clouds() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "Clouds"
	particles.amount = 90
	particles.lifetime = CLOUD_LIFETIME
	particles.preprocess = CLOUD_LIFETIME
	particles.local_coords = true
	particles.visibility_aabb = AABB(CLOUDS_CENTER - CLOUDS_HALF * 3.0, CLOUDS_HALF * 6.0)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	process.emission_point_texture = _points_around_hull(256, 2, CLOUDS_CENTER, CLOUDS_HALF, true)
	process.emission_point_count = 256
	process.direction = Vector3.UP
	process.spread = 5.0
	process.initial_velocity_min = CLOUD_SPEED
	process.initial_velocity_max = CLOUD_SPEED * 1.4
	process.gravity = Vector3.ZERO
	process.scale_min = 0.6
	process.scale_max = 1.4
	process.angle_min = -180.0
	process.angle_max = 180.0
	process.color_ramp = _fade_ramp(Color(cloud_color, 0.55))
	particles.process_material = process
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE * CLOUD_SIZE
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = _puff_texture()
	material.disable_receive_shadows = true
	# The clouds are the fog.
	material.disable_fog = true
	mesh.material = material
	particles.draw_pass_1 = mesh
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.emitting = false
	return particles


## Fades in and out over a particle's life.
static func _fade_ramp(color: Color) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = [0.0, 0.2, 0.8, 1.0]
	gradient.colors = [Color(color, 0.0), color, color, Color(color, 0.0)]
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


## A soft round puff.
static func _puff_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = [0.0, 1.0]
	gradient.colors = [Color.WHITE, Color(1.0, 1.0, 1.0, 0.0)]
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = 64
	texture.height = 64
	return texture


## `count` emission points in the box `center` ± `half`, none over the hull's footprint above its
## bottom (with `beside`, none over the footprint at all). Fixed by `seed_value`, so every ship
## looks the same.
static func _points_around_hull(
	count: int, seed_value: int, center: Vector3, half: Vector3, beside: bool = false
) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var image := Image.create_empty(count, 1, false, Image.FORMAT_RGBF)
	var placed: int = 0
	while placed < count:
		var at: Vector3 = (
			center
			+ (
				Vector3(
					rng.randf_range(-1.0, 1.0),
					rng.randf_range(-1.0, 1.0),
					rng.randf_range(-1.0, 1.0)
				)
				* half
			)
		)
		if (at.y > HULL_BOTTOM or beside) and HULL_FOOTPRINT.has_point(Vector2(at.x, at.z)):
			continue
		image.set_pixel(placed, 0, Color(at.x, at.y, at.z))
		placed += 1
	return ImageTexture.create_from_image(image)
