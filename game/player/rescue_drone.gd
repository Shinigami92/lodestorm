class_name RescueDrone
extends Node3D
## The rescue drone (a skill): a small drone sitting on the `holder`'s backpack while it's ready
## (learned and not used this run). While it's ready, the holder goes down at zero health instead
## of dying (`PlayerVitals.bleed_out`): the drone flies out, hovers over the body shining a light
## on it, and after `PlayerSettings.rescue_time` gets it up with `PlayerSettings.rescue_health` of
## its health (nothing carried is lost; aliens leave a downed player alone meanwhile). Then it flies
## off and is gone until the next run (`restock`, when the ramp opens for one). The suit ring shows
## it as a tick on the health arc. A greybox model built in code. It follows the backpack (the
## model's `CargoRack` marker) and sits on top of it.

enum State { DOCKED, RESCUING, LEAVING }

## Where it sits on the backpack (on top of its frame), from the cargo rack's origin.
const DOCK := Vector3(-0.17, CargoRack.TUBE_HEIGHT + 0.27, -0.08)
## How far above the ground it hovers over the body (m) and how fast it gets there (higher =
## quicker).
const HOVER_HEIGHT: float = 1.3
const FLY_RATE: float = 6.0
## Its size in flight, so it reads from the game's camera (docked it fits the backpack).
const FLIGHT_SCALE: float = 1.6
## Seconds it takes to fly off after a rescue, and how far up it goes meanwhile (m).
const LEAVE_TIME: float = 0.8
const LEAVE_RISE: float = 2.5
## The bleed-out while it's ready: longer than the rescue, so the drone always gets there first.
const BLEED_OUT_MARGIN: float = 1.0
const LIGHT_COLOR := Color(0.55, 1.0, 0.75)
const BODY_COLOR := Color(0.24, 0.26, 0.29)
## Turns per second of the rotors while it flies.
const ROTOR_SPEED: float = 9.0

## The player it belongs to.
var holder: Player
## Whether it was used this run.
var used: bool = false
var state: State = State.DOCKED
## Seconds until it gets the holder up (while rescuing), or until it's gone (while leaving).
var time_left: float = 0.0

## The model: on the backpack while docked, flying on its own (top level) otherwise.
var _model := Node3D.new()
var _rotors: Array[Node3D] = []
var _beam := MeshInstance3D.new()
var _light := OmniLight3D.new()
var _lamp_material := StandardMaterial3D.new()
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
	match state:
		State.DOCKED:
			var drone_ready: bool = is_ready()
			_model.visible = drone_ready
			holder.vitals.bleed_out = (
				holder.settings.rescue_time + BLEED_OUT_MARGIN if drone_ready else 0.0
			)
		State.RESCUING:
			# Over the backpack (it follows the body lying down), not the feet.
			var over: Vector3 = global_position
			over.y = holder.global_position.y + HOVER_HEIGHT
			_fly_to(over, delta)
			time_left = maxf(time_left - delta, 0.0)
			var pulse: float = 0.5 + 0.5 * sin(_time * TAU * 2.0)
			_light.light_energy = 0.6 + 0.6 * pulse
			_lamp_material.emission_energy_multiplier = 2.0 + 2.0 * pulse
			_beam.visible = true
			if time_left == 0.0:
				_rescue()
		State.LEAVING:
			time_left = maxf(time_left - delta, 0.0)
			var share: float = time_left / LEAVE_TIME
			_model.global_position += Vector3.UP * LEAVE_RISE / LEAVE_TIME * delta
			_model.scale = Vector3.ONE * FLIGHT_SCALE * maxf(share, 0.01)
			_light.light_energy = share
			if time_left == 0.0:
				_dock()
	var spinning: bool = state != State.DOCKED
	for rotor: Node3D in _rotors:
		if spinning:
			rotor.rotate_y(TAU * ROTOR_SPEED * delta)


## The holder went down: with the drone ready, it flies out to get them up.
func _on_went_down() -> void:
	if not is_ready() or state != State.DOCKED:
		return
	used = true
	# This fall is already down; the next one dies.
	holder.vitals.bleed_out = 0.0
	state = State.RESCUING
	time_left = holder.settings.rescue_time
	_model.top_level = true
	_model.scale = Vector3.ONE * FLIGHT_SCALE
	_model.visible = true
	_light.visible = true


## Gets the holder up and flies off.
func _rescue() -> void:
	holder.vitals.get_up(holder.settings.rescue_health)
	state = State.LEAVING
	time_left = LEAVE_TIME
	_beam.visible = false


## Back on the backpack (hidden while it isn't ready).
func _dock() -> void:
	state = State.DOCKED
	time_left = 0.0
	_model.top_level = false
	_model.transform = Transform3D(Basis.IDENTITY, DOCK)
	_model.visible = holder != null and is_ready()
	_beam.visible = false
	_light.visible = false
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
	_beam.name = "Beam"
	_beam.mesh = cone
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_model.add_child(_beam)
	_light.name = "Light"
	_light.light_color = LIGHT_COLOR
	_light.omni_range = 2.5
	_light.shadow_enabled = false
	_light.position.y = -0.05
	_model.add_child(_light)
	RenderLayers.put(_model, RenderLayers.CHARACTERS)


func _add_part(mesh: Mesh, at: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = at
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_model.add_child(part)
	return part
