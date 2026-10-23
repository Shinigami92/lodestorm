extends GutTest
## The in-game cursor: a reticle on the ground where the mouse points, only for the local player
## aiming with the mouse outside menus and pauses, dimmed (or following) while something is locked,
## and never on the player.

const SWARMER: AlienStrain = preload("res://game/aliens/strains/swarmer/swarmer.tres")
const PLAYER_SCENE: PackedScene = preload("res://game/player/player.tscn")
const KYRITE: OreType = preload("res://game/ores/types/ore_kyrite.tres")

var _arena: Node3D
var _player: Player
var _reticle: AimReticle


func before_each() -> void:
	_arena = Node3D.new()
	add_child_autofree(_arena)
	_player = PLAYER_SCENE.instantiate() as Player
	_arena.add_child(_player)
	_reticle = _player.reticle
	await wait_physics_frames(1)


func test_shows_where_the_mouse_points() -> void:
	_point_at(Vector3(3.0, 0.0, -4.0))
	assert_true(_reticle.visible)
	assert_almost_eq(_reticle.global_position, Vector3(3.0, 0.0, -4.0), Vector3.ONE * 0.001)


func test_only_with_the_mouse_on_the_ground() -> void:
	_point_at(Vector3(3.0, 0.0, -4.0))
	_player.aim.set(&"_with_mouse", false)
	_reticle._process(0.0)
	assert_false(_reticle.visible, "a stick aims by a direction")
	_point_at(Vector3.INF)
	assert_false(_reticle.visible, "no ground under the cursor")


func test_hidden_for_a_teammate_and_while_down() -> void:
	_player.local = false
	_point_at(Vector3(3.0, 0.0, -4.0))
	assert_false(_reticle.visible, "not the local player")
	_player.local = true
	_player.take_damage(_player.health + 1.0)
	_point_at(Vector3(3.0, 0.0, -4.0))
	assert_false(_reticle.visible, "down")


func test_dims_under_the_cursor_while_locked_or_follows_the_lock() -> void:
	var alien := SWARMER.spawn()
	_arena.add_child(alien)
	alien.global_position = Vector3(5.0, 0.0, -5.0)
	_point_at(Vector3(4.0, 0.0, -5.0))
	var unlocked: float = (_reticle.get_node("Decal") as Decal).albedo_mix
	_player.aim.target = alien
	_reticle._process(0.0)
	var decal := _reticle.get_node("Decal") as Decal
	assert_lt(decal.albedo_mix, unlocked, "dimmed")
	assert_almost_eq(_reticle.global_position, Vector3(4.0, 0.0, -5.0), Vector3.ONE * 0.001)
	_reticle.follows_lock = true
	_reticle._process(0.0)
	assert_almost_eq(_reticle.global_position, alien.global_position, Vector3.ONE * 0.001)
	assert_eq(decal.albedo_mix, unlocked)


## Nothing on the player catches the reticle (a decal): not the suit and what it carries (the
## weapon, the cargo tubes, the armor pips), and not the suit ring and the target brackets, which
## are drawn pulled towards the camera (it would paint a shifted copy of itself on them).
func test_leaves_the_player_out() -> void:
	# Enough for canisters beside the backpack.
	_player.add_cargo(KYRITE, 2000.0)
	await wait_process_frames(1)
	var decal := _reticle.get_node("Decal") as Decal
	assert_not_null(_player.weapon, "with a weapon")
	for node: Node in _player.find_children("*", "VisualInstance3D", true, false):
		if node != decal:
			var visual := node as VisualInstance3D
			assert_eq(visual.layers & decal.cull_mask, 0, str(_player.get_path_to(visual)))


## Aims the mouse at `point` on the ground and lets the reticle follow at once.
func _point_at(point: Vector3) -> void:
	_player.aim.set(&"_with_mouse", true)
	_player.aim.target = null
	_player.aim.cursor_point = point
	_reticle._process(0.0)
