class_name Hit
extends RefCounted
## One hit of a weapon on an alien (a projectile, a swing): what it does to it (see
## `Alien.take_hit`).

## Damage before the alien's armor.
var damage: float
## Stagger it adds (see `DamageEffect.stagger`).
var stagger: float
## How hard it pushes the alien back, in m/s (see `DamageEffect.push`).
var push: float
## Horizontal unit vector the hit travels along (from the attacker to the alien).
var direction: Vector3
## Where it lands, in world space.
var point: Vector3
## Who dealt it (e.g. for the damage readout), or null.
var attacker: Node


func _init(
	hit_damage: float,
	hit_stagger: float,
	hit_push: float,
	hit_direction: Vector3,
	hit_point: Vector3,
	hit_attacker: Node = null
) -> void:
	damage = hit_damage
	stagger = hit_stagger
	push = hit_push
	direction = Vector3(hit_direction.x, 0.0, hit_direction.z).normalized()
	point = hit_point
	attacker = hit_attacker
