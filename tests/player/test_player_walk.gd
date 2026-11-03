extends GutTest
## Walking (`walk` held) instead of running: at the crew's pace, or at the pace of whoever walks
## nearby (`NpcBody.pace_near`), so a player can walk along with them; the legs walk ("Walk") and
## the steps come closer together.

const PLAYER_SCENE: PackedScene = preload("res://game/player/player.tscn")
const BODY: PackedScene = preload("res://game/npcs/npc_body.tscn")
const COLONIST: NpcProfile = preload("res://game/npcs/ostra/colonists/hauler_pilot.tres")

var _arena: Node3D
var _player: Player
var _animator: PlayerAnimator


func before_each() -> void:
	_arena = Node3D.new()
	add_child_autofree(_arena)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	_arena.add_child(floor_body)
	_player = PLAYER_SCENE.instantiate() as Player
	_arena.add_child(_player)
	_animator = _player.get_node("Animator") as PlayerAnimator
	await wait_physics_frames(1)


func after_each() -> void:
	Input.action_release(&"walk")
	Input.action_release(&"move_right")


func test_walks_at_the_crews_pace_with_nobody_near() -> void:
	Input.action_press(&"walk")
	assert_almost_eq(await _speed_after_moving(), _player.settings.walk_speed, 0.05)
	Input.action_release(&"walk")
	assert_almost_eq(await _speed_after_moving(), _player.settings.move_speed, 0.05, "runs again")


func test_keeps_the_pace_of_someone_walking_beside() -> void:
	var body := _walker(Vector3(0.0, 0.0, 2.0), 2.0)
	Input.action_press(&"walk")
	assert_almost_eq(await _speed_after_moving(), 2.0, 0.05, "the one beside")
	body.walk(0.0)
	assert_almost_eq(await _speed_after_moving(), _player.settings.walk_speed, 0.05, "stopped")


func test_the_nearest_walking_one_sets_the_pace() -> void:
	var tree: SceneTree = get_tree()
	_walker(Vector3(0.0, 0.0, 3.0), 2.0)
	_walker(Vector3(0.0, 0.0, 1.5), 1.1)
	_walker(Vector3(0.0, 0.0, 1.0), 0.0)
	var far := _walker(Vector3(0.0, 0.0, 10.0), 1.7)
	assert_almost_eq(NpcBody.pace_near(tree, Vector3.ZERO, 4.0), 1.1, 0.001)
	assert_eq(NpcBody.pace_near(tree, Vector3(0.0, 0.0, -5.0), 4.0), 0.0, "nobody near")
	far.visible = false
	assert_eq(NpcBody.pace_near(tree, Vector3(0.0, 0.0, 10.0), 4.0), 0.0, "hidden")


func test_the_legs_walk_and_step_closer() -> void:
	var running: float = _animator.step_length()
	Input.action_press(&"walk")
	await _speed_after_moving()
	assert_gt(_gait(), 0.9, "Walk plays")
	assert_lt(_animator.step_length(), running * 0.5, "shorter steps")
	Input.action_release(&"walk")
	await _speed_after_moving()
	assert_lt(_gait(), 0.1, "runs again")


func _gait() -> float:
	var amount: float = _animator.get(&"parameters/gait/blend_amount")
	return amount


func _walker(at: Vector3, speed: float) -> NpcBody:
	var body := BODY.instantiate() as NpcBody
	body.profile = COLONIST
	_arena.add_child(body)
	body.position = at
	body.walk(speed)
	return body


## The player's horizontal speed after moving right for half a second.
func _speed_after_moving() -> float:
	Input.action_press(&"move_right")
	await wait_physics_frames(30)
	await wait_process_frames(10)
	return Vector2(_player.velocity.x, _player.velocity.z).length()
