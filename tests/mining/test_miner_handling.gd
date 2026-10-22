extends GutTest
## Placing and picking up miners taking time: standing still, cancelling, the fold and its sounds,
## and the suit ring's miner ticks.

const TEST_MAP := preload("res://tests/support/test_map.gd")
const SERVO: Sound = preload("res://assets/audio/sfx/mining/miner_servo.tres")
const LATCH: Sound = preload("res://assets/audio/sfx/mining/miner_latch.tres")
const PLACE: Sound = preload("res://assets/audio/sfx/mining/miner_place.tres")

var _map: Node3D
var _player: Player
var _node: OreNode
var _played: Array[Sound] = []


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	_node = _map.get_node("Location/OreNodes/KyriteA") as OreNode
	_player.global_position = _node.global_position + Vector3(2.0, 0.0, 0.0)
	_player.reset_physics_interpolation()
	_played.clear()
	Sfx.played.connect(_on_played)
	await wait_physics_frames(2)


func after_each() -> void:
	Sfx.played.disconnect(_on_played)
	Sfx.stop_all()
	GameSettings.ring_always_show = false
	for action: StringName in [&"move_right", &"attack"]:
		Input.action_release(action)


func test_placing_takes_the_place_time() -> void:
	var miner: Miner = _player.place_miner()
	assert_not_null(miner)
	assert_eq(_node.miner, miner, "the node is taken at once")
	assert_true(_player.handling.busy())
	assert_false(miner.is_standing())
	assert_does_not_have(_played, PLACE, "no thud yet")
	await wait_physics_frames(3)
	assert_eq(miner.amount, 0.0, "it doesn't mine yet")
	assert_gt(miner.unfolded, 0.0)
	assert_has(_loops(miner), SERVO)
	_player.handling.update(miner.settings.place_time)
	assert_true(miner.is_standing())
	assert_false(_player.handling.busy())
	assert_has(_played, PLACE)
	await wait_physics_frames(2)
	var mined: float = miner.amount + _player.cargo.get(miner.ore_type, 0.0)
	assert_gt(mined, 0.0, "mining (the hose takes it to the player)")
	assert_does_not_have(_loops(miner), SERVO)


func test_nothing_else_is_placed_meanwhile() -> void:
	_player.place_miner()
	var left: int = _player.fleet.left_to_place()
	_player.global_position = (
		(_map.get_node("Location/OreNodes").get_child(1) as Node3D).global_position
	)
	assert_null(_player.place_miner())
	assert_eq(_player.fleet.left_to_place(), left)


func test_moving_cancels_placing() -> void:
	var miner: Miner = _player.place_miner()
	Input.action_press(&"move_right")
	await wait_physics_frames(2)
	assert_false(_player.handling.busy())
	assert_true(not is_instance_valid(miner) or miner.is_queued_for_deletion(), "back on the back")
	assert_true(_node.is_free())
	assert_eq(_player.fleet.left_to_place(), MinerFleet.PER_RUN, "nothing lost")


func test_attacking_cancels_placing() -> void:
	_player.place_miner()
	Input.action_press(&"attack")
	await wait_physics_frames(2)
	assert_false(_player.handling.busy())
	assert_true(_node.is_free())


func test_the_player_stands_still_with_the_weapon_lowered() -> void:
	var miner: Miner = _player.place_miner()
	await wait_physics_frames(2)
	assert_eq(_player.velocity.x, 0.0)
	assert_eq(_player.velocity.z, 0.0)
	assert_false(_player.weapon.trigger_held)
	var to_miner: Vector3 = miner.global_position - _player.global_position
	to_miner.y = 0.0
	assert_almost_eq(_player.aim.direction.dot(to_miner.normalized()), 1.0, 0.01, "facing it")


func test_damage_does_not_cancel() -> void:
	_player.place_miner()
	_player.take_damage(10.0)
	await wait_physics_frames(2)
	assert_true(_player.handling.busy())


func test_dying_cancels() -> void:
	_player.place_miner()
	_player.take_damage(_player.health)
	assert_false(_player.handling.busy())
	assert_true(_node.is_free())


func test_picking_up_takes_the_pick_up_time() -> void:
	var miner: Miner = _place_standing()
	miner.amount = 30.0
	await wait_physics_frames(2)
	_player.interact()
	assert_true(_player.handling.busy())
	assert_eq(miner.carrier, _player)
	assert_false(miner.is_standing(), "folding")
	_player.handling.update(miner.settings.pick_up_time * 0.5)
	assert_false(miner.is_queued_for_deletion())
	assert_almost_eq(miner.unfolded, 0.5, 0.01)
	_player.handling.update(miner.settings.pick_up_time * 0.5)
	assert_true(miner.is_queued_for_deletion())
	assert_true(_node.is_free())
	var carried: float = _player.cargo.get(miner.ore_type, 0.0)
	assert_almost_eq(carried, 30.0, 1.0)
	assert_has(_played, LATCH)


func test_moving_cancels_a_pickup_and_it_stands_again() -> void:
	var miner: Miner = _place_standing()
	await wait_physics_frames(2)
	_player.interact()
	_player.handling.update(1.0)
	Input.action_press(&"move_right")
	await wait_physics_frames(2)
	assert_false(_player.handling.busy())
	assert_false(miner.is_queued_for_deletion(), "it stays where it was")
	assert_null(miner.carrier)
	Input.action_release(&"move_right")
	await wait_seconds(Miner.STAND_TIME + 0.2)
	assert_true(miner.is_standing())


func test_a_miner_being_picked_up_cannot_be_taken_by_another() -> void:
	var miner: Miner = _place_standing()
	await wait_physics_frames(2)
	_player.interact()
	var other := preload("res://game/player/player.tscn").instantiate() as Player
	other.local = false
	_map.add_child(other)
	await wait_physics_frames(1)
	assert_false(other.handling.pick_up(miner))
	await wait_physics_frames(1)
	assert_false((miner.get_node("Pickup") as Interactable).enabled)


func test_the_ring_ticks_show_the_runs_miners() -> void:
	var ring := _player.get_node("SuitRing") as SuitRing
	await wait_physics_frames(1)
	await wait_process_frames(2)
	assert_eq(
		ring.miner_ticks,
		PackedFloat32Array([2.0, 1.0, 1.0, 1.0, 1.0, 1.0]),
		"M-01 bright, five standard-issue dimmer"
	)
	_player.place_miner()
	await wait_process_frames(2)
	assert_eq(ring.miner_ticks[0], -SuitRing.CRAFTED_TICK, "placed: an outline")
	assert_gt(ring.miners_alpha, 0.0)
	var shown: PackedFloat32Array = ring.shown(&"miner_ticks")
	assert_eq(shown, ring.miner_ticks)


func test_the_ring_ticks_hide_away_from_miners() -> void:
	var ring := _player.get_node("SuitRing") as SuitRing
	_player.global_position = _node.global_position + Vector3(20.0, 0.0, 0.0)
	_player.reset_physics_interpolation()
	await wait_seconds(SuitRing.FADE_TIME + 0.2)
	assert_eq(ring.miners_alpha, 0.0)


func test_always_show_keeps_the_ring_ticks_shown() -> void:
	var ring := _player.get_node("SuitRing") as SuitRing
	GameSettings.ring_always_show = true
	_player.global_position = _node.global_position + Vector3(20.0, 0.0, 0.0)
	_player.reset_physics_interpolation()
	await wait_seconds(SuitRing.FADE_TIME + 0.2)
	assert_eq(ring.miners_alpha, 1.0)


## A standing miner of the player's fleet on `_node`.
func _place_standing() -> Miner:
	return _node.place_miner(_player.miner_scene, _player.fleet, _player)


func _loops(holder: Node) -> Array[Sound]:
	var sounds: Array[Sound] = []
	for child: Node in holder.get_children():
		var player := child as AudioStreamPlayer3D
		if player and not player.is_queued_for_deletion():
			for sound: Sound in [SERVO]:
				if player.stream == sound.stream:
					sounds.append(sound)
	return sounds


func _on_played(sound: Sound, _critical: bool) -> void:
	_played.append(sound)
