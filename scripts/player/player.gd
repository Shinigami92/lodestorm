class_name Player
extends CharacterBody3D
## Twin-stick player: moves relative to the camera and faces the aim direction. Aims at the
## mouse cursor on the ground, with the right stick, or else in the movement direction, and
## attacks there with the equipped weapon while `attack` is held. An alien under the cursor, or
## close to where the stick points, gets locked on (a ring under it): the player turns to it and
## shots fly straight at it, also up or down a slope. Places miners on the nearest
## free ore node in range with `place_miner`, and carries the ore that miners' hoses move to it,
## shown in canisters on its back. An arrow on the ground points back to the ship. Uses the
## nearest interactable in range (buttons, ...) with `interact`. Health shows on the suit light;
## at zero health the player dies, drops everything carried and lies still until `respawn`.
## The suit model (Body/Model) is animated by `PlayerAnimator`; the weapon, the cargo rack and
## the hose port follow its markers (WeaponGrip in the right hand, the others on the backpack).
## While the mouse is over a 2D control (developer tools), it neither aims nor attacks with it.

## Emitted when the carried amount of an ore type changes.
signal cargo_changed(ore_type: OreType, amount: float)
## Emitted when health changes (damage, healing).
signal health_changed(health: float)
## Emitted when health reaches zero.
signal died

const GROUP: StringName = &"players"

## Ignore cursor positions this close to the player, the direction flips around too easily.
const MIN_MOUSE_AIM_DISTANCE: float = 0.1
## The cursor ray looks for the ground from this high above the player's feet (m), so ceilings and
## the deck above (inside the ship) don't catch it.
const CURSOR_CEILING: float = 3.0
## Stencil value the suit writes where it's visible (occluded_silhouette.gdshader skips those).
const STENCIL_VISIBLE: int = 1

@export var settings: PlayerSettings
## Weapons taken into the mission. Only the first slot is used until switching exists.
@export var loadout: Loadout
@export var miner_scene: PackedScene
## Drawn over the suit: its silhouette behind walls and the rim light.
@export var body_overlay: Material

## Horizontal unit vector the player faces and attacks in.
var aim_direction: Vector3 = Vector3.FORWARD
## The alien locked on, or null.
var aim_target: Alien
## The equipped weapon, or null with an empty loadout.
var weapon: Weapon
## The ore node `place_miner` would use right now, or null.
var miner_target: OreNode
## The interactable `interact` would use right now, or null.
var interact_target: Interactable
## Whether the weapon can be used here; it's holstered (hidden) otherwise, e.g. inside the ship.
var weapon_allowed: bool = true:
	set(value):
		weapon_allowed = value
		if weapon:
			weapon.visible = value
			weapon.trigger_held = false
## Units carried per ore type; no carry limit.
var cargo: Dictionary[OreType, float] = {}
## Current health, from 0 to `settings.max_health`.
var health: float
## Dead players can't move or act until they respawn.
var dead: bool = false

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
## Whether the mouse was used for aiming more recently than the right stick.
var _aim_with_mouse: bool = false

@onready var _weapon_mount: Marker3D = $WeaponMount
@onready var _hose_port: Marker3D = $HosePort
@onready var _cargo_rack: CargoRack = $CargoRack
@onready var _suit_light: SuitLight = $SuitLight
@onready var _model: Node3D = $Body/Model
@onready var _animator: PlayerAnimator = $Animator
@onready var _ship_pointer: Node3D = $ShipPointer
@onready var _target_marker: Node3D = $TargetMarker


func _ready() -> void:
	add_to_group(GROUP)
	_animator.setup(_model)
	_suit_light.band = _model.find_child("SuitLight") as GeometryInstance3D
	(_model.find_child("Suit") as GeometryInstance3D).material_overlay = body_overlay
	_mark_visible(_model)
	_attach(_weapon_mount, "WeaponGrip")
	_attach(_cargo_rack, "CargoRack")
	_attach(_hose_port, "HosePort")
	cargo_changed.connect(_cargo_rack.show_cargo)
	health = settings.max_health
	if loadout and not loadout.weapons.is_empty():
		_equip(loadout.weapons[0])


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_aim_with_mouse = true


func _physics_process(delta: float) -> void:
	if dead:
		aim_target = null
		return
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
	_animator.local_velocity = Vector2(velocity.dot(basis.x), -velocity.dot(basis.z))
	_animator.aiming = weapon != null and weapon_allowed

	if weapon:
		weapon.aim_direction = aim_direction
		weapon.aim_target = aim_target
		weapon.trigger_held = (
			weapon_allowed and Input.is_action_pressed(&"attack") and not _mouse_over_ui()
		)

	_update_miner_target()
	if Input.is_action_just_pressed(&"place_miner"):
		place_miner()

	_update_interact_target()
	if Input.is_action_just_pressed(&"interact"):
		interact()


func _process(_delta: float) -> void:
	var locked: bool = _is_lockable(aim_target)
	_target_marker.visible = locked
	if locked:
		_target_marker.global_position = aim_target.global_position + Vector3.UP * 0.05


func _update_aim(camera: Camera3D, camera_basis: Basis, move: Vector3) -> void:
	var stick: Vector2 = Input.get_vector(&"aim_left", &"aim_right", &"aim_forward", &"aim_back")
	if stick != Vector2.ZERO:
		_aim_with_mouse = false
		aim_with_stick(IsoInput.camera_relative(stick, camera_basis))
	elif _aim_with_mouse and camera:
		if not _mouse_over_ui():
			aim_at_screen_position(camera, get_viewport().get_mouse_position())
	else:
		aim_target = null
		if move != Vector3.ZERO:
			aim_direction = move.normalized()
	if not _is_lockable(aim_target):
		aim_target = null
	elif aim_target:
		_aim_towards(aim_target.global_position)


## Aims at what's under the given screen position: an alien close to it (locked on), or else
## the point on the ground.
func aim_at_screen_position(camera: Camera3D, screen_position: Vector2) -> void:
	aim_target = _alien_near_screen_position(camera, screen_position)
	if aim_target:
		_aim_towards(aim_target.global_position)
		return
	var origin: Vector3 = camera.project_ray_origin(screen_position)
	var normal: Vector3 = camera.project_ray_normal(screen_position)
	var hit: Variant = Plane(Vector3.UP, global_position.y).intersects_ray(origin, normal)
	# The ground under the cursor, also on a slope or hill (below the ceiling height).
	var ceiling: Variant = Plane(Vector3.UP, global_position.y + CURSOR_CEILING).intersects_ray(
		origin, normal
	)
	if ceiling != null:
		var from: Vector3 = ceiling
		var query := PhysicsRayQueryParameters3D.create(from, origin + normal * 1000.0)
		query.exclude = [get_rid()]
		var ground: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if not ground.is_empty():
			hit = ground[&"position"]
	if hit != null:
		_aim_towards(hit as Vector3)


## Aims along `direction` (horizontal) and locks on the nearest alien close to it.
func aim_with_stick(direction: Vector3) -> void:
	aim_direction = direction.normalized()
	var best: Alien
	var best_distance: float = settings.stick_lock_range
	var max_angle: float = deg_to_rad(settings.stick_lock_angle)
	for alien: Alien in _aliens():
		var offset: Vector3 = alien.global_position - global_position
		offset.y = 0.0
		var distance: float = offset.length()
		if distance < best_distance and offset.angle_to(aim_direction) <= max_angle:
			best = alien
			best_distance = distance
	aim_target = best


func _aim_towards(point: Vector3) -> void:
	var to_point: Vector3 = point - global_position
	to_point.y = 0.0
	if to_point.length() > MIN_MOUSE_AIM_DISTANCE:
		aim_direction = to_point.normalized()


## The alien closest to `screen_position` on screen, within the lock radius (the one already
## locked on keeps it up to the larger release radius), or null.
func _alien_near_screen_position(camera: Camera3D, screen_position: Vector2) -> Alien:
	var screen_height: float = get_viewport().get_visible_rect().size.y
	var best: Alien
	var best_distance: float = INF
	for alien: Alien in _aliens():
		var point: Vector3 = alien.get_aim_point()
		if camera.is_position_behind(point):
			continue
		var radius: float = (
			settings.target_release_radius if alien == aim_target else settings.target_lock_radius
		)
		var distance: float = camera.unproject_position(point).distance_to(screen_position)
		if distance <= radius * screen_height and distance < best_distance:
			best = alien
			best_distance = distance
	return best


func _aliens() -> Array[Alien]:
	var aliens: Array[Alien] = []
	for node: Node in get_tree().get_nodes_in_group(Alien.GROUP):
		var alien := node as Alien
		if _is_lockable(alien):
			aliens.append(alien)
	return aliens


func _is_lockable(alien: Alien) -> bool:
	return is_instance_valid(alien) and not alien.dead and alien.is_inside_tree()


## Places a miner on `miner_target` and returns it, or null without a target.
func place_miner() -> Miner:
	_update_miner_target()
	if not miner_target:
		return null
	var miner: Miner = miner_target.place_miner(miner_scene)
	_update_miner_target()
	return miner


## Uses `interact_target` and returns it, or null without a target.
func interact() -> Interactable:
	_update_interact_target()
	if interact_target:
		interact_target.use(self)
	return interact_target


## Adds `amount` units of `ore_type` to the cargo.
func add_cargo(ore_type: OreType, amount: float) -> void:
	if amount <= 0.0:
		return
	var carried: float = cargo.get(ore_type, 0.0)
	carried += amount
	cargo[ore_type] = carried
	cargo_changed.emit(ore_type, carried)


## Removes all cargo and returns it.
func take_cargo() -> Dictionary[OreType, float]:
	var taken: Dictionary[OreType, float] = cargo
	cargo = {}
	for ore_type: OreType in taken:
		cargo_changed.emit(ore_type, 0.0)
	return taken


## Loses `amount` health; dies at zero.
func take_damage(amount: float) -> void:
	if dead or amount <= 0.0:
		return
	_set_health(health - amount)
	if health == 0.0:
		_die()
	else:
		_suit_light.flash()


## Restores full health.
func heal() -> void:
	if not dead:
		_set_health(settings.max_health)


## Brings a dead player back at `at` with full health.
func respawn(at: Vector3) -> void:
	dead = false
	_animator.dead = false
	weapon_allowed = weapon_allowed
	_ship_pointer.process_mode = Node.PROCESS_MODE_INHERIT
	global_position = at
	velocity = Vector3.ZERO
	reset_physics_interpolation()
	_set_health(settings.max_health)


## Where hoses attach, as rendered this frame (interpolated between physics steps).
func get_hose_port_position() -> Vector3:
	return _hose_port.get_global_transform_interpolated().origin


## The living player closest to `from` within `max_distance` (horizontally), or null.
static func nearest(tree: SceneTree, from: Vector3, max_distance: float) -> Player:
	var nearest_player: Player = null
	var nearest_distance: float = max_distance
	for player: Player in tree.get_nodes_in_group(GROUP):
		if player.dead:
			continue
		var offset: Vector3 = player.global_position - from
		var distance: float = Vector2(offset.x, offset.z).length()
		if distance <= nearest_distance:
			nearest_player = player
			nearest_distance = distance
	return nearest_player


func _mouse_over_ui() -> bool:
	return _aim_with_mouse and get_viewport().gui_get_hovered_control() != null


func _set_health(value: float) -> void:
	health = clampf(value, 0.0, settings.max_health)
	_suit_light.show_health(health / settings.max_health)
	health_changed.emit(health)


func _die() -> void:
	dead = true
	velocity = Vector3.ZERO
	if weapon:
		weapon.trigger_held = false
		weapon.visible = false
	if is_instance_valid(miner_target):
		miner_target.highlighted = false
	if is_instance_valid(interact_target):
		interact_target.highlighted = false
	miner_target = null
	interact_target = null
	take_cargo()
	# Falls and lies still; the collision shape stays, so the ship still knows where the body is.
	_animator.local_velocity = Vector2.ZERO
	_animator.dead = true
	_ship_pointer.visible = false
	_ship_pointer.process_mode = Node.PROCESS_MODE_DISABLED
	died.emit()


## Lets the meshes under `root` (the suit, the weapon) mark where they're visible in the stencil
## buffer, so the silhouette only shows where something else hides the player. Marks their
## materials in place: the imported ones are only used by players (and weapons they hold).
func _mark_visible(root: Node) -> void:
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh.material_override:  # e.g. the suit light's own material
			_write_stencil(mesh.material_override as BaseMaterial3D)
			continue
		for surface: int in mesh.mesh.get_surface_count():
			_write_stencil(mesh.mesh.surface_get_material(surface) as BaseMaterial3D)


static func _write_stencil(material: BaseMaterial3D) -> void:
	if not material:
		return
	material.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
	material.stencil_flags = BaseMaterial3D.STENCIL_FLAG_WRITE
	material.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_ALWAYS
	material.stencil_reference = STENCIL_VISIBLE


## Makes `node` follow the model's marker `marker_name` (and so its animated bone).
func _attach(node: Node3D, marker_name: String) -> void:
	var follow := RemoteTransform3D.new()
	(_model.find_child(marker_name) as Node3D).add_child(follow)
	follow.remote_path = follow.get_path_to(node)


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


func _update_interact_target() -> void:
	var target: Interactable = Interactable.nearest(get_tree(), global_position)
	if target == interact_target:
		return
	if is_instance_valid(interact_target):
		interact_target.highlighted = false
	interact_target = target
	if interact_target:
		interact_target.highlighted = true


func _equip(weapon_scene: PackedScene) -> void:
	if weapon:
		weapon.queue_free()
	weapon = weapon_scene.instantiate() as Weapon
	weapon.holder = self
	weapon.visible = weapon_allowed
	_mark_visible(weapon)
	_weapon_mount.add_child(weapon)
