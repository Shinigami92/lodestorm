extends GutTest
## An old survey repeller (`AlienRepeller`, Hollis' camp and his hand repeller): nobody within its
## reach is prey, and an alien inside walks out again.

const SWARMER: AlienStrain = preload("res://game/aliens/strains/swarmer/swarmer.tres")
const PLAYER_SCENE: PackedScene = preload("res://game/player/player.tscn")

var _arena: Node3D
var _player: Player
var _repeller: AlienRepeller


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
	_repeller = AlienRepeller.new()
	_repeller.radius = 12.0
	_arena.add_child(_repeller)
	_player = PLAYER_SCENE.instantiate() as Player
	_arena.add_child(_player)


func test_nobody_within_its_reach_is_prey() -> void:
	_player.global_position = Vector3(5.0, 0.0, 0.0)
	assert_false(Alien.is_prey(get_tree(), _player), "within its reach")
	_player.global_position = Vector3(20.0, 0.0, 0.0)
	assert_true(Alien.is_prey(get_tree(), _player), "outside")
	_repeller.visible = false
	_player.global_position = Vector3(5.0, 0.0, 0.0)
	assert_true(Alien.is_prey(get_tree(), _player), "a hidden one keeps nobody off")


func test_an_alien_leaves_it_alone() -> void:
	_player.global_position = Vector3(3.0, 0.0, 0.0)
	var alien: Alien = SWARMER.spawn()
	_arena.add_child(alien)
	alien.global_position = Vector3(8.0, 0.0, 0.0)
	await wait_physics_frames(90)
	assert_ne(alien.target, _player, "no prey in there")
	var offset: Vector3 = alien.global_position - _repeller.global_position
	assert_gt(Vector2(offset.x, offset.z).length(), 8.0, "walks out")
