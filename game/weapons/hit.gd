class_name Hit
extends RefCounted
## One hit of a weapon on an alien (a projectile, a swing, a flame, a beam): what it does to it
## (see `Alien.take_hit`), and to a teammate or miner a mending beam touches (`heal`).

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
## Whether it sprays ichor or sparks where it lands; a continuous weapon's hits mostly don't, so
## ten hits a second don't fill the air.
var spray: bool = true
## Damage per second it sets the target burning with, and for how many seconds (see `Burning`).
var burn_damage: float = 0.0
var burn_time: float = 0.0
## Share of its speed an alien keeps for `slow_time` seconds after it (see `SlowEffect`).
var slow: float = 1.0
var slow_time: float = 0.0
## Health it restores to a teammate, or a miner's it repairs (see `HealEffect`).
var heal: float = 0.0


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


## Lands on `target` (an alien or a destructible): its damage past their armor, the damage readout
## and, if it burns, sets them burning. Returns the damage that got through (0 for anything else).
func land_on(target: Node3D) -> float:
	var dealt: float = 0.0
	if target is Alien:
		dealt = (target as Alien).take_hit(self)
	elif target is Destructible:
		dealt = (target as Destructible).take_hit(self)
	else:
		return 0.0
	DamageNumber.show_hit(attacker, target, dealt)
	if burn_time > 0.0 and burn_damage > 0.0:
		Burning.ignite(target, burn_damage, burn_time, attacker)
	return dealt
