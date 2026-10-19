class_name PlayerAim
extends Node
## Where the `holder` aims: at the mouse cursor on the ground, with the right stick, or else in the
## movement direction. An alien under the cursor, or close to where the stick points, gets locked
## on (shown by `TargetMarker`): the holder turns to it and shots fly straight at it, also up or
## down a slope. Without an alien there, a `Destructible` (an alien nest) gets locked on the same
## way, so an alien next to a nest is locked first. Other aim sources (VR controllers, remote
## players) set `direction` and `target` through `towards`, `at_screen_position` or `with_stick`
## the same way.

## Ignore cursor positions this close to the holder, the direction flips around too easily.
const MIN_MOUSE_AIM_DISTANCE: float = 0.1
## The cursor ray looks for the ground from this high above the holder's feet (m), so ceilings and
## the deck above (inside the ship) don't catch it.
const CURSOR_CEILING: float = 3.0

## The player aiming.
var holder: Player
## Horizontal unit vector the holder faces and attacks in.
var direction: Vector3 = Vector3.FORWARD
## The alien or the `Destructible` locked on, or null.
var target: Node3D

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


## Aims at what's under the given screen position: an alien close to it, or else a destructible
## (locked on), or else the point on the ground.
func at_screen_position(camera: Camera3D, screen_position: Vector2) -> void:
	target = _near_screen_position(camera, screen_position, _aliens())
	if not target:
		target = _near_screen_position(camera, screen_position, _destructibles())
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


## Aims along `along` (horizontal) and locks on the nearest alien close to it, or else the
## nearest destructible.
func with_stick(along: Vector3) -> void:
	direction = along.normalized()
	target = _near_stick(_aliens())
	if not target:
		target = _near_stick(_destructibles())


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


## Whether `node` (an alien or a destructible) can be locked on: it exists, can be hit and isn't
## hidden (a stalker no player is close to).
static func is_lockable(node: Node3D) -> bool:
	if not is_instance_valid(node):
		return false
	if node is Alien:
		var alien := node as Alien
		return alien.is_hittable() and not (alien.cloaking and alien.cloaking.is_hidden())
	return node is Destructible and (node as Destructible).is_hittable()


## Where shots at `node` (an alien or a destructible) aim.
static func aim_point(node: Node3D) -> Vector3:
	if node is Alien:
		return (node as Alien).get_aim_point()
	if node is Destructible:
		return (node as Destructible).get_aim_point()
	return node.global_position


## Of `candidates`, the one closest to `screen_position` on screen, within the lock radius (the
## one already locked on keeps it up to the larger release radius; a destructible's body on screen
## adds to it), or null.
func _near_screen_position(
	camera: Camera3D, screen_position: Vector2, candidates: Array[Node3D]
) -> Node3D:
	var screen_height: float = holder.get_viewport().get_visible_rect().size.y
	var settings: PlayerSettings = holder.settings
	var best: Node3D
	var best_distance: float = INF
	for candidate: Node3D in candidates:
		var point: Vector3 = aim_point(candidate)
		if camera.is_position_behind(point):
			continue
		var radius: float = (
			settings.target_release_radius if candidate == target else settings.target_lock_radius
		)
		radius *= screen_height
		var on_screen: Vector2 = camera.unproject_position(point)
		if candidate is Destructible:
			var edge: Vector3 = point + camera.global_basis.x * (candidate as Destructible).radius()
			radius += camera.unproject_position(edge).distance_to(on_screen)
		var distance: float = on_screen.distance_to(screen_position)
		if distance <= radius and distance < best_distance:
			best = candidate
			best_distance = distance
	return best


## Of `candidates`, the nearest one within the stick's lock range and angle around `direction`,
## or null.
func _near_stick(candidates: Array[Node3D]) -> Node3D:
	var best: Node3D
	var best_distance: float = holder.settings.stick_lock_range
	var max_angle: float = deg_to_rad(holder.settings.stick_lock_angle)
	for candidate: Node3D in candidates:
		var offset: Vector3 = candidate.global_position - holder.global_position
		offset.y = 0.0
		var distance: float = offset.length()
		if distance < best_distance and offset.angle_to(direction) <= max_angle:
			best = candidate
			best_distance = distance
	return best


func _aliens() -> Array[Node3D]:
	return _lockable(Alien.GROUP)


func _destructibles() -> Array[Node3D]:
	return _lockable(Destructible.GROUP)


func _lockable(group: StringName) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for node: Node in holder.get_tree().get_nodes_in_group(group):
		if is_lockable(node as Node3D):
			found.append(node as Node3D)
	return found
