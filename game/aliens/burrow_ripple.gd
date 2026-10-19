class_name BurrowRipple
extends Node3D
## The ripple over a burrower under the ground (see `AlienStrain.burrows`): a low mound of earth
## travelling with it and clods thrown up while it moves; before it bursts up (its wind-up) the
## mound swells and the clods fly faster, so whoever stands on it sees it coming. Greybox look, TBD
## (playtest).

## Dark, dusty earth: reads on every biome's ground without taking its color.
const COLOR_EARTH := Color(0.16, 0.13, 0.11)
## The mound's radius and height at rest and how much it swells before the burst (m, share).
const MOUND_RADIUS: float = 0.7
const MOUND_HEIGHT: float = 0.18
const SWELL: float = 1.8
## How fast the mound grows and shrinks (higher = snappier).
const SPEED: float = 10.0

## Whether it shows (the burrower is under the ground), and how strongly: 0 still, 0.5 moving, 1
## about to burst up.
var active: bool = false
var strength: float = 0.0

var _shown: float = 0.0
var _mound: MeshInstance3D
var _clods: CPUParticles3D


func _ready() -> void:
	var earth := StandardMaterial3D.new()
	earth.albedo_color = COLOR_EARTH
	earth.roughness = 1.0
	# Drawn without writing depth (barely see-through), so a player standing on it isn't hidden
	# behind it (no silhouette).
	var mound_earth := earth.duplicate() as StandardMaterial3D
	mound_earth.albedo_color.a = 0.94
	mound_earth.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var dome := SphereMesh.new()
	dome.radius = MOUND_RADIUS
	dome.height = MOUND_RADIUS * 2.0
	dome.is_hemisphere = true
	dome.radial_segments = 16
	dome.rings = 4
	dome.material = mound_earth
	_mound = MeshInstance3D.new()
	_mound.name = "Mound"
	_mound.mesh = dome
	add_child(_mound)
	var clod := BoxMesh.new()
	clod.size = Vector3.ONE * 0.09
	clod.material = earth
	_clods = CPUParticles3D.new()
	_clods.name = "Clods"
	_clods.mesh = clod
	_clods.local_coords = false
	_clods.amount = 24
	_clods.lifetime = 0.6
	_clods.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_clods.emission_sphere_radius = MOUND_RADIUS * 0.6
	_clods.direction = Vector3.UP
	_clods.spread = 35.0
	_clods.gravity = Vector3(0.0, -9.8, 0.0)
	_clods.angular_velocity_min = -360.0
	_clods.angular_velocity_max = 360.0
	_clods.scale_amount_min = 0.5
	_clods.scale_amount_max = 1.2
	_clods.emitting = false
	add_child(_clods)
	_apply()


func _process(delta: float) -> void:
	var goal: float = (0.6 + 0.4 * strength) if active else 0.0
	_shown = lerpf(_shown, goal, 1.0 - exp(-SPEED * delta))
	_apply()


func _apply() -> void:
	var swell: float = lerpf(1.0, SWELL, clampf(strength * 2.0 - 1.0, 0.0, 1.0))
	_mound.visible = _shown > 0.02
	_mound.scale = Vector3(_shown, _shown * MOUND_HEIGHT / MOUND_RADIUS * swell, _shown)
	_clods.emitting = active and strength > 0.1
	_clods.initial_velocity_min = lerpf(1.0, 3.0, strength)
	_clods.initial_velocity_max = lerpf(2.0, 5.0, strength)
