class_name PlayerAim
extends Node
## Where the `holder` aims: at the mouse cursor on the ground, with the right stick, or else in the
## movement direction. An alien under the cursor, or close to where the stick points, gets locked
## on (shown by `TargetMarker`): the holder turns to it and shots fly straight at it, also up or
## down a slope. Other aim sources (VR controllers, remote players) set `direction` and `target`
## through `towards`, `at_screen_position` or `with_stick` the same way.

## Ignore cursor positions this close to the holder, the direction flips around too easily.
const MIN_MOUSE_AIM_DISTANCE: float = 0.1
## The cursor ray looks for the ground from this high above the holder's feet (m), so ceilings and
## the deck above (inside the ship) don't catch it.
const CURSOR_CEILING: float = 3.0

## The player aiming.
var holder: Player
## Horizontal unit vector the holder faces and attacks in.
var direction: Vector3 = Vector3.FORWARD
## The alien locked on, or null.
var target: Alien

## Whether the mouse was used for aiming more recently than the right stick.
var _with_mouse: bool = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_with_mouse = true


## Aims with the player's input this physics step: the right stick, else the mouse, else the
## movement direction (`move`, camera-relative).
func update(camera: Camera3D, camera_basis: Basis, move: Vector3) -> void:
	var stick: Vector2 = Input.get_vector(&"aim_left", &"aim_right", &"aim_forward", &"aim_back")
	if stick != Vector2.ZERO:
		_with_mouse = false
		with_stick(IsoInput.camera_relative(stick, camera_basis))
	elif _with_mouse and camera:
		if not is_mouse_over_ui():
			at_screen_position(camera, holder.get_viewport().get_mouse_position())
	else:
		target = null
		if move != Vector3.ZERO:
			direction = move.normalized()
	if not is_lockable(target):
		target = null
	elif target:
		towards(target.global_position)


## Aims at what's under the given screen position: an alien close to it (locked on), or else
## the point on the ground.
func at_screen_position(camera: Camera3D, screen_position: Vector2) -> void:
	target = _alien_near_screen_position(camera, screen_position)
	if target:
		towards(target.global_position)
		return
	var from: Vector3 = holder.global_position
	var origin: Vector3 = camera.project_ray_origin(screen_position)
	var normal: Vector3 = camera.project_ray_normal(screen_position)
	var hit: Variant = Plane(Vector3.UP, from.y).intersects_ray(origin, normal)
	# The ground under the cursor, also on a slope or hill (below the ceiling height).
	var ceiling: Variant = Plane(Vector3.UP, from.y + CURSOR_CEILING).intersects_ray(origin, normal)
	if ceiling != null:
		var start: Vector3 = ceiling
		var query := PhysicsRayQueryParameters3D.create(
			start, origin + normal * 1000.0, PhysicsLayers.SHOTS
		)
		query.exclude = [holder.get_rid()]
		var ground: Dictionary = holder.get_world_3d().direct_space_state.intersect_ray(query)
		if not ground.is_empty():
			hit = ground[&"position"]
	if hit != null:
		towards(hit as Vector3)


## Aims along `along` (horizontal) and locks on the nearest alien close to it.
func with_stick(along: Vector3) -> void:
	direction = along.normalized()
	var best: Alien
	var best_distance: float = holder.settings.stick_lock_range
	var max_angle: float = deg_to_rad(holder.settings.stick_lock_angle)
	for alien: Alien in _aliens():
		var offset: Vector3 = alien.global_position - holder.global_position
		offset.y = 0.0
		var distance: float = offset.length()
		if distance < best_distance and offset.angle_to(direction) <= max_angle:
			best = alien
			best_distance = distance
	target = best


## Turns the aim towards `point` (horizontally), unless it's right at the holder.
func towards(point: Vector3) -> void:
	var to_point: Vector3 = point - holder.global_position
	to_point.y = 0.0
	if to_point.length() > MIN_MOUSE_AIM_DISTANCE:
		direction = to_point.normalized()


## Whether the mouse aims and is over a 2D control (developer tools); then it neither aims nor
## attacks.
func is_mouse_over_ui() -> bool:
	return _with_mouse and holder.get_viewport().gui_get_hovered_control() != null


## Whether `alien` can be locked on: it exists, lives and is in the world.
static func is_lockable(alien: Alien) -> bool:
	return is_instance_valid(alien) and not alien.dead and alien.is_inside_tree()


## The alien closest to `screen_position` on screen, within the lock radius (the one already
## locked on keeps it up to the larger release radius), or null.
func _alien_near_screen_position(camera: Camera3D, screen_position: Vector2) -> Alien:
	var screen_height: float = holder.get_viewport().get_visible_rect().size.y
	var settings: PlayerSettings = holder.settings
	var best: Alien
	var best_distance: float = INF
	for alien: Alien in _aliens():
		var point: Vector3 = alien.get_aim_point()
		if camera.is_position_behind(point):
			continue
		var radius: float = (
			settings.target_release_radius if alien == target else settings.target_lock_radius
		)
		var distance: float = camera.unproject_position(point).distance_to(screen_position)
		if distance <= radius * screen_height and distance < best_distance:
			best = alien
			best_distance = distance
	return best


func _aliens() -> Array[Alien]:
	var aliens: Array[Alien] = []
	for node: Node in holder.get_tree().get_nodes_in_group(Alien.GROUP):
		var alien := node as Alien
		if is_lockable(alien):
			aliens.append(alien)
	return aliens
