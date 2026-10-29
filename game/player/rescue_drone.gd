class_name RescueDrone
extends Node3D
## The rescue drone (a skill): a small drone sitting on the `holder`'s backpack while it's ready
## (learned and not used this run). While it's ready, the holder goes down at zero health instead
## of dying (`PlayerVitals.bleed_out`): the drone flies out with a flash that staggers and pushes
## away the aliens within `PlayerSettings.rescue_flash_range`, hovers over the body shining a light
## on it, and gets it up with `PlayerSettings.rescue_health` of its health (nothing carried is
## lost). Aliens leave a downed player alone meanwhile and walk back towards their nest; the drone
## waits at least `PlayerSettings.rescue_time` and then for a gap (no alien within
## `PlayerSettings.rescue_gap`), at most `PlayerSettings.rescue_wait`. Then it burns out and is gone
## until the next run (`restock`, when the ramp opens for one). The suit ring shows it as a tick on
## the health arc. A greybox model built in code. It follows the backpack (the model's `CargoRack`
## marker) and sits on top of it.

enum State { DOCKED, RESCUING, BURNING_OUT }

## Where it sits on the backpack (on top of its frame), from the cargo rack's origin.
const DOCK := Vector3(-0.17, CargoRack.TUBE_HEIGHT + 0.27, -0.08)
## How far above the ground it hovers over the body (m) and how fast it gets there (higher =
## quicker).
const HOVER_HEIGHT: float = 1.3
const FLY_RATE: float = 6.0
## Its size in flight, so it reads from the game's camera (docked it fits the backpack).
const FLIGHT_SCALE: float = 1.6
## Seconds its flash takes to fade, and how bright its light flares meanwhile (energy).
const FLASH_TIME: float = 0.6
const FLASH_ENERGY: float = 8.0
## Seconds it takes to burn out once the holder is up.
const BURN_OUT_TIME: float = 0.6
## The bleed-out while it's ready: longer than the longest wait, so the drone always gets there
## first.
const BLEED_OUT_MARGIN: float = 1.0
const LIGHT_COLOR := Color(0.55, 1.0, 0.75)
## How far its light reaches while it hovers (m).
const LIGHT_RANGE: float = 2.5
const BODY_COLOR := Color(0.24, 0.26, 0.29)
## Turns per second of the rotors while it flies.
const ROTOR_SPEED: float = 9.0

## The player it belongs to.
var holder: Player
## Whether it was used this run.
var used: bool = false
var state: State = State.DOCKED
## Seconds until it gets the holder up at the latest (while rescuing), or until it's gone (while
## burning out).
var time_left: float = 0.0

## The model: on the backpack while docked, flying on its own (top level) otherwise.
var _model: Node3D
var _rotors: Array[Node3D] = []
var _beam: MeshInstance3D
var _light: OmniLight3D
var _lamp_material := StandardMaterial3D.new()
## The flash: a sphere growing to the flash's range while it fades, where the holder went down.
var _flash: MeshInstance3D
var _flash_material := StandardMaterial3D.new()
var _flash_left: float = 0.0
var _flash_at := Vector3.ZERO
var _time: float = 0.0


func _ready() -> void:
	_build()
	holder.vitals.went_down.connect(_on_went_down)
	_dock()


## Whether it would get the holder up right now: learned and not used this run.
func is_ready() -> bool:
	return holder.skills.has(Skill.Effect.RESCUE_DRONE) and not used


## Ready again for a new run.
func restock() -> void:
	used = false
	_dock()


func _physics_process(delta: float) -> void:
	_time += delta
	var flash: float = _update_flash(delta)
	match state:
		State.DOCKED:
			var drone_ready: bool = is_ready()
			_model.visible = drone_ready
			holder.vitals.bleed_out = (
				holder.settings.rescue_wait + BLEED_OUT_MARGIN if drone_ready else 0.0
			)
		State.RESCUING:
			# Over the backpack (it follows the body lying down), not the feet.
			var over: Vector3 = global_position
			over.y = holder.global_position.y + HOVER_HEIGHT
			_fly_to(over, delta)
			time_left = maxf(time_left - delta, 0.0)
			var pulse: float = 0.5 + 0.5 * sin(_time * TAU * 2.0)
			_light.light_energy = 0.6 + 0.6 * pulse + FLASH_ENERGY * flash
			_light.omni_range = lerpf(LIGHT_RANGE, holder.settings.rescue_flash_range, flash)
			_lamp_material.emission_energy_multiplier = 2.0 + 2.0 * pulse
			_beam.visible = true
			var waited: float = holder.settings.rescue_wait - time_left
			if time_left == 0.0 or (waited >= holder.settings.rescue_time and not _alien_near()):
				_rescue()
		State.BURNING_OUT:
			time_left = maxf(time_left - delta, 0.0)
			var share: float = time_left / BURN_OUT_TIME
			_model.scale = Vector3.ONE * FLIGHT_SCALE * maxf(share, 0.01)
			_light.light_energy = 2.0 * share
			_lamp_material.emission_energy_multiplier = 4.0 * share
			if time_left == 0.0:
				_dock()
	var spinning: bool = state != State.DOCKED
	for rotor: Node3D in _rotors:
		if spinning:
			rotor.rotate_y(TAU * ROTOR_SPEED * delta)


## The holder went down: with the drone ready, it flies out with a flash to get them up.
func _on_went_down() -> void:
	if not is_ready() or state != State.DOCKED:
		return
	used = true
	# This fall is already down; the next one dies.
	holder.vitals.bleed_out = 0.0
	state = State.RESCUING
	time_left = holder.settings.rescue_wait
	_model.top_level = true
	_model.scale = Vector3.ONE * FLIGHT_SCALE
	_model.visible = true
	_light.visible = true
	_drive_away()


## The flash: the aliens close by are staggered and pushed away.
func _drive_away() -> void:
	var settings: PlayerSettings = holder.settings
	_flash_at = holder.global_position
	_flash_left = FLASH_TIME
	_flash.visible = true
	for alien: Alien in get_tree().get_nodes_in_group(Alien.GROUP):
		var away: Vector3 = alien.global_position - _flash_at
		away.y = 0.0
		if alien.dead or away.length() > settings.rescue_flash_range:
			continue
		var direction: Vector3 = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
		alien.stagger_for(settings.rescue_flash_stagger, direction * settings.rescue_flash_push)


## The flash's sphere growing and fading. Returns how much of it is left (1 at its start, 0 once
## it's gone).
func _update_flash(delta: float) -> float:
	if _flash_left == 0.0:
		return 0.0
	_flash_left = maxf(_flash_left - delta, 0.0)
	var share: float = _flash_left / FLASH_TIME
	var spread: float = maxf(1.0 - share * share, 0.01)
	_flash.global_transform = Transform3D(
		Basis.from_scale(Vector3.ONE * holder.settings.rescue_flash_range * spread), _flash_at
	)
	_flash_material.albedo_color.a = 0.25 * share * share * share
	_flash.visible = _flash_left > 0.0
	return share


## Whether a living alien is within `PlayerSettings.rescue_gap` of the holder.
func _alien_near() -> bool:
	for alien: Alien in get_tree().get_nodes_in_group(Alien.GROUP):
		if not alien.dead and alien.horizontal_distance(holder) <= holder.settings.rescue_gap:
			return true
	return false


## Gets the holder up and burns out.
func _rescue() -> void:
	holder.vitals.get_up(holder.settings.rescue_health)
	state = State.BURNING_OUT
	time_left = BURN_OUT_TIME
	_beam.visible = false
	_light.omni_range = LIGHT_RANGE


## Back on the backpack (hidden while it isn't ready).
func _dock() -> void:
	state = State.DOCKED
	time_left = 0.0
	_model.top_level = false
	_model.transform = Transform3D(Basis.IDENTITY, DOCK)
	_model.visible = holder != null and is_ready()
	_beam.visible = false
	_light.visible = false
	_light.omni_range = LIGHT_RANGE
	_flash.visible = false
	_flash_left = 0.0
	_lamp_material.emission_energy_multiplier = 1.0


func _fly_to(target: Vector3, delta: float) -> void:
	_model.global_position = _model.global_position.lerp(target, 1.0 - exp(-FLY_RATE * delta))
	_model.global_basis = Basis.from_scale(Vector3.ONE * FLIGHT_SCALE)
	# In the model's own (scaled) units.
	var to_ground: float = (
		maxf(_model.global_position.y - holder.global_position.y, 0.1) / FLIGHT_SCALE
	)
	_beam.scale = Vector3(1.0, to_ground, 1.0)
	_beam.position.y = -to_ground * 0.5


## A flat body with four rotors on crossed arms, a lamp below and the light it shines down.
func _build() -> void:
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = BODY_COLOR
	metal.metallic = 0.7
	metal.roughness = 0.4
	var body := SphereMesh.new()
	body.radius = 0.06
	body.height = 0.05
	body.material = metal
	_add_part(body, Vector3.ZERO)
	for side: float in [-1.0, 1.0]:
		var arm := BoxMesh.new()
		arm.size = Vector3(0.22, 0.012, 0.014)
		arm.material = metal
		var part: MeshInstance3D = _add_part(arm, Vector3.ZERO)
		part.rotation.y = side * PI * 0.25
	var blade_material := StandardMaterial3D.new()
	blade_material.albedo_color = Color(0.6, 0.65, 0.7, 0.45)
	blade_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for corner: Vector3 in [
		Vector3(0.078, 0.012, 0.078),
		Vector3(-0.078, 0.012, 0.078),
		Vector3(0.078, 0.012, -0.078),
		Vector3(-0.078, 0.012, -0.078)
	]:
		var blade := BoxMesh.new()
		blade.size = Vector3(0.07, 0.003, 0.012)
		blade.material = blade_material
		_rotors.append(_add_part(blade, corner))
	_lamp_material.albedo_color = LIGHT_COLOR
	_lamp_material.emission_enabled = true
	_lamp_material.emission = LIGHT_COLOR
	var lamp := SphereMesh.new()
	lamp.radius = 0.016
	lamp.height = 0.032
	lamp.material = _lamp_material
	_add_part(lamp, Vector3(0.0, -0.022, 0.0))
	var beam_material := StandardMaterial3D.new()
	beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam_material.albedo_color = Color(LIGHT_COLOR, 0.18)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.03
	cone.bottom_radius = 0.35
	cone.height = 1.0
	cone.cap_top = false
	cone.cap_bottom = false
	cone.material = beam_material
	_beam = MeshInstance3D.new()
	_beam.name = "Beam"
	_beam.mesh = cone
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_model.add_child(_beam)
	_light = OmniLight3D.new()
	_light.name = "Light"
	_light.light_color = LIGHT_COLOR
	_light.omni_range = LIGHT_RANGE
	_light.shadow_enabled = false
	_light.position.y = -0.05
	_model.add_child(_light)
	RenderLayers.put(_model, RenderLayers.CHARACTERS)
	_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_flash_material.albedo_color = Color(LIGHT_COLOR, 0.0)
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.material = _flash_material
	_flash = MeshInstance3D.new()
	_flash.name = "Flash"
	_flash.mesh = sphere
	_flash.top_level = true
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flash)
	RenderLayers.put(_flash, RenderLayers.CHARACTERS)


func _add_part(mesh: Mesh, at: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = at
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_model.add_child(part)
	return part
