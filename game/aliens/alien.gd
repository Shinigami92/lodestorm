class_name Alien
extends CharacterBody3D
## Alien (the swarmer model, assets/aliens/swarmer/swarmer.glb): waits until a living player
## outside the ship comes within `settings.detection_range`, then chases the nearest one and
## attacks it when in reach (it snaps forward, jaw open, blades striking). A player gets away by
## running farther than `settings.chase_range` or by going aboard; aliens don't hunt players
## inside the ship. Where there is a navigation mesh it
## walks around obstacles along it and steers around other aliens; elsewhere it goes straight.
## Nests send out two more roles: hunters go for the nearest player outside however far away, and
## raiders go for the nearest miner that still works, however far away, and ignore players until
## no working miner is left; then they hunt players too. Raiders have a darker body. It grows
## out of the ground when it appears, loses health when hit (flashes white) and dies at zero: it
## stops, collapses, sinks into the ground and disappears. Its legs step on their own
## (`AlienLegs`), the body plays the model's clips (`AlienAnimator`).

## Emitted when health reaches zero.
signal died

## Guards wait until a player comes close, hunters go for players and raiders for miners.
enum Role { GUARD, HUNTER, RAIDER }

const GROUP: StringName = &"aliens"

## Raiders are a different strain: a darker body (orange would look like the player). The
## alpha is how much the shade covers the model.
const COLOR_RAIDER := Color(0.0, 0.0, 0.0, 0.5)
## The rim light is weaker than on players and machines: the alien's many thin, curved parts
## would glow all over.
const RIM_STRENGTH: float = 0.45
## A hit flash covers the model in white.
const COLOR_FLASH := Color(1.0, 1.0, 1.0, 0.85)
## Seconds a hit flash lasts.
const FLASH_DURATION: float = 0.1
## Seconds the body takes to grow out of the ground when the alien appears.
const HATCH_DURATION: float = 0.4
## Faster than this (m/s), it faces where it goes; slower, where it wants to go.
const FACE_VELOCITY_MIN: float = 1.0
## The path is only looked up again once the target moved this far (m).
const REPATH_DISTANCE: float = 1.0
## Seconds the body lies on the ground after dying (the "Die" clip takes 1 s).
const COLLAPSE_DURATION: float = 1.2
## Seconds it then takes to sink into the ground.
const SINK_DURATION: float = 0.5
## How far it sinks, in m.
const SINK_DEPTH: float = 0.6
## Seconds from death until the alien is gone.
const DEATH_DURATION: float = COLLAPSE_DURATION + SINK_DURATION

## Shared by all aliens (see `RIM_STRENGTH`).
static var _rim: ShaderMaterial

@export var settings: AlienSettings
## Hunters and raiders go for their target however far away and never let it get away by distance.
@export var role := Role.GUARD

## How much stronger than its settings it is (more health, more damage): bodies farther in have
## stronger aliens (see `MissionSettings.alien_health_at`). Set before it enters the tree.
var health_factor: float = 1.0
var damage_factor: float = 1.0
## Current health, from 0 to `max_health()`.
var health: float
## Dead aliens don't move or attack; they disappear after `DEATH_DURATION`.
var dead: bool = false
## The player or miner being chased, or null.
var target: Node3D
## The ground hazards it stands in (slick ice).
var ground_contact := GroundContact.new()

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
## Seconds until the next attack is possible.
var _cooldown: float = 0.0
var _flash_left: float = 0.0
## Laid over the model: the raiders' shade, the hit flash, and the rim light as its next pass.
var _overlay := StandardMaterial3D.new()
var _hatch_tween: Tween
var _legs := AlienLegs.new()

@onready var _body: Node3D = $Body
@onready var _model: Node3D = $Body/Model
@onready var _animator: AlienAnimator = $Animator
@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _agent: NavigationAgent3D = $NavigationAgent3D


func _ready() -> void:
	add_to_group(GROUP)
	health = max_health()
	_animator.run_speed = settings.move_speed
	_animator.setup(_model)
	(_model.find_child("Skeleton3D", true, false) as Skeleton3D).add_child(_legs)
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if not _rim:
		_rim = preload("res://assets/shaders/rim_light.tres").duplicate() as ShaderMaterial
		_rim.set_shader_parameter(&"strength", RIM_STRENGTH)
	_overlay.next_pass = _rim
	# Seen behind cliffs too, as a red silhouette.
	var creature := _model.find_child("Creature", true, false) as GeometryInstance3D
	creature.material_overlay = OccludedSilhouette.overlay(OccludedSilhouette.ALIEN_COLOR, _overlay)
	OccludedSilhouette.mark_visible(_model)
	_update_look()
	_body.scale = Vector3.ONE * 0.01
	_hatch_tween = create_tween()
	_hatch_tween.tween_property(_body, ^"scale", Vector3.ONE, HATCH_DURATION)
	# The feet spread out while it grows: put them where they belong at full size.
	_hatch_tween.tween_callback(_legs.plant_all)
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
		var reach: float = settings.attack_range
		if target is Miner:
			reach += (target as Miner).body_radius
		if distance > reach:
			move = _direction_to(target.global_position)
		elif _cooldown == 0.0:
			attack(target)
		# Face where it actually goes (avoidance and acceleration bend the path), or the target
		# when it stands.
		var facing: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
		if facing.length() < FACE_VELOCITY_MIN:
			facing = move if move != Vector3.ZERO else offset
		if facing != Vector3.ZERO:
			var target_yaw: float = atan2(-facing.x, -facing.z)
			# In world space: aliens live under turned nodes (the location, nests).
			var yaw: float = lerp_angle(
				global_rotation.y, target_yaw, 1.0 - exp(-settings.turn_speed * delta)
			)
			global_basis = Basis(Vector3.UP, yaw)

	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(
		move * settings.move_speed * ground_contact.speed(),
		settings.acceleration * ground_contact.grip() * delta
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
	_animator.speed = 0.0 if dead else Vector2(velocity.x, velocity.z).length()
	_update_look()


## Hits `victim` (a player or a miner) once and waits `1 / settings.attack_rate` until the next
## attack.
func attack(victim: Node3D) -> void:
	if victim is Player:
		(victim as Player).take_damage(attack_damage(), global_position)
	elif victim is Miner:
		(victim as Miner).take_damage(attack_damage())
	_cooldown = 1.0 / settings.attack_rate
	_animator.attack()


## Health of the unhurt alien.
func max_health() -> float:
	return settings.max_health * health_factor


## Damage per attack.
func attack_damage() -> float:
	return settings.attack_damage * damage_factor


## Where shots aim at: the middle of its body.
func get_aim_point() -> Vector3:
	return _collision.global_position


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
## Raiders keep their miner until it breaks and pick the nearest working one from any distance;
## without one they act like hunters.
func _update_target() -> void:
	if role == Role.RAIDER and _update_miner_target():
		return
	if target is Player and is_instance_valid(target) and is_prey(get_tree(), target as Player):
		if role != Role.GUARD or _horizontal_distance(target) <= settings.chase_range:
			return
	target = null
	var nearest_distance: float = INF if role != Role.GUARD else settings.detection_range
	for player: Player in get_tree().get_nodes_in_group(Player.GROUP):
		if not is_prey(get_tree(), player):
			continue
		var distance: float = _horizontal_distance(player)
		if distance <= nearest_distance:
			target = player
			nearest_distance = distance


## Keeps the target miner while it works, otherwise picks the nearest working one. Returns
## whether there is one.
func _update_miner_target() -> bool:
	if target is Miner and is_instance_valid(target) and not (target as Miner).broken:
		return true
	target = null
	var nearest_distance: float = INF
	for miner: Miner in get_tree().get_nodes_in_group(Miner.GROUP):
		var distance: float = _horizontal_distance(miner)
		if not miner.broken and distance <= nearest_distance:
			target = miner
			nearest_distance = distance
	return target != null


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
	var shade := Color(0.0, 0.0, 0.0, 0.0)
	if _flash_left > 0.0:
		shade = COLOR_FLASH
	elif role == Role.RAIDER:
		shade = COLOR_RAIDER
	_overlay.albedo_color = shade


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
	_body.scale = Vector3.ONE
	_animator.dead = true
	_legs.active = false
	var tween: Tween = create_tween()
	tween.tween_interval(COLLAPSE_DURATION)
	tween.tween_property(_body, ^"position:y", -SINK_DEPTH, SINK_DURATION)
	tween.tween_callback(queue_free)
