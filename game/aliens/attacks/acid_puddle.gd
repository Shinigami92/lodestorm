class_name AcidPuddle
extends Node3D
## A burning puddle of acid where a spitter's glob landed (`AcidGlob`): it hurts players and miners
## standing in it every `TICK` s, not aliens (the hive's own acid), and fades out at the end.
## Greybox look, TBD (playtest).

## How often it hurts, in s.
const TICK: float = 0.5
## Who stands this much higher or lower than the puddle isn't in it (m).
const REACH_HEIGHT: float = 1.0
## Seconds it takes to fade out at the end.
const FADE_TIME: float = 1.0

var radius: float = 1.5
var lifetime: float = 4.0
## Damage per second.
var damage_per_second: float = 6.0

var _left: float
var _until_hurt: float = TICK
var _material := StandardMaterial3D.new()


## Leaves a puddle at `point` (global) in `parent`.
static func spawn(
	parent: Node, point: Vector3, size: float, duration: float, damage: float
) -> AcidPuddle:
	var puddle := AcidPuddle.new()
	puddle.radius = size
	puddle.lifetime = duration
	puddle.damage_per_second = damage
	parent.add_child(puddle)
	puddle.global_position = point
	return puddle


func _ready() -> void:
	_left = lifetime
	_material.albedo_color = Color(Alien.COLOR_GLOW, 0.4)
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.emission_enabled = true
	_material.emission = Alien.COLOR_GLOW
	_material.emission_energy_multiplier = 1.2
	_material.roughness = 0.1
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.04
	disc.radial_segments = 24
	disc.rings = 1
	disc.material = _material
	var mesh := MeshInstance3D.new()
	mesh.name = "Acid"
	mesh.mesh = disc
	mesh.position.y = 0.03
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)


func _physics_process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0:
		queue_free()
		return
	_until_hurt -= delta
	if _until_hurt <= 0.0:
		_until_hurt += TICK
		_hurt(damage_per_second * TICK)


func _process(_delta: float) -> void:
	_material.albedo_color.a = 0.4 * clampf(_left / FADE_TIME, 0.0, 1.0)
	_material.emission_energy_multiplier = 1.2 * clampf(_left / FADE_TIME, 0.0, 1.0)


## Whether `node` stands in it.
func covers(node: Node3D) -> bool:
	var offset: Vector3 = node.global_position - global_position
	if absf(offset.y) > REACH_HEIGHT:
		return false
	var reach: float = radius + ((node as Miner).body_radius if node is Miner else 0.0)
	return Vector2(offset.x, offset.z).length() <= reach


func _hurt(amount: float) -> void:
	for player: Player in get_tree().get_nodes_in_group(Player.GROUP):
		if covers(player):
			Alien.hurt(player, amount, global_position)
	for miner: Miner in get_tree().get_nodes_in_group(Miner.GROUP):
		if covers(miner):
			Alien.hurt(miner, amount, global_position)
