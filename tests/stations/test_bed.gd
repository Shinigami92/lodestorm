extends GutTest
## The beds in the player cabins, where players quit the game ("Sleep").

const TEST_MAP := preload("res://tests/support/test_map.gd")

var _map: Node3D
var _player: Player
var _ship: Ship


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	_ship = _map.get_node("Ship") as Ship
	_ship.ramp_duration = 0.25
	for i: int in 4:
		_bed(i + 1).quits = false
	await wait_physics_frames(2)


func test_own_bed_opens_its_card() -> void:
	var bed: BedStation = await _use_bed()
	assert_eq(bed.user, _player)
	assert_eq(_player.menu, bed)
	assert_not_null(bed.selected, "the bed")
	assert_true(bed.card.visible)


func test_only_the_own_bed_works() -> void:
	assert_true(_bed(1).can_use(_player), "cabin 1 is the solo player's")
	for i: int in range(2, 5):
		assert_false(_bed(i).can_use(_player), "cabin %d" % i)
		_bed(i).use_point.use(_player)
		assert_null(_bed(i).user)


func test_sleeping_saves_and_fades_out() -> void:
	var bed: BedStation = await _use_bed()
	var card := bed.card_menu as BedCard
	assert_false(bed.loses_run())
	assert_true(card.press_primary(), "Sleep")
	assert_true(bed.asleep)
	assert_false(bed.card.visible, "the card goes")
	assert_eq(bed.user, _player, "the camera stays on the bed while it fades out")
	await wait_seconds(ScreenFade.QUIT_TIME + 0.3)
	assert_null(bed.user, "then it's over")
	assert_null(_player.menu)
	assert_false(bed.can_use(_player), "once is enough")
	assert_false(bed.sleep())


func test_sleeping_during_a_run_warns_that_it_is_lost() -> void:
	TEST_MAP.pick_mission(_map)
	_ship.ramp_button.use(_player)
	var bed: BedStation = await _use_bed()
	assert_true(bed.loses_run())
	await wait_process_frames(1)
	var note := bed.card_menu.find_child("Note", true, false) as Label
	assert_string_contains(note.text, "lose")


func test_settings_terminal_stays_the_target_in_front_of_it() -> void:
	var terminal := _ship.get_node("Rooms/Upper/Cabin1/Terminal") as Terminal
	_player.global_position = terminal.global_position + terminal.global_basis.z * 1.3
	_player.reset_physics_interpolation()
	await wait_physics_frames(5)
	assert_eq(_player.interact(), terminal, "not the bed beside it")


func _bed(number: int) -> BedStation:
	return _ship.get_node("Rooms/Upper/Cabin%d/BedStation" % number) as BedStation


func _use_bed() -> BedStation:
	var bed: BedStation = _bed(1)
	var use: Interactable = bed.use_point
	_player.global_position = use.global_position
	_player.reset_physics_interpolation()
	await wait_physics_frames(5)
	assert_eq(_player.interact(), use)
	await wait_process_frames(1)
	return bed
