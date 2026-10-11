class_name RangedWeapon
extends Weapon
## Fires a projectile from the muzzle per attack.

@export var settings: RangedWeaponSettings
@export var projectile_scene: PackedScene

@onready var _muzzle: Marker3D = $Muzzle


## Projectiles don't hit the holder and are added to its parent, so they fly on independently.
## They start inside the holder and travel to the muzzle first: a muzzle poking into a wall
## would otherwise spawn them inside it, where the ray doesn't detect it.
func _attack() -> void:
	var muzzle: Vector3 = _muzzle.global_position
	var projectile := projectile_scene.instantiate() as Projectile
	projectile.velocity = aim_direction * settings.projectile_speed
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
