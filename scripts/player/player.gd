class_name Player
extends CharacterBody3D
## Twin-stick player: moves relative to the camera and faces the aim direction. Aims at the
## mouse cursor on the ground, with the right stick, or else in the movement direction, and
## attacks there with the equipped weapon while `attack` is held. Places miners on the nearest
## free ore node in range with `place_miner`, and carries the ore that miners' hoses move to it.

## Emitted when the carried amount of an ore type changes.
signal cargo_changed(ore_type: OreType, amount: float)

const GROUP: StringName = &"players"

## Ignore cursor positions this close to the player, the direction flips around too easily.
const MIN_MOUSE_AIM_DISTANCE: float = 0.1

@export var settings: PlayerSettings
## Weapons taken into the mission. Only the first slot is used until switching exists.
@export var loadout: Loadout
@export var miner_scene: PackedScene

## Horizontal unit vector the player faces and attacks in.
var aim_direction: Vector3 = Vector3.FORWARD
## The equipped weapon, or null with an empty loadout.
var weapon: Weapon
## The ore node `place_miner` would use right now, or null.
var miner_target: OreNode
## Units carried per ore type; no carry limit.
var cargo: Dictionary[OreType, float] = {}

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
## Whether the mouse was used for aiming more recently than the right stick.
var _aim_with_mouse: bool = false

@onready var _weapon_mount: Marker3D = $WeaponMount
@onready var _hose_port: Marker3D = $HosePort


func _ready() -> void:
	add_to_group(GROUP)
	if loadout and not loadout.weapons.is_empty():
		_equip(loadout.weapons[0])


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_aim_with_mouse = true


func _physics_process(delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	var camera_basis: Basis = camera.global_basis if camera else Basis.IDENTITY

	var move_input: Vector2 = Input.get_vector(
		&"move_left", &"move_right", &"move_forward", &"move_back"
	)
	var move: Vector3 = IsoInput.camera_relative(move_input, camera_basis)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(
		move * settings.move_speed, settings.acceleration * delta
	)
	velocity = Vector3(horizontal.x, velocity.y, horizontal.z)
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= _gravity * delta
	move_and_slide()

	_update_aim(camera, camera_basis, move)
	var target_yaw: float = atan2(-aim_direction.x, -aim_direction.z)
	var yaw: float = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-settings.turn_speed * delta))
	# A fresh basis instead of setting rotation.y keeps the scale from drifting over time.
	basis = Basis(Vector3.UP, yaw)

	if weapon:
		weapon.aim_direction = aim_direction
		weapon.trigger_held = Input.is_action_pressed(&"attack")

	_update_miner_target()
	if Input.is_action_just_pressed(&"place_miner"):
		place_miner()


func _update_aim(camera: Camera3D, camera_basis: Basis, move: Vector3) -> void:
	var stick: Vector2 = Input.get_vector(&"aim_left", &"aim_right", &"aim_forward", &"aim_back")
	if stick != Vector2.ZERO:
		_aim_with_mouse = false
		aim_direction = IsoInput.camera_relative(stick, camera_basis).normalized()
	elif _aim_with_mouse and camera:
		aim_at_screen_position(camera, get_viewport().get_mouse_position())
	elif move != Vector3.ZERO:
		aim_direction = move.normalized()


## Aims at the point on the ground (at the player's height) under the given screen position.
func aim_at_screen_position(camera: Camera3D, screen_position: Vector2) -> void:
	var ground := Plane(Vector3.UP, global_position.y)
	var hit: Variant = ground.intersects_ray(
		camera.project_ray_origin(screen_position), camera.project_ray_normal(screen_position)
	)
	if hit == null:
		return
	var to_cursor: Vector3 = (hit as Vector3) - global_position
	to_cursor.y = 0.0
	if to_cursor.length() > MIN_MOUSE_AIM_DISTANCE:
		aim_direction = to_cursor.normalized()


## Places a miner on `miner_target` and returns it, or null without a target.
func place_miner() -> Miner:
	_update_miner_target()
	if not miner_target:
		return null
	var miner: Miner = miner_target.place_miner(miner_scene)
	_update_miner_target()
	return miner


## Adds `amount` units of `ore_type` to the cargo.
func add_cargo(ore_type: OreType, amount: float) -> void:
	if amount <= 0.0:
		return
	var carried: float = cargo.get(ore_type, 0.0)
	carried += amount
	cargo[ore_type] = carried
	cargo_changed.emit(ore_type, carried)


## Where hoses attach, as rendered this frame (interpolated between physics steps).
func get_hose_port_position() -> Vector3:
	return _hose_port.get_global_transform_interpolated().origin


## The player closest to `from` within `max_distance` (horizontally), or null.
static func nearest(tree: SceneTree, from: Vector3, max_distance: float) -> Player:
	var nearest_player: Player = null
	var nearest_distance: float = max_distance
	for player: Player in tree.get_nodes_in_group(GROUP):
		var offset: Vector3 = player.global_position - from
		var distance: float = Vector2(offset.x, offset.z).length()
		if distance <= nearest_distance:
			nearest_player = player
			nearest_distance = distance
	return nearest_player


func _update_miner_target() -> void:
	var target: OreNode = OreNode.nearest_free(
		get_tree(), global_position, settings.miner_place_range
	)
	if target == miner_target:
		return
	if is_instance_valid(miner_target):
		miner_target.highlighted = false
	miner_target = target
	if miner_target:
		miner_target.highlighted = true


func _equip(weapon_scene: PackedScene) -> void:
	if weapon:
		weapon.queue_free()
	weapon = weapon_scene.instantiate() as Weapon
	weapon.holder = self
	_weapon_mount.add_child(weapon)
