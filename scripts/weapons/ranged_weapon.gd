class_name RangedWeapon
extends Weapon
## Fires projectiles from the muzzle per attack: along the aim direction, or straight at the locked
## target. With several pellets per shot (`settings.pellets`) they fly in an even fan
## (`settings.spread`) around that direction.

@export var settings: RangedWeaponSettings
@export var projectile_scene: PackedScene

@onready var _muzzle: Marker3D = $Muzzle


func _attack() -> void:
	var direction: Vector3 = aim_direction
	if is_instance_valid(aim_target) and not aim_target.dead:
		direction = _muzzle.global_position.direction_to(aim_target.get_aim_point())
	var spread: float = deg_to_rad(settings.spread)
	for pellet: int in settings.pellets:
		var angle: float = 0.0
		if settings.pellets > 1:
			angle = lerpf(-spread * 0.5, spread * 0.5, float(pellet) / (settings.pellets - 1))
		_fire(direction.rotated(Vector3.UP, angle))


func _get_settings() -> WeaponSettings:
	return settings


## Projectiles don't hit the holder and are added to its parent, so they fly on independently.
## They start inside the holder and travel to the muzzle first: a muzzle poking into a wall
## would otherwise spawn them inside it, where the ray doesn't detect it.
func _fire(direction: Vector3) -> void:
	var muzzle: Vector3 = _muzzle.global_position
	var projectile := projectile_scene.instantiate() as Projectile
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
