class_name RangedWeapon
extends Weapon
## Fires a projectile from the muzzle per attack: along the aim direction, or straight at the locked
## target.

@export var settings: RangedWeaponSettings
@export var projectile_scene: PackedScene

@onready var _muzzle: Marker3D = $Muzzle


## Projectiles don't hit the holder and are added to its parent, so they fly on independently.
## They start inside the holder and travel to the muzzle first: a muzzle poking into a wall
## would otherwise spawn them inside it, where the ray doesn't detect it.
func _attack() -> void:
	var muzzle: Vector3 = _muzzle.global_position
	var projectile := projectile_scene.instantiate() as Projectile
	var direction: Vector3 = aim_direction
	if is_instance_valid(aim_target) and not aim_target.dead:
		direction = muzzle.direction_to(aim_target.get_aim_point())
	projectile.velocity = direction * settings.projectile_speed
	projectile.max_distance = settings.projectile_range
	projectile.damage = settings.damage
	projectile.exclude = [holder.get_rid()]
	holder.get_parent().add_child(projectile)
	projectile.global_position = Vector3(
		holder.global_position.x, muzzle.y, holder.global_position.z
	)
	projectile.move_to(muzzle)
	projectile.reset_physics_interpolation()


func _get_settings() -> WeaponSettings:
	return settings
