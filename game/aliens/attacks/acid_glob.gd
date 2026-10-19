class_name AcidGlob
extends Node3D
## A glob of acid a spitter lobbed (`AlienSpit`): it flies in an arc to where its target stood,
## glowing and dripping, while a ring on the ground shows where it lands. There it splashes whoever
## is close (players and miners) and leaves a burning puddle (`AcidPuddle`). It flies over
## everything: rocks and gaps don't stop it. The ring starts wider than the splash and closes in
## on it as the glob comes down (so it doesn't read as the suit ring). Greybox look, TBD (playtest).

const COLOR := Alien.COLOR_GLOW
## Size of the glob, and of its drops (m).
const RADIUS: float = 0.22
const DROP_RADIUS: float = 0.05
## Width of the ring on the ground (m), how much wider than the splash it starts, and how fast it
## pulses (per second).
const RING_WIDTH: float = 0.12
const RING_START: float = 2.0
const RING_PULSE: float = 4.0
## How strongly the splash's area is filled in under the ring.
const FILL_ALPHA: float = 0.18
## Who stands this much higher or lower than the landing spot isn't splashed (m).
const SPLASH_HEIGHT: float = 1.5

## Where it leaves and lands, how high the arc rises and how long it flies.
var start: Vector3
var landing: Vector3
var arc_height: float = 1.0
var flight_time: float = 1.0
## Damage of the splash, the puddle's damage per second (both scaled by the alien's tier), and the
## spit's other values.
var damage: float = 0.0
var puddle_damage: float = 0.0
var spit: AlienSpit
## Where the spit came from, for the players' hit marks.
var from := Vector3.INF

var _elapsed: float = 0.0
var _ring_material := StandardMaterial3D.new()
var _ring: MeshInstance3D


## Lobs a glob of `spit` from `mouth` to `target_point`, for `alien` (in its parent).
static func launch(
	alien: Alien, of_spit: AlienSpit, mouth: Vector3, target_point: Vector3
) -> AcidGlob:
	var glob := AcidGlob.new()
	glob.spit = of_spit
	glob.start = mouth
	glob.landing = target_point
	var distance: float = Vector2(target_point.x - mouth.x, target_point.z - mouth.z).length()
	glob.flight_time = maxf(distance / of_spit.glob_speed, of_spit.min_flight_time)
	glob.arc_height = distance * of_spit.arc_per_meter
	glob.damage = of_spit.damage * alien.damage_factor
	glob.puddle_damage = of_spit.puddle_damage * alien.damage_factor
	glob.from = alien.global_position
	alien.get_parent().add_child(glob)
	glob.global_position = mouth
	return glob


func _ready() -> void:
	var glow := StandardMaterial3D.new()
	glow.albedo_color = COLOR
	glow.emission_enabled = true
	glow.emission = COLOR
	glow.emission_energy_multiplier = 3.0
	var ball := SphereMesh.new()
	ball.radius = RADIUS
	ball.height = RADIUS * 2.0
	ball.material = glow
	var body := MeshInstance3D.new()
	body.name = "Glob"
	body.mesh = ball
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(body)
	add_child(_drops(glow))
	_ring = _make_ring()
	add_child(_ring)
	add_child(_fill())


func _physics_process(delta: float) -> void:
	_elapsed += delta
	var t: float = minf(_elapsed / flight_time, 1.0)
	global_position = start.lerp(landing, t) + Vector3.UP * arc_height * 4.0 * t * (1.0 - t)
	if t >= 1.0:
		_land()


func _process(_delta: float) -> void:
	var wave: float = 0.5 + 0.5 * sin(_elapsed * TAU * RING_PULSE)
	_ring_material.albedo_color.a = lerpf(0.45, 0.95, wave)
	var closing: float = lerpf(RING_START, 1.0, minf(_elapsed / flight_time, 1.0))
	_ring.scale = Vector3(closing, 0.15, closing)


func _land() -> void:
	var parent: Node = get_parent()
	for player: Player in get_tree().get_nodes_in_group(Player.GROUP):
		if _splashes(player):
			Alien.hurt(player, damage, from)
	for miner: Miner in get_tree().get_nodes_in_group(Miner.GROUP):
		if _splashes(miner):
			Alien.hurt(miner, damage, from)
	HitSpray.spawn(parent, landing, Vector3.UP, false)
	AcidPuddle.spawn(parent, landing, spit.puddle_radius, spit.puddle_time, puddle_damage)
	queue_free()


func _splashes(node: Node3D) -> bool:
	var offset: Vector3 = node.global_position - landing
	if absf(offset.y) > SPLASH_HEIGHT:
		return false
	var radius: float = spit.splash_radius + ((node as Miner).body_radius if node is Miner else 0.0)
	return Vector2(offset.x, offset.z).length() <= radius


func _drops(glow: StandardMaterial3D) -> CPUParticles3D:
	var drop := SphereMesh.new()
	drop.radius = DROP_RADIUS
	drop.height = DROP_RADIUS * 2.0
	drop.radial_segments = 6
	drop.rings = 3
	drop.material = glow
	var drops := CPUParticles3D.new()
	drops.name = "Drops"
	drops.mesh = drop
	drops.local_coords = false
	drops.amount = 16
	drops.lifetime = 0.4
	drops.gravity = Vector3(0.0, -9.8, 0.0)
	drops.initial_velocity_min = 0.2
	drops.initial_velocity_max = 0.8
	drops.direction = Vector3.UP
	drops.spread = 180.0
	drops.scale_amount_min = 0.5
	drops.scale_amount_max = 1.0
	return drops


## The ring on the ground where it lands, closing in on the splash's edge.
func _make_ring() -> MeshInstance3D:
	_ring_material.albedo_color = Color(COLOR, 0.8)
	_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.no_depth_test = false
	var torus := TorusMesh.new()
	torus.outer_radius = spit.splash_radius
	torus.inner_radius = spit.splash_radius - RING_WIDTH
	torus.rings = 32
	torus.ring_segments = 4
	torus.material = _ring_material
	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	ring.mesh = torus
	ring.top_level = true
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.transform = Transform3D(
		Basis.from_scale(Vector3(RING_START, 0.15, RING_START)), landing + Vector3.UP * 0.05
	)
	return ring


## The splash's area, faintly filled in.
func _fill() -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(COLOR, FILL_ALPHA)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var disc := CylinderMesh.new()
	disc.top_radius = spit.splash_radius
	disc.bottom_radius = spit.splash_radius
	disc.height = 0.01
	disc.radial_segments = 32
	disc.rings = 1
	disc.material = material
	var fill := MeshInstance3D.new()
	fill.name = "Fill"
	fill.mesh = disc
	fill.top_level = true
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fill.transform = Transform3D(Basis.IDENTITY, landing + Vector3.UP * 0.03)
	return fill
