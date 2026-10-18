extends GutTest
## Ground hazards (`GroundHazard`): slick ice makes players and aliens slide a little.

const ALIEN_SCENE: PackedScene = preload("res://game/aliens/alien.tscn")
const PLAYER_SCENE: PackedScene = preload("res://game/player/player.tscn")
const GRIP: float = 0.15

var _arena: Node3D
var _player: Player


func before_each() -> void:
	_arena = Node3D.new()
	add_child_autofree(_arena)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100.0, 1.0, 100.0)
	floor_shape.shape = box
	floor_shape.position.y = -0.5
	floor_body.add_child(floor_shape)
	_arena.add_child(floor_body)
	_player = PLAYER_SCENE.instantiate() as Player
	_arena.add_child(_player)


func after_each() -> void:
	for action: StringName in InputMap.get_actions():
		Input.action_release(action)


func test_feet_grip_as_usual_without_hazards() -> void:
	assert_eq(_player.ground_contact.grip(), 1.0)


## On slick ice the player gets up to speed (and stops) much slower: they slide a little.
func test_player_slides_on_slick_ice() -> void:
	var normal: float = await _speed_after_starting()
	_player.velocity = Vector3.ZERO
	_add_ice(_player.global_position)
	await wait_physics_frames(3)
	assert_eq(_player.ground_contact.grip(), GRIP, "stands on the ice")
	var slick: float = await _speed_after_starting()
	assert_gt(normal, 3.0, "speeds up on ordinary ground")
	assert_lt(slick, normal * 0.5, "slides on the ice")
	# Up to speed, then letting go: it takes a while to stop.
	Input.action_press(&"move_right")
	await wait_physics_frames(60)
	Input.action_release(&"move_right")
	await wait_physics_frames(6)
	assert_gt(Vector2(_player.velocity.x, _player.velocity.z).length(), 2.0, "slides on")


func test_aliens_slide_too() -> void:
	var alien := ALIEN_SCENE.instantiate() as Alien
	alien.position = Vector3(20.0, 0.0, 0.0)
	_arena.add_child(alien)
	_add_ice(alien.global_position)
	await wait_physics_frames(3)
	assert_eq(alien.ground_contact.grip(), GRIP)


## Stepping off the ice, or the ice going away with its location, gives the grip back.
func test_grip_comes_back_off_the_ice() -> void:
	var ice: GroundHazard = _add_ice(_player.global_position)
	await wait_physics_frames(3)
	assert_eq(_player.ground_contact.grip(), GRIP)
	_player.global_position += Vector3(30.0, 0.0, 0.0)
	await wait_physics_frames(3)
	assert_eq(_player.ground_contact.grip(), 1.0, "stepped off")
	ice.global_position = _player.global_position
	await wait_physics_frames(3)
	assert_eq(_player.ground_contact.grip(), GRIP, "back on")
	ice.free()
	assert_eq(_player.ground_contact.grip(), 1.0, "ice gone")


## The least grip counts where hazards overlap.
func test_least_grip_counts() -> void:
	var contact := GroundContact.new()
	var ice := GroundHazard.new()
	ice.grip = 0.2
	var slush := GroundHazard.new()
	slush.grip = 0.6
	contact.enter(slush)
	contact.enter(ice)
	assert_eq(contact.grip(), 0.2)
	contact.leave(ice)
	assert_eq(contact.grip(), 0.6)
	ice.free()
	slush.free()


## How fast the player runs after moving right for a few physics frames from standing.
func _speed_after_starting() -> float:
	Input.action_press(&"move_right")
	await wait_physics_frames(6)
	var speed: float = Vector2(_player.velocity.x, _player.velocity.z).length()
	Input.action_release(&"move_right")
	return speed


func _add_ice(at: Vector3) -> GroundHazard:
	var ice := GroundHazard.new()
	ice.grip = GRIP
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 6.0
	cylinder.height = 3.0
	var shape := CollisionShape3D.new()
	shape.shape = cylinder
	ice.add_child(shape)
	_arena.add_child(ice)
	ice.global_position = at
	return ice
