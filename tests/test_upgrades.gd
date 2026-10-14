extends GutTest

const TEST_MAP := preload("res://tests/support/test_map.gd")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const MINER_SCENE: PackedScene = preload("res://scenes/mining/miner.tscn")
const ALL_WEAPONS: Arsenal = preload("res://scenes/weapons/all_weapons.tres")
const BLASTER: WeaponType = preload("res://scenes/weapons/types/blaster.tres")
const SHOTGUN: WeaponType = preload("res://scenes/weapons/types/shotgun.tres")
const HAMMER: WeaponType = preload("res://scenes/weapons/types/hammer.tres")
const ARMOR: Upgrade = preload("res://scenes/upgrades/armor.tres")
const DRILL: Upgrade = preload("res://scenes/upgrades/miner_drill.tres")
const TANK: Upgrade = preload("res://scenes/upgrades/miner_tank.tres")
const HOSE: Upgrade = preload("res://scenes/upgrades/miner_hose.tres")
const CYAN: OreType = preload("res://scenes/mining/ores/ore_cyan.tres")
const GREEN: OreType = preload("res://scenes/mining/ores/ore_green.tres")
const VIOLET: OreType = preload("res://scenes/mining/ores/ore_violet.tres")
## In front of the consoles in the upgrade rooms (ship-local).
const AT_CONSOLES: Dictionary[String, Vector3] = {
	"Weapons": Vector3(-42.6875, 2.5, 5.1),
	"Armor": Vector3(-30.5625, 2.5, 5.1),
	"Miners": Vector3(-6.3125, 2.5, 5.1),
}

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
	Input.action_release(&"attack")


func test_every_upgrade_has_texts_and_rising_levels() -> void:
	var all: Array[Upgrade] = [ARMOR, DRILL, TANK, HOSE]
	for weapon_type: WeaponType in ALL_WEAPONS.weapons:
		assert_not_null(weapon_type.upgrade, "%s has MK levels" % weapon_type.display_name)
		all.append(weapon_type.upgrade)
	for upgrade: Upgrade in all:
		assert_ne(upgrade.display_name, "")
		assert_ne(upgrade.description, "")
		assert_eq(upgrade.max_mk(), 3, "MK1 to MK3 for now")
		var previous: float = 1.0
		for level: UpgradeLevel in upgrade.levels:
			assert_gt(level.multiplier, previous)
			previous = level.multiplier
			assert_false(level.cost.is_empty())
			for ore_type: OreType in level.cost:
				assert_gt(level.cost[ore_type], 0)


func test_higher_levels_ask_for_rarer_ores() -> void:
	for weapon_type: WeaponType in ALL_WEAPONS.weapons:
		var levels: Array[UpgradeLevel] = weapon_type.upgrade.levels
		assert_eq(levels[0].cost.keys(), [CYAN])
		assert_eq(levels[1].cost.keys(), [CYAN, GREEN])
	for upgrade: Upgrade in [ARMOR, DRILL, TANK, HOSE] as Array[Upgrade]:
		assert_eq(upgrade.levels[0].cost.keys(), [CYAN])
		assert_has(upgrade.levels[1].cost, VIOLET, "%s's top level" % upgrade.display_name)


func test_levels_start_at_mk1_and_rise_to_the_highest() -> void:
	var upgrades := Upgrades.new()
	assert_eq(upgrades.mk(ARMOR), 1)
	assert_eq(upgrades.multiplier(ARMOR), 1.0)
	assert_eq(upgrades.next_level(ARMOR), ARMOR.levels[0])
	assert_eq(upgrades.mk(null), 1)
	assert_eq(upgrades.multiplier(null), 1.0)
	watch_signals(upgrades)
	assert_true(upgrades.raise(ARMOR))
	assert_signal_emitted(upgrades, "changed")
	assert_eq(upgrades.mk(ARMOR), 2)
	assert_eq(upgrades.multiplier(ARMOR), ARMOR.levels[0].multiplier)
	assert_true(upgrades.raise(ARMOR))
	assert_eq(upgrades.multiplier(ARMOR), ARMOR.levels[1].multiplier)
	assert_null(upgrades.next_level(ARMOR))
	assert_false(upgrades.raise(ARMOR), "MK3 is the highest")
	assert_eq(upgrades.mk(ARMOR), 3)


func test_hold_pays_only_what_it_has() -> void:
	var cost: Dictionary[OreType, int] = {CYAN: 200, GREEN: 100}
	assert_false(_ship.can_pay(cost))
	_ship.add_to_hold(CYAN, 300.0)
	assert_false(_ship.can_pay(cost), "no green yet")
	assert_false(_ship.pay(cost))
	assert_eq(_ship.hold[CYAN], 300.0, "nothing taken")
	_ship.add_to_hold(GREEN, 100.0)
	assert_true(_ship.pay(cost))
	assert_eq(_ship.hold[CYAN], 100.0)
	assert_eq(_ship.hold[GREEN], 0.0)
	var rack := _ship.get_node("HoldRack") as CargoRack
	assert_eq(rack.canister_count(GREEN), 0, "the canisters show what's left")
	assert_eq(rack.canister_count(CYAN), 1)


func test_weapon_upgrade_raises_its_damage_and_lights_its_pips() -> void:
	assert_eq(_player.get_weapon_type(), BLASTER)
	assert_eq(_player.weapon.damage_multiplier, 1.0)
	var pips := _player.weapon.get_node("MkPips") as MkPips
	assert_eq(pips.lit_count(), 1)
	assert_eq(pips.max_mk, 3)
	_player.upgrades.raise(BLASTER.upgrade)
	assert_eq(_player.weapon.damage_multiplier, BLASTER.upgrade.levels[0].multiplier)
	assert_eq(pips.lit_count(), 2)
	_player.switch_weapon()
	assert_eq(_player.get_weapon_type(), HAMMER)
	assert_eq(_player.weapon.damage_multiplier, 1.0, "each weapon has its own level")
	_player.switch_weapon()
	assert_eq(_player.weapon.damage_multiplier, BLASTER.upgrade.levels[0].multiplier)


func test_every_weapon_shows_pips() -> void:
	for weapon_type: WeaponType in ALL_WEAPONS.weapons:
		var weapon := weapon_type.scene.instantiate() as Weapon
		weapon.apply_upgrades(Upgrades.new(), weapon_type)
		var pips := weapon.get_node_or_null("MkPips") as MkPips
		assert_not_null(pips, weapon_type.display_name)
		if pips:
			assert_eq(pips.get_child_count(), 3)
		weapon.free()


func test_projectiles_carry_the_upgraded_damage() -> void:
	_player.upgrades.raise(BLASTER.upgrade)
	_player.upgrades.raise(BLASTER.upgrade)
	# Weapons are holstered inside the ship, where the player starts.
	_player.global_position = _ship.to_global(Vector3(22.0, 0.0, 0.0))
	_player.reset_physics_interpolation()
	await wait_physics_frames(2)
	assert_true(_player.weapon_allowed, "outside the ship")
	Input.action_press(&"attack")
	await wait_physics_frames(2)
	Input.action_release(&"attack")
	var projectiles: Array[Projectile] = []
	for node: Node in _player.get_parent().get_children():
		if node is Projectile:
			projectiles.append(node as Projectile)
	assert_false(projectiles.is_empty())
	var settings := (_player.weapon as RangedWeapon).settings
	for projectile: Projectile in projectiles:
		assert_eq(projectile.damage, settings.damage * BLASTER.upgrade.levels[1].multiplier)


func test_armor_upgrade_adds_health_and_lights_its_pips() -> void:
	var base: float = _player.settings.max_health
	_player.take_damage(30.0)
	assert_eq(_player.get_armor_pips().lit_count(), 1)
	assert_eq(_player.get_armor_pips().max_mk, 3)
	_player.upgrades.raise(ARMOR)
	assert_eq(_player.max_health(), base * ARMOR.levels[0].multiplier)
	assert_eq(_player.health, _player.max_health() - 30.0, "the extra health is added")
	assert_eq(_player.get_armor_pips().lit_count(), 2)
	_player.heal()
	assert_eq(_player.health, _player.max_health())
	_player.take_damage(_player.health)
	await wait_physics_frames(1)
	_player.respawn(_ship.get_respawn_position())
	assert_eq(_player.health, base * ARMOR.levels[0].multiplier, "respawns with the armor")


func test_armor_pips_sit_on_the_helmet() -> void:
	await wait_process_frames(2)
	var pips: MkPips = _player.get_armor_pips()
	var local: Vector3 = _player.to_local(pips.global_position)
	assert_between(local.y, 1.7, 1.9, "on top of the helmet")
	assert_lt(Vector2(local.x, local.z).length(), 0.15, "near its middle")


func test_miner_upgrades_apply_to_the_miners_a_player_places() -> void:
	var upgrades := Upgrades.new()
	upgrades.raise(DRILL)
	upgrades.raise(TANK)
	upgrades.raise(TANK)
	upgrades.raise(HOSE)
	var miner := MINER_SCENE.instantiate() as Miner
	miner.upgrades = upgrades
	var settings: MinerSettings = miner.settings
	assert_eq(miner.fill_rate(), settings.fill_rate * DRILL.levels[0].multiplier)
	assert_eq(miner.capacity(), settings.capacity * TANK.levels[1].multiplier)
	assert_eq(miner.hose_range(), settings.hose_range * HOSE.levels[0].multiplier)
	assert_eq(miner.transfer_rate(), settings.transfer_rate * HOSE.levels[0].multiplier)
	miner.free()
	var plain := MINER_SCENE.instantiate() as Miner
	assert_eq(plain.capacity(), plain.settings.capacity, "MK1 without upgrades")
	plain.free()


func test_placed_miner_gets_the_players_upgrades() -> void:
	var node := get_tree().get_nodes_in_group(OreNode.GROUP)[0] as OreNode
	var miner: Miner = node.place_miner(MINER_SCENE, _player.upgrades)
	assert_eq(miner.upgrades, _player.upgrades)
	_player.upgrades.raise(TANK)
	assert_eq(miner.capacity(), miner.settings.capacity * TANK.levels[0].multiplier)


func test_each_player_has_their_own_upgrades() -> void:
	var other := PLAYER_SCENE.instantiate() as Player
	_map.add_child(other)
	_player.upgrades.raise(ARMOR)
	assert_eq(other.upgrades.mk(ARMOR), 1)
	assert_eq(other.max_health(), other.settings.max_health)
	var defaults := PLAYER_SCENE.instantiate() as Player
	assert_true(defaults.upgrades == null or defaults.upgrades.levels.is_empty())
	defaults.free()


func test_every_upgrade_room_has_a_console() -> void:
	var menus: Dictionary[String, Array] = {
		"Weapons":
		[
			BLASTER.upgrade,
			BLASTER.magazine_upgrade,
			SHOTGUN.upgrade,
			SHOTGUN.magazine_upgrade,
			HAMMER.upgrade,
		],
		"Armor": [ARMOR],
		"Miners": [DRILL, TANK, HOSE],
	}
	for room: String in menus:
		var menu: UpgradeMenu = await _open_console(room)
		var expected: Array[Upgrade] = []
		expected.assign(menus[room])
		assert_eq(menu.listed(), expected, room)
		for upgrade: Upgrade in expected:
			assert_not_null(menu.get_buy_button(upgrade), "%s: %s" % [room, upgrade.display_name])
		WorldPanel.showing(menu).close()
		await wait_process_frames(1)


func test_console_buys_with_ore_from_the_hold() -> void:
	var menu: UpgradeMenu = await _open_console("Armor")
	var button: Button = menu.get_buy_button(ARMOR)
	assert_true(button.disabled, "the hold is empty")
	_ship.add_to_hold(CYAN, 1000.0)
	await wait_process_frames(1)
	assert_false(button.disabled)
	button.pressed.emit()
	assert_eq(_player.upgrades.mk(ARMOR), 2)
	assert_eq(_ship.hold[CYAN], 1000.0 - ARMOR.levels[0].cost[CYAN])
	await wait_process_frames(2)
	button = menu.get_buy_button(ARMOR)
	assert_true(button.disabled, "MK3 needs green and violet")
	_ship.add_to_hold(GREEN, 1000.0)
	_ship.add_to_hold(VIOLET, 1000.0)
	await wait_process_frames(1)
	button.pressed.emit()
	assert_eq(_player.upgrades.mk(ARMOR), 3)
	await wait_process_frames(2)
	button = menu.get_buy_button(ARMOR)
	assert_true(button.disabled, "at the highest level")
	assert_eq(button.text, "Max")


func test_console_locks_weapons_the_player_does_not_own() -> void:
	var menu: UpgradeMenu = await _open_console("Weapons")
	_ship.add_to_hold(CYAN, 1000.0)
	await wait_process_frames(1)
	assert_true(menu.get_buy_button(SHOTGUN.upgrade).disabled, "no shotgun yet")
	assert_false(menu.buy(SHOTGUN.upgrade))
	assert_false(menu.get_buy_button(BLASTER.upgrade).disabled)
	_player.arsenal.unlock(SHOTGUN)
	await wait_process_frames(2)
	assert_false(menu.get_buy_button(SHOTGUN.upgrade).disabled)
	assert_true(menu.buy(SHOTGUN.upgrade))
	assert_eq(_player.upgrades.mk(SHOTGUN.upgrade), 2)


func test_console_locks_while_a_mission_is_underway() -> void:
	var menu: UpgradeMenu = await _open_console("Miners")
	_ship.add_to_hold(CYAN, 1000.0)
	TEST_MAP.pick_mission(_map)
	_ship.ramp_button.use(_player)
	await wait_process_frames(2)
	assert_true(menu.is_locked())
	assert_true(menu.get_buy_button(DRILL).disabled)
	assert_false(menu.buy(DRILL))
	assert_eq(_player.upgrades.mk(DRILL), 1)
	assert_eq(_ship.hold[CYAN], 1000.0, "nothing paid")


func test_debug_overlay_fills_the_hold() -> void:
	var overlay: CanvasLayer = get_tree().root.get_node("DebugOverlay") as CanvasLayer
	overlay.call(&"fill_hold")
	for ore_type: OreType in [CYAN, GREEN, VIOLET] as Array[OreType]:
		var stored: float = _ship.hold.get(ore_type, 0.0)
		assert_gt(stored, 0.0)


func _open_console(room: String) -> UpgradeMenu:
	var terminal := _ship.get_node("Rooms/Lower/%s/UpgradeTerminal" % room) as Terminal
	_player.global_position = _ship.to_global(AT_CONSOLES[room])
	_player.reset_physics_interpolation()
	await wait_physics_frames(5)
	assert_eq(_player.interact(), terminal, room)
	var menu := terminal.panel.content as UpgradeMenu
	await wait_process_frames(2)
	assert_eq(menu.player, _player)
	assert_eq(menu.ship, _ship)
	return menu
