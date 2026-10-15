class_name OreScanner
extends Node3D
## The ore scanner (a skill): a small arrow on the ground around the player, in the ore's color,
## that points to the nearest ore node within `reach` (the skill's value) while the player is
## outside, with or without a miner on it. It hides within `min_distance` of the node.
## Like the arrow back to the ship, but shorter and closer to the player.

## Distance from the player to the arrow's center, in m.
const ARROW_DISTANCE: float = 2.2
const ALPHA: float = 0.75

## How far it looks for ore nodes (m); 0: off (the skill isn't learned).
var reach: float = 0.0
## How close (m) a node may be before the arrow hides (the miner placing range: it's in reach).
var min_distance: float = 2.5
## The node it points to, or null.
var target: OreNode

var _material := StandardMaterial3D.new()
var _arrow := MeshInstance3D.new()


func _ready() -> void:
	var mesh := PrismMesh.new()
	mesh.size = Vector3(0.55, 0.6, 0.03)
	_arrow.mesh = mesh
	# Lies flat on the ground, the tip pointing along -Z.
	_arrow.transform = Transform3D(
		Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP), Vector3(0.0, 0.0, -ARROW_DISTANCE)
	)
	_arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# A projection on the ground: stays visible when it points behind the player's body.
	_material.no_depth_test = true
	_arrow.material_override = _material
	add_child(_arrow)
	visible = false


func _physics_process(_delta: float) -> void:
	target = _find_target()
	visible = target != null
	if not visible:
		return
	var offset: Vector3 = target.global_position - global_position
	# Runs after the player turned this tick, so the arrow keeps pointing at the node.
	global_basis = Basis(Vector3.UP, atan2(-offset.x, -offset.z))
	_material.albedo_color = Color(target.ore_type.color, ALPHA)


func _find_target() -> OreNode:
	var player := get_parent() as Player
	if reach <= 0.0 or not player or player.dead:
		return null
	var ship: Ship = Ship.nearest(get_tree(), global_position)
	if ship and ship.is_aboard(player):
		return null
	var nearest: OreNode = null
	var nearest_distance: float = reach
	for node: OreNode in get_tree().get_nodes_in_group(OreNode.GROUP):
		var offset: Vector3 = node.global_position - global_position
		var distance: float = Vector2(offset.x, offset.z).length()
		if distance <= nearest_distance:
			nearest = node
			nearest_distance = distance
	return nearest if nearest and nearest_distance > min_distance else null
