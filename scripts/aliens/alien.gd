class_name Alien
extends CharacterBody3D
## Greybox alien: waits until a living player outside the ship comes within
## `settings.detection_range`, then chases the nearest one and attacks it when in reach (the body
## lunges forward). A player gets away by running farther than `settings.chase_range` or by
## going aboard; aliens don't hunt players inside the ship. Loses health when hit (flashes
## white) and dies at zero: it stops, shrinks and disappears.

## Emitted when health reaches zero.
signal died

const GROUP: StringName = &"aliens"

const COLOR_BODY := Color(0.55, 0.08, 0.2)
const COLOR_FLASH := Color(1.0, 1.0, 1.0)
## Seconds a hit flash lasts.
const FLASH_DURATION: float = 0.1
## Seconds the lunge of an attack takes, there and back.
const LUNGE_DURATION: float = 0.25
## How far the body lunges forward when attacking, in m.
const LUNGE_DISTANCE: float = 0.4
## Seconds the body takes to shrink away after dying.
const DEATH_DURATION: float = 0.3

@export var settings: AlienSettings

## Current health, from 0 to `settings.max_health`.
var health: float
## Dead aliens don't move or attack; they disappear after `DEATH_DURATION`.
var dead: bool = false
## The player being chased, or null.
var target: Player

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
## Seconds until the next attack is possible.
var _cooldown: float = 0.0
var _flash_left: float = 0.0
var _lunge_left: float = 0.0
var _material := StandardMaterial3D.new()

@onready var _body: MeshInstance3D = $Body
@onready var _body_position: Vector3 = _body.position
@onready var _collision: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	add_to_group(GROUP)
	health = settings.max_health
	_body.material_override = _material
	_update_look()


func _physics_process(delta: float) -> void:
	if dead:
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	_update_target()

	var move := Vector3.ZERO
	if target:
		var offset: Vector3 = target.global_position - global_position
		offset.y = 0.0
		var distance: float = offset.length()
		if distance > 0.0:
			var target_yaw: float = atan2(-offset.x, -offset.z)
			var yaw: float = lerp_angle(
				rotation.y, target_yaw, 1.0 - exp(-settings.turn_speed * delta)
			)
			basis = Basis(Vector3.UP, yaw)
		if distance > settings.attack_range:
			move = offset / distance
		elif _cooldown == 0.0:
			attack(target)

	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(
		move * settings.move_speed, settings.acceleration * delta
	)
	velocity = Vector3(horizontal.x, velocity.y, horizontal.z)
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= _gravity * delta
	move_and_slide()


func _process(delta: float) -> void:
	_flash_left = maxf(_flash_left - delta, 0.0)
	_lunge_left = maxf(_lunge_left - delta, 0.0)
	_update_look()


## Hits `player` once and waits `1 / settings.attack_rate` until the next attack.
func attack(player: Player) -> void:
	player.take_damage(settings.attack_damage)
	_cooldown = 1.0 / settings.attack_rate
	_lunge_left = LUNGE_DURATION


## Loses `amount` health; dies at zero.
func take_damage(amount: float) -> void:
	if dead or amount <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	_flash_left = FLASH_DURATION
	if health == 0.0:
		_die()


## Whether `player` can be hunted: alive and not aboard a ship.
static func is_prey(tree: SceneTree, player: Player) -> bool:
	if player.dead:
		return false
	for ship: Ship in tree.get_nodes_in_group(Ship.GROUP):
		if ship.is_aboard(player):
			return false
	return true


## Keeps chasing the target while it's in `settings.chase_range`, otherwise picks the nearest
## prey in `settings.detection_range`.
func _update_target() -> void:
	if target and is_instance_valid(target) and is_prey(get_tree(), target):
		if _horizontal_distance(target) <= settings.chase_range:
			return
	target = null
	var nearest_distance: float = settings.detection_range
	for player: Player in get_tree().get_nodes_in_group(Player.GROUP):
		if not is_prey(get_tree(), player):
			continue
		var distance: float = _horizontal_distance(player)
		if distance <= nearest_distance:
			target = player
			nearest_distance = distance


func _horizontal_distance(node: Node3D) -> float:
	var offset: Vector3 = node.global_position - global_position
	return Vector2(offset.x, offset.z).length()


func _update_look() -> void:
	_material.albedo_color = COLOR_FLASH if _flash_left > 0.0 else COLOR_BODY
	var lunge: float = sin(PI * _lunge_left / LUNGE_DURATION) * LUNGE_DISTANCE
	_body.position = _body_position + Vector3(0.0, 0.0, -lunge)


func _die() -> void:
	dead = true
	target = null
	remove_from_group(GROUP)
	velocity = Vector3.ZERO
	_collision.set_deferred(&"disabled", true)
	died.emit()
	var tween: Tween = create_tween()
	tween.tween_property(_body, ^"scale", Vector3.ONE * 0.01, DEATH_DURATION)
	tween.tween_callback(queue_free)
