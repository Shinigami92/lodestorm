extends GutTest
## The med beds in the medical bay, where players heal (health carries over between runs), and the
## hint at the ramp button that says so.

const TEST_MAP := preload("res://tests/support/map_fixture.gd")

var _map: Node3D
var _player: Player
var _ship: Ship


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	_ship = _map.get_node("Ship") as Ship
	await wait_physics_frames(2)


func test_lying_down_heals_to_full() -> void:
	_player.take_damage(60.0)
	var bed: MedBedStation = await _use_bed(1)
	assert_eq(bed.user, _player)
	assert_eq(_player.lying_on, bed.get_node("Lie"), "lies on the bed")
	assert_false(_player.weapon.visible, "its weapon put away")
	assert_true(bed.card.visible)
	assert_true(bed.is_healing())
	await wait_seconds(bed.heal_time * 0.6 * 0.5)
	assert_between(_player.health, 41.0, _player.max_health() - 1.0, "heals over time")
	await wait_seconds(bed.heal_time * 0.6 * 0.5 + 0.3)
	assert_eq(_player.health, _player.max_health())
	assert_false(bed.is_healing())
	var health := bed.card_menu.find_child("Health", true, false) as Label
	assert_string_contains(health.text, "%d / %d" % [100, 100])


func test_getting_up_stands_the_player_up() -> void:
	_player.take_damage(30.0)
	var bed: MedBedStation = await _use_bed(2)
	assert_true(bed.card_menu.press_primary(), "Get up")
	assert_null(bed.user)
	assert_null(_player.menu)
	assert_null(_player.lying_on)
	assert_eq(_player.weapon.visible, _player.weapon_allowed)
	assert_lt(_player.health, _player.max_health(), "got up early")


func test_every_player_has_a_bed() -> void:
	for i: int in 4:
		assert_not_null(_bed(i + 1), "med bed %d" % (i + 1))
		assert_true(_bed(i + 1).can_use(_player))


func test_ramp_hint_shows_once_when_hurt() -> void:
	var hint: RampHint = _ship.ramp_hint
	# The button only works (and is a target) with a mission picked.
	TEST_MAP.pick_mission(_map)
	await _stand_at_ramp_button()
	assert_null(hint.shown_for, "not at full health only")
	_player.take_damage(20.0)
	await wait_process_frames(2)
	assert_eq(hint.shown_for, _player)
	assert_true(_ship.story.is_set(RampHint.FLAG))
	await _move(_ship.get_respawn_position())
	assert_null(hint.shown_for, "gone once the player steps away")
	await _stand_at_ramp_button()
	assert_null(hint.shown_for, "only once")


func _bed(number: int) -> MedBedStation:
	return _ship.get_node("Rooms/Lower/MedicalBay/MedBed%d" % number) as MedBedStation


func _use_bed(number: int) -> MedBedStation:
	var bed: MedBedStation = _bed(number)
	var use: Interactable = bed.use_point
	# In front of it, within reach.
	await _move(use.to_global(Vector3(0.0, 0.0, use.footprint.y * 0.5 + use.interact_range - 0.3)))
	assert_eq(_player.interact(), use)
	return bed


func _stand_at_ramp_button() -> void:
	# On the floor beside the console, inside.
	var button: Vector3 = _ship.to_local(_ship.ramp_button.global_position)
	await _move(_ship.to_global(Vector3(button.x - 0.9, 2.5, button.z)))
	await wait_process_frames(2)
	assert_eq(_player.interact_target, _ship.ramp_button)


func _move(target: Vector3) -> void:
	_player.global_position = target
	_player.reset_physics_interpolation()
	await wait_physics_frames(5)
