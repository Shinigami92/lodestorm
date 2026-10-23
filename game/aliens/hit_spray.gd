class_name HitSpray
extends CPUParticles3D
## What flies off an alien where a hit lands, so it reads without numbers: glowing ichor from its
## flesh (in the hive's yellow-green), grey sparks and chips from its armor. Sprays back towards
## the attacker and frees itself when it's done.

## Sparks off armor: hot white fading to the chitin's grey.
const COLOR_SPARK := Color(1.0, 0.95, 0.85)
const COLOR_CHIP := Color(0.35, 0.36, 0.38)
## Drops of ichor, and sparks with chips.
const ICHOR_AMOUNT: int = 8
const SPARK_AMOUNT: int = 10
## Ichor glows: its color is raised past white, so it blooms like the eyes.
const ICHOR_GLOW: float = 1.4
## Width of the spray around its direction, in degrees.
const SPREAD: float = 50.0

static var _ichor_mesh: Mesh
static var _spark_mesh: Mesh


## Sprays at `point`, back against `along` (the way the hit travelled): sparks if it hit armor.
static func spawn(parent: Node, point: Vector3, along: Vector3, armored: bool) -> HitSpray:
	var spray := HitSpray.new()
	spray.layers = RenderLayers.EFFECTS
	spray._setup(armored)
	parent.add_child(spray)
	# Level with the world, so `direction` is too.
	spray.global_transform = Transform3D(Basis.IDENTITY, point)
	var back: Vector3 = -along if along != Vector3.ZERO else Vector3.UP
	spray.direction = (back + Vector3.UP * 0.6).normalized()
	spray.emitting = true
	return spray


func _setup(armored: bool) -> void:
	# Not before it's in place: it would spray where its parent is.
	emitting = false
	one_shot = true
	explosiveness = 1.0
	local_coords = false
	spread = SPREAD
	gravity = Vector3.DOWN * 9.8
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if armored:
		amount = SPARK_AMOUNT
		lifetime = 0.3
		initial_velocity_min = 4.0
		initial_velocity_max = 8.0
		scale_amount_min = 0.5
		scale_amount_max = 1.0
		var ramp := Gradient.new()
		ramp.set_color(0, COLOR_SPARK)
		ramp.set_color(1, COLOR_CHIP)
		color_ramp = ramp
		# Streaks along their flight.
		particle_flag_align_y = true
		mesh = _spark()
	else:
		amount = ICHOR_AMOUNT
		lifetime = 0.5
		initial_velocity_min = 2.0
		initial_velocity_max = 4.5
		scale_amount_min = 0.6
		scale_amount_max = 1.2
		var fade := Gradient.new()
		fade.set_color(0, Alien.COLOR_GLOW)
		fade.set_color(1, Color(Alien.COLOR_GLOW, 0.0))
		fade.add_point(0.6, Alien.COLOR_GLOW)
		color_ramp = fade
		mesh = _ichor()
	finished.connect(queue_free)


static func _ichor() -> Mesh:
	if not _ichor_mesh:
		var sphere := SphereMesh.new()
		sphere.radius = 0.05
		sphere.height = 0.1
		sphere.radial_segments = 6
		sphere.rings = 3
		var glowing: StandardMaterial3D = _material(true)
		glowing.albedo_color = Color(ICHOR_GLOW, ICHOR_GLOW, ICHOR_GLOW)
		sphere.material = glowing
		_ichor_mesh = sphere
	return _ichor_mesh


static func _spark() -> Mesh:
	if not _spark_mesh:
		var box := BoxMesh.new()
		box.size = Vector3(0.025, 0.1, 0.025)
		box.material = _material(false)
		_spark_mesh = box
	return _spark_mesh


## Unshaded, colored per particle; ichor glows and fades out.
static func _material(transparent: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
