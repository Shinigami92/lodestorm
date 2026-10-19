class_name Destructible
extends StaticBody3D
## Something solid that weapons wear down besides aliens (an alien nest's body): health and armor
## like an alien's (a flat reduction per hit, at least `Alien.MIN_DAMAGE_SHARE` gets through),
## shots and swings hit it, and the target lock takes it when no alien is near (see `PlayerAim`).
## Hits spray ichor. Whoever owns it sets its values before it enters the tree and listens to
## `damaged` and `destroyed`; it doesn't move. Its shape is the `CollisionShape3D` child.

## Emitted for every loss of health: how much, and who dealt it (or null: the debug overlay).
signal damaged(amount: float, by: Node)
## Emitted once, when its health reaches zero.
signal destroyed

const GROUP: StringName = &"destructibles"

## Health when unhurt.
@export var max_health: float = 100.0
## Taken off every hit's damage (see `Alien.MIN_DAMAGE_SHARE`).
@export var armor: float = 0.0
## Where shots aim at: this high above its origin (m).
@export var aim_height: float = 1.0

## Current health, from 0 to `max_health`; set to `max_health` when it enters the tree.
var health: float
## Whether its health reached zero; it then takes no more hits and can't be locked on.
var dead: bool = false

@onready var _collision: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	add_to_group(GROUP)
	health = max_health


## Takes `hit` past its armor and sprays. Returns the damage that got through.
func take_hit(hit: Hit) -> float:
	if dead or hit.damage <= 0.0:
		return 0.0
	var dealt: float = hit.damage
	if armor > 0.0:
		dealt = maxf(hit.damage - armor, hit.damage * Alien.MIN_DAMAGE_SHARE)
	if is_inside_tree():
		HitSpray.spawn(get_parent(), hit.point, hit.direction, false)
	take_damage(dealt, hit.attacker)
	return dealt


## Loses `amount` health, past its armor, dealt `by` someone (or null); it's destroyed at zero.
func take_damage(amount: float, by: Node = null) -> void:
	if dead or amount <= 0.0:
		return
	amount = minf(amount, health)
	health -= amount
	damaged.emit(amount, by)
	if health <= 0.0:
		dead = true
		destroyed.emit()


## Whether shots, swings and the target lock can reach it: not destroyed and in the world.
func is_hittable() -> bool:
	return not dead and is_inside_tree()


## Where shots aim at (see `aim_height`).
func get_aim_point() -> Vector3:
	return global_position + Vector3.UP * aim_height


## The radius of its shape on the ground (m): swings reach it at its edge.
func radius() -> float:
	var shape: Shape3D = _collision.shape if _collision else null
	if shape is CylinderShape3D:
		return (shape as CylinderShape3D).radius
	if shape is SphereShape3D:
		return (shape as SphereShape3D).radius
	if shape is CapsuleShape3D:
		return (shape as CapsuleShape3D).radius
	if shape is BoxShape3D:
		var size: Vector3 = (shape as BoxShape3D).size
		return maxf(size.x, size.z) * 0.5
	return 0.0
