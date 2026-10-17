extends GutTest

const TEST_MAP := preload("res://tests/support/test_map.gd")
const PLAYER_SCENE: PackedScene = preload("res://game/player/player.tscn")
const MINER_SCENE: PackedScene = preload("res://game/mining/miner.tscn")
const ALL_WEAPONS: Arsenal = preload("res://game/weapons/all_weapons.tres")
const BLASTER: WeaponType = preload("res://game/weapons/types/blaster.tres")
const SHOTGUN: WeaponType = preload("res://game/weapons/types/shotgun.tres")
const HAMMER: WeaponType = preload("res://game/weapons/types/hammer.tres")
const ARMOR: Upgrade = preload("res://game/progression/upgrades/armor.tres")
const DRILL: Upgrade = preload("res://game/progression/upgrades/miner_drill.tres")
const TANK: Upgrade = preload("res://game/progression/upgrades/miner_tank.tres")
const HOSE: Upgrade = preload("res://game/progression/upgrades/miner_hose.tres")
const KYRITE: OreType = preload("res://game/ores/types/ore_kyrite.tres")
const OLVANE: OreType = preload("res://game/ores/types/ore_olvane.tres")
const VYREL: OreType = preload("res://game/ores/types/ore_vyrel.tres")
const MERIDINE: OreType = preload("res://game/ores/types/ore_meridine.tres")

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
		assert_eq(upgrade.max_mk(), 8, "MK1 to MK8, one more per planet")
		var previous: float = 1.0
		for level: UpgradeLevel in upgrade.levels:
			assert_gt(level.multiplier, previous)
			previous = level.multiplier
		assert_true(upgrade.cost_of(1).is_empty(), "MK1 is free")
		assert_true(upgrade.cost_of(upgrade.max_mk() + 1).is_empty())
		for mk: int in range(2, upgrade.max_mk() + 1):
			var cost: Dictionary[OreType, int] = upgrade.cost_of(mk)
			assert_eq(cost.size(), 2 if mk == 2 else 3, "%s MK%d" % [upgrade.display_name, mk])
			for ore_type: OreType in cost:
				assert_gt(cost[ore_type], 0)
				assert_eq(cost[ore_type] % 10, 0, "rounded to tens")


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
	assert_eq(upgrades.next_cost(ARMOR), ARMOR.cost_of(3))
	assert_true(upgrades.raise(ARMOR))
	assert_eq(upgrades.multiplier(ARMOR), ARMOR.levels[1].multiplier)
	while upgrades.raise(ARMOR):
		pass
	assert_eq(upgrades.mk(ARMOR), 8, "MK8 is the highest")
	assert_eq(upgrades.multiplier(ARMOR), ARMOR.levels[-1].multiplier)
	assert_null(upgrades.next_level(ARMOR))
	assert_true(upgrades.next_cost(ARMOR).is_empty())


func test_hold_pays_only_what_it_has() -> void:
	var cost: Dictionary[OreType, int] = {KYRITE: 200, OLVANE: 100}
	assert_false(_ship.can_pay(cost))
	_ship.add_to_hold(KYRITE, 300.0)
	assert_false(_ship.can_pay(cost), "no olvane yet")
	assert_false(_ship.pay(cost))
	assert_eq(_ship.hold[KYRITE], 300.0, "nothing taken")
	_ship.add_to_hold(OLVANE, 100.0)
	assert_true(_ship.pay(cost))
	assert_eq(_ship.hold[KYRITE], 100.0)
	assert_eq(_ship.hold[OLVANE], 0.0)
	var hold := _ship.get_node("OreHold") as OreHold
	assert_eq(hold.get_tank(OLVANE).fill_level(), 0.0, "the tanks show what's left")
	assert_gt(hold.get_tank(KYRITE).fill_level(), 0.0)
	assert_true(hold.get_tank(OLVANE).found, "an emptied tank stays known")


func test_weapon_upgrade_raises_its_damage_and_lights_its_pips() -> void:
	assert_eq(_player.get_weapon_type(), BLASTER)
	assert_eq(_player.weapon.damage_multiplier, 1.0)
	var pips := _player.weapon.get_node("MkPips") as MkPips
	assert_eq(pips.lit_count(), 1)
	assert_eq(pips.max_mk, 8)
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
			assert_eq(pips.get_child_count(), weapon_type.upgrade.max_mk())
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
	assert_eq(_player.get_armor_pips().max_mk, 8)
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


func test_every_upgrade_room_has_a_station() -> void:
	var stations: Dictionary[String, Array] = {
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
	for room: String in stations:
		var station: UpgradeStation = await _open_station(room)
		var expected: Array[Upgrade] = []
		expected.assign(stations[room])
		assert_eq(station.get_upgrades(), expected, room)
		assert_not_null(station.selected, "%s selects its first part" % room)
		station.close()
		await wait_process_frames(1)


func test_station_buys_with_ore_from_the_hold() -> void:
	var station: UpgradeStation = await _open_station("Armor")
	var card := station.card_menu as UpgradeCard
	assert_eq(card.upgrade, ARMOR)
	var button: Button = card.get_buy_button()
	assert_true(button.disabled, "the hold is empty")
	_ship.add_to_hold(KYRITE, 1000.0)
	_ship.add_to_hold(VYREL, 1000.0)
	await wait_process_frames(1)
	assert_false(button.disabled)
	button.pressed.emit()
	assert_eq(_player.upgrades.mk(ARMOR), 2)
	assert_eq(_ship.hold[KYRITE], 1000.0 - ARMOR.cost_of(2)[KYRITE])
	await wait_process_frames(1)
	assert_true(button.disabled, "MK3 needs olvane and meridine")
	_ship.add_to_hold(OLVANE, 1000.0)
	_ship.add_to_hold(MERIDINE, 1000.0)
	await wait_process_frames(1)
	assert_true(card.press_primary(), "interact buys too")
	assert_eq(_player.upgrades.mk(ARMOR), 3)
	await wait_process_frames(1)
	assert_true(button.disabled, "MK4 waits for the next planet")
	assert_true(card.get_status().visible)
	assert_string_contains(card.get_status().text, "heat shield MK2")


func test_station_sells_higher_levels_once_the_ship_reaches_further() -> void:
	var station: UpgradeStation = await _open_station("Armor")
	_player.upgrades.levels[ARMOR] = 3
	for ore_type: OreType in OreCatalog.all().ores:
		_ship.add_to_hold(ore_type, 10000.0)
	await wait_process_frames(1)
	assert_false(station.can_buy(ARMOR), "MK3 is the highest with the bare core")
	assert_false(station.buy(ARMOR))
	_ship.heat_shield.install_next()
	assert_eq(station.upgrade_cap(), 4)
	assert_true(station.buy(ARMOR))
	assert_eq(_player.upgrades.mk(ARMOR), 4)
	assert_false(station.can_buy(ARMOR))
	while _ship.heat_shield.install_next():
		pass
	while station.buy(ARMOR):
		pass
	assert_eq(_player.upgrades.mk(ARMOR), 8)
	var card := station.card_menu as UpgradeCard
	await wait_process_frames(1)
	assert_eq(card.get_buy_button().text, "Max")
	assert_false(card.get_status().visible)


func test_station_locks_weapons_the_player_does_not_own() -> void:
	var station := await _open_station("Weapons") as WeaponStation
	_ship.add_to_hold(KYRITE, 1000.0)
	_ship.add_to_hold(VYREL, 1000.0)
	await wait_process_frames(1)
	assert_false(station.can_buy(SHOTGUN.upgrade), "no shotgun yet")
	assert_false(station.buy(SHOTGUN.upgrade))
	assert_true(station.can_buy(BLASTER.upgrade))
	_player.arsenal.unlock(SHOTGUN)
	assert_true(station.buy(SHOTGUN.upgrade))
	assert_eq(_player.upgrades.mk(SHOTGUN.upgrade), 2)


func test_station_locks_while_a_mission_is_underway() -> void:
	var station: UpgradeStation = await _open_station("Miners")
	_ship.add_to_hold(KYRITE, 1000.0)
	TEST_MAP.pick_mission(_map)
	_ship.ramp_button.use(_player)
	await wait_process_frames(2)
	assert_true(station.is_locked())
	assert_false(station.can_buy(DRILL))
	assert_false(station.buy(DRILL))
	assert_eq(_player.upgrades.mk(DRILL), 1)
	assert_eq(_ship.hold[KYRITE], 1000.0, "nothing paid")
	assert_true((station.card_menu as UpgradeCard).get_buy_button().disabled)


func test_debug_overlay_fills_the_hold() -> void:
	var overlay: CanvasLayer = get_tree().root.get_node("DebugOverlay") as CanvasLayer
	overlay.call(&"fill_hold")
	for ore_type: OreType in [KYRITE, OLVANE, VYREL] as Array[OreType]:
		var stored: float = _ship.hold.get(ore_type, 0.0)
		assert_gt(stored, 0.0)


func _open_station(room: String) -> UpgradeStation:
	var station := _ship.get_node("Rooms/Lower/%s/UpgradeStation" % room) as UpgradeStation
	var use: Interactable = station.use_point
	_player.global_position = use.global_position + use.global_basis.z * 0.3
	_player.reset_physics_interpolation()
	await wait_physics_frames(5)
	assert_eq(_player.interact(), station.use_point, room)
	assert_eq(station.user, _player)
	await wait_process_frames(2)
	assert_eq(station.ship, _ship)
	return station
