extends GutTest
## The drive core in the engine room: the heat shield's plates as parts, the card's project and
## payment, the plates' look by state, and the navigator's card of a body out of reach.

const TEST_MAP := preload("res://tests/support/map_fixture.gd")
const MERIDINE: OreType = preload("res://game/ores/types/ore_meridine.tres")
const VYREL: OreType = preload("res://game/ores/types/ore_vyrel.tres")

var _map: Node3D
var _player: Player
var _ship: Ship
var _mission: Mission
var _voyage: Voyage
var _core: HeatShieldStation


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	_ship = _map.get_node("Ship") as Ship
	_mission = _map.get_node("Mission") as Mission
	_voyage = _map.get_node("Voyage") as Voyage
	_ship.ramp_duration = 0.25
	_core = _ship.get_node("Rooms/Lower/EngineRoom/DriveCore") as HeatShieldStation
	await wait_physics_frames(2)


func after_each() -> void:
	# What the game frees a frame late (a swapped model, weapon or view) isn't counted as an orphan.
	await wait_process_frames(1)


func test_a_plate_per_level_with_the_next_one_selected() -> void:
	await _use()
	assert_eq(_core.get_parts().size(), _ship.heat_shield.max_mk() - 1)
	assert_eq(_core.selected, _core.get_plate_part(2), "the next plate")
	var card := _core.card_menu as HeatShieldCard
	assert_eq(card.mk, 2)
	assert_true(card.get_project_button().visible)
	assert_true(card.get_project_button().disabled == false)
	assert_true(card.get_pay_button().disabled, "nothing in the hold")
	assert_has(_core.opened_by(2), "Vehra")
	assert_eq(_core.opened_by(4).size(), 2, "the gas giant's two moons")


func test_making_it_the_project_and_paying_the_rest() -> void:
	await _use()
	var card := _core.card_menu as HeatShieldCard
	assert_true(card.press_primary(), "makes it the ship's project")
	assert_true(_ship.heat_shield.project)
	assert_true(card.get_project_button().disabled, "it is already")
	_player.hold.add(MERIDINE, 1000.0)
	_player.hold.add(VYREL, 1000.0)
	await wait_process_frames(1)
	assert_false(card.get_pay_button().disabled)
	assert_true(card.press_primary(), "pays the rest")
	assert_eq(_ship.heat_shield.mk, 2, "installed")
	assert_eq(_player.hold.amount(MERIDINE), 850.0)
	await wait_process_frames(1)
	_core.select(_core.get_plate_part(3))
	assert_eq(card.mk, 3)
	assert_false(_ship.heat_shield.project, "the next plate isn't the project yet")


func test_later_and_installed_plates_cannot_be_worked_on() -> void:
	await _use()
	_player.hold.add(MERIDINE, 1000.0)
	assert_false(_core.set_project(3), "not the next one")
	assert_false(_core.pay(3))
	_core.select(_core.get_plate_part(3))
	var card := _core.card_menu as HeatShieldCard
	assert_false(card.get_project_button().visible)
	assert_false(card.press_primary())
	_ship.heat_shield.install_next()
	assert_false(_core.set_project(2), "installed")


func test_locked_while_a_mission_is_underway() -> void:
	TEST_MAP.pick_mission(_map)
	_ship.ramp_button.use(_player)
	assert_true(_mission.is_underway())
	await _use()
	assert_true(_core.is_locked())
	assert_false(_core.set_project(2))
	var card := _core.card_menu as HeatShieldCard
	assert_true(card.get_project_button().disabled)


func test_plates_show_their_state() -> void:
	await wait_process_frames(2)
	var installed: StationPart = _core.get_plate_part(2)
	var later: StationPart = _core.get_plate_part(4)
	assert_true((installed.outline.get_node("Shell") as Node3D).visible, "the next one is there")
	assert_false((later.outline.get_node("Shell") as Node3D).visible, "later ones are outlines")
	assert_false((installed.get_parent().get_node("Fill") as Node3D).visible, "nothing paid yet")
	_ship.heat_shield.set_project()
	_ship.store_haul({MERIDINE: 150.0}, [_player])
	assert_true((installed.get_parent().get_node("Fill") as Node3D).visible, "fills as it's paid")
	_ship.heat_shield.install_next()
	assert_false((installed.get_parent().get_node("Fill") as Node3D).visible)
	var shell := installed.outline.get_node("Shell") as MeshInstance3D
	var material := shell.material_override as StandardMaterial3D
	assert_true(material.emission_enabled, "installed plates glow")


func test_navigator_says_what_a_locked_planet_needs() -> void:
	var navigator := _ship.get_node("Rooms/Upper/Bridge/Navigator") as NavigatorStation
	navigator.open(_player)
	await wait_process_frames(1)
	var vehra: CelestialBody = _voyage.settings.system.body_by_id(&"vehra")
	navigator.select(navigator.get_part(vehra))
	await wait_process_frames(1)
	var card := navigator.card_menu as NavigatorCard
	var status := card.get_node("%Status") as Label
	var needs := card.get_node("%Needs") as HFlowContainer
	assert_eq(status.text, "Needs heat shield MK2 (engine room)")
	assert_true(needs.visible)
	assert_eq(needs.get_child_count(), _ship.heat_shield.plate_for(2).cost.size())
	_ship.heat_shield.install_next()
	navigator.select(navigator.get_part(vehra))
	await wait_process_frames(1)
	assert_false(needs.visible, "in reach now")


func _use() -> void:
	var use: Interactable = _core.use_point
	# In front of it, within reach.
	_player.global_position = use.to_global(
		Vector3(0.0, 0.0, use.footprint.y * 0.5 + use.interact_range - 0.3)
	)
	_player.reset_physics_interpolation()
	await wait_physics_frames(5)
	assert_eq(_player.interact(), use)
	await wait_process_frames(1)
