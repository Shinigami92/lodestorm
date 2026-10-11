class_name Alien
extends CharacterBody3D
## Greybox alien: waits until a living player outside the ship comes within
## `settings.detection_range`, then chases the nearest one and attacks it when in reach (the body
## lunges forward). A player gets away by running farther than `settings.chase_range` or by
## going aboard; aliens don't hunt players inside the ship. Where there is a navigation mesh it
## walks around obstacles along it and steers around other aliens; elsewhere it goes straight.
## Hunters (sent out by nests) go for the nearest player outside however far away. It grows out of
## the ground when it appears, loses health when hit (flashes white) and dies at zero: it stops,
## shrinks and disappears.

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
## Seconds the body takes to grow out of the ground when the alien appears.
const HATCH_DURATION: float = 0.4
## Seconds the body takes to shrink away after dying.
## The path is only looked up again once the target moved this far (m).
const REPATH_DISTANCE: float = 1.0
const DEATH_DURATION: float = 0.3

@export var settings: AlienSettings
## Hunters go for the nearest prey however far away and never let it get away by distance.
@export var hunter: bool = false

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
var _hatch_tween: Tween

@onready var _body: MeshInstance3D = $Body
@onready var _body_position: Vector3 = _body.position
@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _agent: NavigationAgent3D = $NavigationAgent3D


func _ready() -> void:
	add_to_group(GROUP)
	health = settings.max_health
	_body.material_override = _material
	_update_look()
	_body.scale = Vector3.ONE * 0.01
	_hatch_tween = create_tween()
	_hatch_tween.tween_property(_body, ^"scale", Vector3.ONE, HATCH_DURATION)
	_agent.velocity_computed.connect(_on_velocity_computed)


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
		if distance > settings.attack_range:
			move = _direction_to(target.global_position)
		elif _cooldown == 0.0:
			attack(target)
		# Face where it walks, or the target when it stands.
		var facing: Vector3 = move if move != Vector3.ZERO else offset
		if facing != Vector3.ZERO:
			var target_yaw: float = atan2(-facing.x, -facing.z)
			var yaw: float = lerp_angle(
				rotation.y, target_yaw, 1.0 - exp(-settings.turn_speed * delta)
			)
			basis = Basis(Vector3.UP, yaw)

	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(
		move * settings.move_speed, settings.acceleration * delta
	)
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= _gravity * delta
	# Avoidance only runs with a navigation mesh; it answers with `velocity_computed`.
	var navigation: bool = _has_navigation()
	if _agent.avoidance_enabled != navigation:
		_agent.avoidance_enabled = navigation
	if navigation:
		_agent.max_speed = settings.move_speed
		_agent.velocity = horizontal
	else:
		_on_velocity_computed(horizontal)


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
## prey in `settings.detection_range`. Hunters keep their prey and pick it from any distance.
func _update_target() -> void:
	if target and is_instance_valid(target) and is_prey(get_tree(), target):
		if hunter or _horizontal_distance(target) <= settings.chase_range:
			return
	target = null
	var nearest_distance: float = INF if hunter else settings.detection_range
	for player: Player in get_tree().get_nodes_in_group(Player.GROUP):
		if not is_prey(get_tree(), player):
			continue
		var distance: float = _horizontal_distance(player)
		if distance <= nearest_distance:
			target = player
			nearest_distance = distance


## Horizontal direction towards `point`: along the navigation mesh if there is one and it has a
## path, straight otherwise.
func _direction_to(point: Vector3) -> Vector3:
	var next: Vector3 = point
	if _has_navigation():
		if _agent.target_position.distance_to(point) > REPATH_DISTANCE:
			_agent.target_position = point
		next = _agent.get_next_path_position()
	var offset: Vector3 = next - global_position
	offset.y = 0.0
	if offset.length() < 0.01:
		offset = point - global_position
		offset.y = 0.0
	return offset.normalized()


func _has_navigation() -> bool:
	return not NavigationServer3D.map_get_regions(get_world_3d().navigation_map).is_empty()


func _horizontal_distance(node: Node3D) -> float:
	var offset: Vector3 = node.global_position - global_position
	return Vector2(offset.x, offset.z).length()


func _update_look() -> void:
	_material.albedo_color = COLOR_FLASH if _flash_left > 0.0 else COLOR_BODY
	var lunge: float = sin(PI * _lunge_left / LUNGE_DURATION) * LUNGE_DISTANCE
	_body.position = _body_position + Vector3(0.0, 0.0, -lunge)


func _on_velocity_computed(safe_velocity: Vector3) -> void:
	if dead:
		return
	velocity = Vector3(safe_velocity.x, velocity.y, safe_velocity.z)
	move_and_slide()


func _die() -> void:
	dead = true
	target = null
	remove_from_group(GROUP)
	velocity = Vector3.ZERO
	_agent.avoidance_enabled = false
	_collision.set_deferred(&"disabled", true)
	died.emit()
	_hatch_tween.kill()
	var tween: Tween = create_tween()
	tween.tween_property(_body, ^"scale", Vector3.ONE * 0.01, DEATH_DURATION)
	tween.tween_callback(queue_free)
