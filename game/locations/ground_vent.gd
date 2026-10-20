class_name GroundVent
extends GroundHazard
## A vent in the ground (the Ash fields' hazard, see `LocationBiome.Hazard.VENTS`): it rests a
## while, then glows and rumbles for `warning` s and bursts, hurting every player and alien
## standing on it (`hurt`). Readable and avoidable: its reach is painted on the ground, and the glow
## and a rising rumble come first. Greybox: a cone, a glowing disc over its reach and a plume of
## fire. All values TBD (playtest).

## How opaque the disc glows while the vent rests (a hint where it reaches) and when it bursts.
const RESTING_GLOW: float = 0.08
const FULL_GLOW: float = 0.85
## How often the glow pulses while it warns, per s.
const PULSE: float = 5.0
const GLOW_COLOR := Color(1.0, 0.42, 0.08)
## How long the plume lasts, in s, and how high it rises, in m.
const PLUME_TIME: float = 0.9
const PLUME_HEIGHT: float = 4.0
## How far the cone shakes while it rumbles, in m.
const RUMBLE: float = 0.04

## The rumble during the warning (as long as the default `warning`) and the burst.
const RUMBLE_SOUND: Sound = preload("res://assets/audio/sfx/biomes/vent_rumble.tres")
const BURST_SOUND: Sound = preload("res://assets/audio/sfx/biomes/vent_burst.tres")

## How long it rests between bursts (shortest, longest), in s.
@export var rest: Vector2 = Vector2(6.0, 12.0)
## How long it glows and rumbles before it bursts, in s.
@export var warning: float = 1.5
## Damage of a burst.
@export var damage: float = 15.0
## How far the burst reaches, in m (the disc; the collision shape is set by whoever adds it).
@export var radius: float = 3.0

## Time until the next burst, in s.
var _until_burst: float = 0.0
## Time the plume still shows, in s.
var _plume_left: float = 0.0
var _cone: MeshInstance3D
var _disc_material: StandardMaterial3D
## The plume grows from its base, at the ground.
var _plume: Node3D
var _plume_material: StandardMaterial3D


func _ready() -> void:
	super()
	_until_burst = randf_range(rest.x, rest.y) + warning
	_build()
	_show(0.0)


func _physics_process(delta: float) -> void:
	var resting: bool = not is_warning()
	_until_burst -= delta
	if resting and is_warning():
		Sfx.play_at(RUMBLE_SOUND, global_position)
	if _until_burst <= 0.0:
		hurt(damage)
		Sfx.play_at(BURST_SOUND, global_position)
		_plume_left = PLUME_TIME
		_until_burst = randf_range(rest.x, rest.y) + warning
	_plume_left = maxf(_plume_left - delta, 0.0)
	_show(1.0 - clampf(_until_burst / warning, 0.0, 1.0))


## Whether it glows and rumbles, about to burst.
func is_warning() -> bool:
	return _until_burst <= warning


## Seconds until it bursts next.
func time_to_burst() -> float:
	return _until_burst


## Shows how far the warning is (`warned`: 0 resting, 1 bursting) and the plume.
func _show(warned: float) -> void:
	var pulse: float = 0.8 + 0.2 * sin(_until_burst * TAU * PULSE) if warned > 0.0 else 1.0
	var glow: float = lerpf(RESTING_GLOW, FULL_GLOW, sqrt(warned)) * pulse
	_disc_material.albedo_color = Color(GLOW_COLOR, glow)
	var shake: float = RUMBLE * warned if warned > 0.0 else 0.0
	_cone.position = Vector3(randf_range(-shake, shake), 0.0, randf_range(-shake, shake))
	_plume.visible = _plume_left > 0.0
	if _plume.visible:
		var shown: float = 1.0 - _plume_left / PLUME_TIME
		_plume.scale = Vector3(1.0, maxf(ease(shown * 4.0, 0.4), 0.01), 1.0)
		_plume_material.albedo_color = Color(GLOW_COLOR.lightened(0.3), 0.9 * (1.0 - shown * shown))


func _build() -> void:
	_cone = MeshInstance3D.new()
	_cone.name = "Cone"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.35
	cone.bottom_radius = 1.1
	cone.height = 0.5
	_cone.mesh = cone
	var crust := StandardMaterial3D.new()
	crust.albedo_color = Color(0.1, 0.09, 0.09)
	crust.roughness = 1.0
	_cone.material_override = crust
	add_child(_cone)
	var disc := MeshInstance3D.new()
	disc.name = "Glow"
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = radius
	disc_mesh.bottom_radius = radius
	disc_mesh.height = 0.04
	disc_mesh.radial_segments = 32
	disc.mesh = disc_mesh
	disc.position.y = 0.05
	_disc_material = _glowing()
	disc.material_override = _disc_material
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)
	_plume = Node3D.new()
	_plume.name = "Plume"
	add_child(_plume)
	var column := MeshInstance3D.new()
	column.name = "Column"
	var plume := CylinderMesh.new()
	plume.top_radius = radius * 0.5
	plume.bottom_radius = 0.6
	plume.height = PLUME_HEIGHT
	column.mesh = plume
	column.position.y = PLUME_HEIGHT * 0.5
	_plume_material = _glowing()
	column.material_override = _plume_material
	column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_plume.add_child(column)


static func _glowing() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
