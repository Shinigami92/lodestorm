class_name SightLine
extends MeshInstance3D
## A line from the weapon's muzzle along its shot while it charges (Quill, see `ChargeTrigger`):
## up to its delivery's reach or the first rock or nest (aliens don't stop it, a full charge
## pierces them), brighter as the charge grows and white when it's full. Teammates see it too.
## A child of the weapon's scene.

## Thickness of the line in m.
@export var width: float = 0.03
## The line's color while charging; white when full.
@export var color := Color(1.0, 0.86, 0.66)

var _material := StandardMaterial3D.new()

@onready var _weapon: Weapon = owner as Weapon


func _ready() -> void:
	top_level = true
	var box := BoxMesh.new()
	box.size = Vector3(width, width, 1.0)
	mesh = box
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false


func _process(_delta: float) -> void:
	var charge: float = _weapon.charge() if _weapon else 0.0
	visible = charge > 0.0 and _weapon.is_visible_in_tree()
	if not visible:
		return
	var from: Vector3 = _weapon.get_muzzle().global_position
	var direction: Vector3 = _weapon.shot_direction()
	var length: float = _length(from, direction)
	var line: Color = AmmoGauge.TIMING if charge >= 1.0 else color
	line.a = lerpf(0.2, 0.8, charge)
	_material.albedo_color = line
	global_transform = Transform3D(
		Basis.looking_at(direction).scaled_local(Vector3(1.0, 1.0, length)),
		from + direction * length * 0.5
	)


## How far the line reaches from `from` along `direction`: to the first rock or nest within the
## delivery's reach.
func _length(from: Vector3, direction: Vector3) -> float:
	var delivery := _weapon.type.delivery as ProjectileDelivery
	var reach: float = delivery.reach if delivery else 20.0
	var to: Vector3 = from + direction * reach
	var exclude: Array[RID] = []
	if _weapon.holder:
		exclude.append(_weapon.holder.get_rid())
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	for _i: int in 8:
		var query := PhysicsRayQueryParameters3D.create(from, to, PhysicsLayers.SHOTS)
		query.exclude = exclude
		var result: Dictionary = space.intersect_ray(query)
		if result.is_empty():
			break
		var collider: Object = result["collider"]
		if not collider is Alien:
			return from.distance_to(result["position"] as Vector3)
		exclude.append((collider as Alien).get_rid())
	return reach
