class_name WeaponTarget
extends RefCounted
## What weapons hit, burn and lock on: an alien or a `Destructible` (an alien nest's body). The
## one place that tells the two apart, so weapons, fire and the target lock treat them alike; a new
## kind of target only needs adding here. Everything else (players, miners, rock) isn't one.


## Whether `node` is something weapons hit.
static func is_target(node: Object) -> bool:
	return node is Alien or node is Destructible


## Whether shots, swings and the target lock can reach `node` now: a target that's alive (not
## destroyed), above the ground and in the world.
static func is_hittable(node: Object) -> bool:
	if not is_instance_valid(node):
		return false
	if node is Alien:
		return (node as Alien).is_hittable()
	if node is Destructible:
		return (node as Destructible).is_hittable()
	return false


## Where shots at `node` aim: a target's middle, anything else's origin.
static func aim_point(node: Node3D) -> Vector3:
	if node is Alien:
		return (node as Alien).get_aim_point()
	if node is Destructible:
		return (node as Destructible).get_aim_point()
	return node.global_position


## How far `node`'s edge lies from its middle on the ground (m): a destructible's shape radius,
## else `body` (an alien's body, as the weapon measures it).
static func edge(node: Node3D, body: float = 0.0) -> float:
	if node is Destructible:
		return (node as Destructible).radius()
	return body


## Lands `hit` on `node` past its armor. Returns the damage that got through (0 for anything
## that isn't a target).
static func take_hit(node: Node3D, hit: Hit) -> float:
	if node is Alien:
		return (node as Alien).take_hit(hit)
	if node is Destructible:
		return (node as Destructible).take_hit(hit)
	return 0.0


## Takes `amount` off `node`'s health past its armor, dealt `by` someone (or null) `with` a weapon
## (or null). Returns whether it was a target.
static func take_damage(
	node: Node3D, amount: float, by: Node = null, with: WeaponType = null
) -> bool:
	if node is Alien:
		(node as Alien).take_damage(amount, by, with)
	elif node is Destructible:
		(node as Destructible).take_damage(amount, by, with)
	else:
		return false
	return true
