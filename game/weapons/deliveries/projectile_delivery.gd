class_name ProjectileDelivery
extends WeaponDelivery
## Fires projectiles from the weapon's muzzle: along the aim direction, or straight at the locked
## target. With several pellets per shot (more with the MK level of the weapon's pellets) they fly
## in an even fan (`spread`) around that direction. All values TBD (playtest).

const PROJECTILE: PackedScene = preload("res://game/weapons/projectile.tscn")

## Projectile speed in m/s.
@export var speed: float = 30.0
## Distance in m after which a projectile disappears.
@export var reach: float = 25.0
## Projectiles per shot at MK1 (Brask fires several).
@export var pellets: int = 1
## Width of the fan the pellets fly in, around the attack direction, in degrees.
@export var spread: float = 0.0
## What flies; the plain projectile when null.
@export var projectile_scene: PackedScene


func attack(weapon: Weapon) -> void:
	var muzzle: Vector3 = weapon.get_muzzle().global_position
	var direction: Vector3 = weapon.aim_direction
	if PlayerAim.is_lockable(weapon.aim_target):
		direction = muzzle.direction_to(PlayerAim.aim_point(weapon.aim_target))
	var count: int = pellets_of(weapon)
	var fan: float = deg_to_rad(spread)
	for pellet: int in count:
		var angle: float = 0.0
		if count > 1:
			angle = lerpf(-fan * 0.5, fan * 0.5, float(pellet) / (count - 1))
		_fire(weapon, direction.rotated(Vector3.UP, angle))


## Pellets per shot of `weapon`, with its MK level.
func pellets_of(weapon: Weapon) -> int:
	return maxi(1, roundi(pellets * weapon.multiplier(WeaponPart.Stat.PELLETS)))


## Projectiles don't hit the holder and are added to its parent, so they fly on independently.
## They start inside the holder and travel to the muzzle first: a muzzle poking into a wall
## would otherwise spawn them inside it, where the ray doesn't detect it.
func _fire(weapon: Weapon, direction: Vector3) -> void:
	var holder: CollisionObject3D = weapon.holder
	var muzzle: Vector3 = weapon.get_muzzle().global_position
	var projectile := (
		(projectile_scene if projectile_scene else PROJECTILE).instantiate() as Projectile
	)
	var hit: Hit = weapon.make_hit(direction, muzzle)
	projectile.velocity = direction * speed
	projectile.max_distance = reach
	projectile.damage = hit.damage
	projectile.stagger = hit.stagger
	projectile.push = hit.push
	projectile.exclude = [holder.get_rid()]
	projectile.shooter = holder
	holder.get_parent().add_child(projectile)
	projectile.global_position = Vector3(
		holder.global_position.x, muzzle.y, holder.global_position.z
	)
	projectile.move_to(muzzle)
	projectile.reset_physics_interpolation()
