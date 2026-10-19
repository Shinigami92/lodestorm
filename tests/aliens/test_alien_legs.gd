extends GutTest

const SWARMER: AlienStrain = preload("res://game/aliens/strains/swarmer/swarmer.tres")

var _alien: Alien
var _legs: AlienLegs


func before_each() -> void:
	var arena := Node3D.new()
	add_child_autofree(arena)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100.0, 1.0, 100.0)
	floor_shape.shape = box
	floor_shape.position.y = -0.5
	floor_body.add_child(floor_shape)
	arena.add_child(floor_body)
	_alien = SWARMER.spawn()
	arena.add_child(_alien)
	var skeleton: Skeleton3D = _alien.find_child("Skeleton3D", true, false)
	for child: Node in skeleton.get_children():
		if child is AlienLegs:
			_legs = child as AlienLegs
	await wait_seconds(Alien.HATCH_DURATION + 0.1)


func after_each() -> void:
	# Headless nothing is ever on screen: culling stays off in tests unless one turns it on.
	Alien.culls_off_screen = false


func test_two_bone_reaches_the_target_bending_to_the_pole() -> void:
	var root := Vector3(0.0, 1.0, 0.0)
	var target := Vector3(0.0, 0.2, 0.3)
	var result: Array[Vector3] = AlienLegs.two_bone(root, target, 0.5, 0.5, Vector3.FORWARD)
	var joint: Vector3 = result[0]
	assert_almost_eq(root.distance_to(joint), 0.5, 0.001, "upper length kept")
	assert_almost_eq(joint.distance_to(result[1]), 0.5, 0.001, "lower length kept")
	assert_almost_eq(result[1].distance_to(target), 0.0, 0.001, "reaches the target")
	assert_lt(joint.z, root.z, "bends towards the pole (forward is -Z)")


func test_two_bone_stretches_towards_a_target_out_of_reach() -> void:
	var result: Array[Vector3] = AlienLegs.two_bone(
		Vector3.ZERO, Vector3(0.0, -3.0, 0.0), 0.5, 0.5, Vector3.FORWARD
	)
	assert_almost_eq(result[1].y, -1.0, 0.01)
	assert_almost_eq(result[1].x, 0.0, 0.001)


func test_feet_stand_on_the_ground_under_the_body() -> void:
	assert_eq(_legs.feet.size(), 4)
	for leg: String in _legs.feet:
		var foot: Vector3 = _legs.feet[leg]
		assert_almost_eq(foot.y, 0.0, 0.01, "%s on the floor" % leg)
		assert_lt(_horizontal(foot - _alien.global_position), 0.8, "%s under the body" % leg)


func test_feet_stay_planted_while_standing() -> void:
	var before: Dictionary[String, Vector3] = _legs.feet.duplicate()
	await wait_physics_frames(30)
	for leg: String in before:
		assert_eq(_legs.feet[leg], before[leg], "%s stays put" % leg)


func test_feet_step_after_the_moving_body_in_diagonal_pairs() -> void:
	var start: Dictionary[String, Vector3] = _legs.feet.duplicate()
	var both_pairs_up: bool = false
	# Walk 3 m forward at 3 m/s.
	for frame: int in 60:
		_alien.global_position += Vector3(0.0, 0.0, -0.05)
		await wait_physics_frames(1)
		both_pairs_up = both_pairs_up or _pairs_stepping() == 2
	# Once its speed has faded, the feet that landed ahead step back under it, a pair at a time.
	await wait_seconds(0.3)
	await wait_while(_legs.is_stepping, 2.0)
	assert_false(both_pairs_up, "one pair stands while the other steps")
	for leg: String in start:
		var foot: Vector3 = _legs.feet[leg]
		assert_lt(foot.z, start[leg].z - 2.0, "%s followed" % leg)
		assert_lt(_horizontal(foot - _alien.global_position), 0.8, "%s under the body" % leg)
		assert_almost_eq(foot.y, 0.0, 0.01, "%s back on the floor" % leg)
	assert_false(_legs.is_stepping(), "all feet planted once it stands")


func test_legs_let_go_when_the_alien_dies() -> void:
	_alien.take_damage(_alien.strain.max_health)
	assert_false(_legs.active)


func test_off_screen_its_legs_and_clips_stop() -> void:
	# Headless nothing is ever on screen: with culling on, the alien is off screen.
	Alien.culls_off_screen = true
	_alien._on_screen_changed()
	assert_true(_legs.culled, "its legs don't step")
	assert_false((_alien.get_node("Animator") as AnimationTree).active, "its clips stop")
	assert_false(_alien.is_processing(), "nor does its pose change")
	var before: Dictionary[String, Vector3] = _legs.feet.duplicate()
	_alien.global_position += Vector3(0.0, 0.0, -3.0)
	await wait_physics_frames(10)
	assert_eq(_legs.feet, before, "the feet stay behind")
	Alien.culls_off_screen = false
	_alien._on_screen_changed()
	await wait_physics_frames(2)
	assert_false(_legs.culled)
	for leg: String in _legs.feet:
		var foot: Vector3 = _legs.feet[leg]
		assert_lt(_horizontal(foot - _alien.global_position), 0.8, "%s put down under it" % leg)


func _pairs_stepping() -> int:
	var pairs: int = 0
	for pair: Array in [["FrontLeft", "HindRight"], ["FrontRight", "HindLeft"]]:
		for leg: String in pair:
			if _legs.feet[leg].y > 0.005:
				pairs += 1
				break
	return pairs


func _horizontal(offset: Vector3) -> float:
	return Vector2(offset.x, offset.z).length()
