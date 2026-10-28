extends GutTest

const TEST_MAP := preload("res://tests/support/map_fixture.gd")
const PLAYER_SCENE: PackedScene = preload("res://game/player/player.tscn")
const ALL_WEAPONS: Arsenal = preload("res://game/weapons/all_weapons.tres")
const HARL: WeaponType = preload("res://game/weapons/types/harl/harl.tres")
const BRASK: WeaponType = preload("res://game/weapons/types/brask/brask.tres")
const DRAY: WeaponType = preload("res://game/weapons/types/dray/dray.tres")
## In the armory (ship-local).
const IN_ARMORY := Vector3(-8.0, 2.5, -12.4)

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
	var names: Array[String] = []
	names.assign(ALL_WEAPONS.weapons.map(func(w: WeaponType) -> String: return w.display_name))
	assert_eq(
		names,
		[
			"Harl",
			"Brask",
			"Pinner",
			"Grindle",
			"Quill",
			"Dray",
			"Riven",
			"Wick",
			"Auger",
			"Tremor",
			"Scald",
			"Jag",
			"Kith",
			"Zenith",
			"Fulgen",
			"Nadir",
			"Clout",
			"Mantle",
		]
	)
	for weapon_type: WeaponType in ALL_WEAPONS.weapons:
		assert_ne(weapon_type.display_name, "")
		assert_ne(weapon_type.description, "")
		var weapon: Node = weapon_type.scene.instantiate()
		assert_is(weapon, Weapon)
		weapon.free()
	assert_true(DRAY.is_melee())
	assert_false(BRASK.is_melee())


func test_new_player_owns_harl_and_dray() -> void:
	assert_eq(_player.arsenal.weapons, [HARL, DRAY] as Array[WeaponType])
	assert_false(_player.arsenal.owns(BRASK))
	assert_eq(_player.settings.loadout_slots, 2)
	assert_eq(_player.loadout.weapons, [HARL, DRAY] as Array[WeaponType])
	assert_eq(_player.arms.get_weapon_type(), HARL)


func test_unlock_adds_a_weapon_once() -> void:
	assert_true(_player.arsenal.unlock(BRASK))
	assert_false(_player.arsenal.unlock(BRASK))
	assert_eq(_player.arsenal.weapons.count(BRASK), 1)


func test_each_player_has_its_own_arsenal_and_loadout() -> void:
	var other := PLAYER_SCENE.instantiate() as Player
	_map.add_child(other)
	_player.arsenal.unlock(BRASK)
	_player.loadout.assign(0, BRASK)
	assert_false(other.arsenal.owns(BRASK))
	assert_eq(other.loadout.get_weapon(0), HARL)
	var defaults := load("res://game/player/default_loadout.tres") as Loadout
	assert_eq(defaults.get_weapon(0), HARL, "the default resource stays untouched")


func test_assigning_a_weapon_in_another_slot_swaps_them() -> void:
	var loadout := Loadout.new()
	loadout.assign(1, DRAY)
	assert_eq(loadout.weapons, [null, DRAY] as Array[WeaponType])
	loadout.assign(0, HARL)
	loadout.assign(0, DRAY)
	assert_eq(loadout.weapons, [DRAY, HARL] as Array[WeaponType])
	loadout.assign(1, null)
	assert_null(loadout.get_weapon(1))
	assert_eq(loadout.slot_of(DRAY), 0)
	assert_eq(loadout.slot_of(HARL), -1)


func test_switch_action_cycles_the_loadout() -> void:
	assert_not_null(_player.arms.get_ammo())
	Input.action_press(&"switch_weapon")
	await wait_physics_frames(2)
	Input.action_release(&"switch_weapon")
	assert_eq(_player.arms.slot, 1)
	assert_eq(_player.arms.get_weapon_type(), DRAY)
	assert_true(_player.arms.get_weapon_type().is_melee())
	assert_eq(_player.arms.weapon.get_parent().name, &"WeaponMount")
	assert_true(_player.arms.switch_weapon())
	assert_eq(_player.arms.get_weapon_type(), HARL)
	assert_eq(_player.get_node("WeaponMount").get_child_count(), 1, "the old weapon is gone")


func test_no_switch_with_one_weapon() -> void:
	_player.loadout.assign(1, null)
	assert_false(_player.arms.switch_weapon())
	assert_eq(_player.arms.get_weapon_type(), HARL)


func test_changing_the_loadout_changes_the_weapon() -> void:
	_player.arsenal.unlock(BRASK)
	_player.loadout.assign(0, BRASK)
	assert_eq(_player.arms.get_weapon_type(), BRASK)
	_player.loadout.assign(0, null)
	assert_eq(_player.arms.slot, 1, "the other slot's weapon")
	assert_eq(_player.arms.get_weapon_type(), DRAY)
	_player.loadout.assign(1, null)
	assert_null(_player.arms.weapon)
	assert_null(_player.arms.get_weapon_type())


func test_switched_weapon_stays_holstered_aboard() -> void:
	_player.global_position = _ship.to_global(IN_ARMORY)
	_player.reset_physics_interpolation()
	await wait_physics_frames(2)
	assert_false(_player.arms.allowed)
	_player.arms.switch_weapon()
	assert_false(_player.arms.weapon.visible)


func test_debug_overlay_unlocks_every_weapon() -> void:
	var overlay: CanvasLayer = get_tree().root.get_node("DebugOverlay") as CanvasLayer
	overlay.call(&"_unlock_weapons")
	for weapon_type: WeaponType in ALL_WEAPONS.weapons:
		assert_true(_player.arsenal.owns(weapon_type))
