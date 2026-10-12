extends GutTest

const TEST_MAP := preload("res://tests/support/test_map.gd")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const ALL_WEAPONS: Arsenal = preload("res://scenes/weapons/all_weapons.tres")
const BLASTER: WeaponType = preload("res://scenes/weapons/types/blaster.tres")
const SHOTGUN: WeaponType = preload("res://scenes/weapons/types/shotgun.tres")
const HAMMER: WeaponType = preload("res://scenes/weapons/types/hammer.tres")
## In front of the console in the armory (ship-local).
const AT_CONSOLE := Vector3(-8.0, 2.5, -12.4)

var _map: Node3D
var _player: Player
var _mission: Mission
var _ship: Ship


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	_mission = _map.get_node("Mission") as Mission
	_ship = _map.get_node("Ship") as Ship
	_ship.ramp_duration = 0.25
	await wait_physics_frames(2)


func after_each() -> void:
	Input.action_release(&"switch_weapon")


func test_catalog_lists_every_weapon_once() -> void:
	assert_eq(ALL_WEAPONS.weapons, [BLASTER, SHOTGUN, HAMMER] as Array[WeaponType])
	for weapon_type: WeaponType in ALL_WEAPONS.weapons:
		assert_ne(weapon_type.display_name, "")
		assert_ne(weapon_type.description, "")
		assert_is(weapon_type.scene.instantiate(), Weapon)
	assert_eq(HAMMER.kind, WeaponType.Kind.MELEE)
	assert_eq(SHOTGUN.kind, WeaponType.Kind.RANGED)


func test_new_player_owns_blaster_and_hammer() -> void:
	assert_eq(_player.arsenal.weapons, [BLASTER, HAMMER] as Array[WeaponType])
	assert_false(_player.arsenal.owns(SHOTGUN))
	assert_eq(_player.settings.loadout_slots, 2)
	assert_eq(_player.loadout.weapons, [BLASTER, HAMMER] as Array[WeaponType])
	assert_eq(_player.get_weapon_type(), BLASTER)


func test_unlock_adds_a_weapon_once() -> void:
	assert_true(_player.arsenal.unlock(SHOTGUN))
	assert_false(_player.arsenal.unlock(SHOTGUN))
	assert_eq(_player.arsenal.weapons.count(SHOTGUN), 1)


func test_each_player_has_its_own_arsenal_and_loadout() -> void:
	var other := PLAYER_SCENE.instantiate() as Player
	_map.add_child(other)
	_player.arsenal.unlock(SHOTGUN)
	_player.loadout.assign(0, SHOTGUN)
	assert_false(other.arsenal.owns(SHOTGUN))
	assert_eq(other.loadout.get_weapon(0), BLASTER)
	var defaults := load("res://scenes/player/default_loadout.tres") as Loadout
	assert_eq(defaults.get_weapon(0), BLASTER, "the default resource stays untouched")


func test_assigning_a_weapon_in_another_slot_swaps_them() -> void:
	var loadout := Loadout.new()
	loadout.assign(1, HAMMER)
	assert_eq(loadout.weapons, [null, HAMMER] as Array[WeaponType])
	loadout.assign(0, BLASTER)
	loadout.assign(0, HAMMER)
	assert_eq(loadout.weapons, [HAMMER, BLASTER] as Array[WeaponType])
	loadout.assign(1, null)
	assert_null(loadout.get_weapon(1))
	assert_eq(loadout.slot_of(HAMMER), 0)
	assert_eq(loadout.slot_of(BLASTER), -1)


func test_switch_action_cycles_the_loadout() -> void:
	assert_is(_player.weapon, RangedWeapon)
	Input.action_press(&"switch_weapon")
	await wait_physics_frames(2)
	Input.action_release(&"switch_weapon")
	assert_eq(_player.weapon_slot, 1)
	assert_eq(_player.get_weapon_type(), HAMMER)
	assert_is(_player.weapon, MeleeWeapon)
	assert_eq(_player.weapon.get_parent().name, &"WeaponMount")
	assert_true(_player.switch_weapon())
	assert_eq(_player.get_weapon_type(), BLASTER)
	assert_eq(_player.get_node("WeaponMount").get_child_count(), 1, "the old weapon is gone")


func test_no_switch_with_one_weapon() -> void:
	_player.loadout.assign(1, null)
	assert_false(_player.switch_weapon())
	assert_eq(_player.get_weapon_type(), BLASTER)


func test_changing_the_loadout_changes_the_weapon() -> void:
	_player.arsenal.unlock(SHOTGUN)
	_player.loadout.assign(0, SHOTGUN)
	assert_eq(_player.get_weapon_type(), SHOTGUN)
	_player.loadout.assign(0, null)
	assert_eq(_player.weapon_slot, 1, "the other slot's weapon")
	assert_eq(_player.get_weapon_type(), HAMMER)
	_player.loadout.assign(1, null)
	assert_null(_player.weapon)
	assert_null(_player.get_weapon_type())


func test_switched_weapon_stays_holstered_aboard() -> void:
	_player.global_position = _ship.to_global(AT_CONSOLE)
	_player.reset_physics_interpolation()
	await wait_physics_frames(2)
	assert_false(_player.weapon_allowed)
	_player.switch_weapon()
	assert_false(_player.weapon.visible)


func test_armory_console_assigns_slots() -> void:
	var menu: ArmoryMenu = await _open_console()
	var hammer: Array[Button] = menu.get_slot_buttons(HAMMER)
	assert_eq(hammer.size(), 2)
	assert_false(hammer[0].button_pressed)
	assert_true(hammer[1].button_pressed, "the hammer is in slot 2")
	hammer[0].pressed.emit()
	assert_eq(_player.loadout.weapons, [HAMMER, BLASTER] as Array[WeaponType], "swapped")
	await wait_process_frames(1)
	assert_true(hammer[0].button_pressed)
	assert_true(menu.get_slot_buttons(BLASTER)[1].button_pressed)
	hammer[0].pressed.emit()
	assert_null(_player.loadout.get_weapon(0), "pressing it again takes it out")


func test_armory_console_shows_locked_weapons() -> void:
	var menu: ArmoryMenu = await _open_console()
	for button: Button in menu.get_slot_buttons(SHOTGUN):
		assert_true(button.disabled, "not owned yet")
	_player.arsenal.unlock(SHOTGUN)
	await wait_process_frames(2)
	var shotgun: Array[Button] = menu.get_slot_buttons(SHOTGUN)
	assert_false(shotgun[0].disabled)
	shotgun[0].pressed.emit()
	assert_eq(_player.loadout.get_weapon(0), SHOTGUN)


func test_armory_console_locks_while_a_mission_is_underway() -> void:
	var menu: ArmoryMenu = await _open_console()
	TEST_MAP.pick_mission(_map)
	_ship.ramp_button.use(_player)
	await wait_process_frames(2)
	assert_true(menu.is_locked())
	var hammer: Array[Button] = menu.get_slot_buttons(HAMMER)
	assert_true(hammer[0].disabled)
	hammer[0].pressed.emit()
	assert_eq(_player.loadout.get_weapon(0), BLASTER, "unchanged")


func test_debug_overlay_unlocks_every_weapon() -> void:
	var overlay: CanvasLayer = get_tree().root.get_node("DebugOverlay") as CanvasLayer
	overlay.call(&"unlock_weapons")
	for weapon_type: WeaponType in ALL_WEAPONS.weapons:
		assert_true(_player.arsenal.owns(weapon_type))


func _open_console() -> ArmoryMenu:
	var terminal := _ship.get_node("Rooms/Lower/Armory/ArmoryTerminal") as Terminal
	_player.global_position = _ship.to_global(AT_CONSOLE)
	_player.reset_physics_interpolation()
	await wait_physics_frames(5)
	assert_eq(_player.interact(), terminal)
	var menu := terminal.panel.content as ArmoryMenu
	await wait_process_frames(2)
	assert_eq(menu.player, _player)
	return menu
