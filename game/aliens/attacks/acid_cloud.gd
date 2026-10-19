class_name AcidCloud
extends AcidPuddle
## The acid cloud a bloater leaves when it bursts (`AlienBurst`): a low, glowing haze that hurts
## everyone in it, players, miners and aliens alike (past their armor, like burning ground), and
## thins out at the end. Greybox look, TBD (playtest).

## How high the cloud reaches (m).
const HEIGHT: float = 2.2
## How strongly the acid shows on the ground under it (a wide area: fainter than a puddle).
const GROUND_OPACITY: float = 0.2
## How strongly each puff of the haze shows.
const PUFF_ALPHA: float = 0.09

var _puffs: CPUParticles3D


## Leaves a cloud at `point` (global) in `parent`.
static func release(
	parent: Node, point: Vector3, size: float, duration: float, damage: float
) -> AcidCloud:
	var cloud := AcidCloud.new()
	cloud.radius = size
	cloud.lifetime = duration
	cloud.damage_per_second = damage
	cloud.reach_height = HEIGHT
	cloud.opacity = GROUND_OPACITY
	parent.add_child(cloud)
	cloud.global_position = point
	return cloud


## Splashes `amount` on everyone in it at once (the burst), except `source`.
func splash(amount: float, source: Alien) -> void:
	for node: Node3D in _victims():
		if node != source:
			_hurt_one(node, amount)
	HitSpray.spawn(get_parent(), global_position + Vector3.UP * 0.8, Vector3.UP, false)


func _ready() -> void:
	super()
	var haze := CPUParticles3D.new()
	haze.name = "Haze"
	var puff := SphereMesh.new()
	puff.radius = 0.5
	puff.height = 1.0
	puff.radial_segments = 8
	puff.rings = 4
	var puff_material := StandardMaterial3D.new()
	puff_material.albedo_color = Color(Alien.COLOR_GLOW, PUFF_ALPHA)
	puff_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	puff.material = puff_material
	haze.mesh = puff
	haze.amount = 30
	haze.lifetime = 1.6
	haze.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	haze.emission_sphere_radius = radius * 0.8
	haze.direction = Vector3.UP
	haze.spread = 60.0
	haze.gravity = Vector3(0.0, 0.3, 0.0)
	haze.initial_velocity_min = 0.1
	haze.initial_velocity_max = 0.4
	haze.scale_amount_min = 1.0
	haze.scale_amount_max = 2.2
	haze.position.y = 0.8
	haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(haze)
	_puffs = haze


func _process(delta: float) -> void:
	super(delta)
	if _left < FADE_TIME:
		_puffs.emitting = false


## Players, miners and aliens in it.
func _victims() -> Array[Node3D]:
	var inside: Array[Node3D] = []
	for group: StringName in [Player.GROUP, Miner.GROUP, Alien.GROUP]:
		for node: Node3D in get_tree().get_nodes_in_group(group):
			if covers(node):
				inside.append(node)
	return inside


func _hurt(amount: float) -> void:
	for node: Node3D in _victims():
		_hurt_one(node, amount)


func _hurt_one(node: Node3D, amount: float) -> void:
	if node is Alien:
		(node as Alien).take_damage(amount)
	else:
		Alien.hurt(node, amount, global_position)
