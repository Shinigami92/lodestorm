extends GutTest
## Weapons composed of Resources: every weapon's data, its parts, the draw after switching and
## building a weapon from its blueprint at the workbench.

const TEST_MAP := preload("res://tests/support/test_map.gd")
const ALL_WEAPONS: Arsenal = preload("res://game/weapons/all_weapons.tres")
const HARL: WeaponType = preload("res://game/weapons/types/harl/harl.tres")
const BRASK: WeaponType = preload("res://game/weapons/types/brask/brask.tres")
const DRAY: WeaponType = preload("res://game/weapons/types/dray/dray.tres")

var _map: Node3D
var _player: Player
var _ship: Ship


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	_ship = _map.get_node("Ship") as Ship
	await wait_physics_frames(2)


func after_each() -> void:
	Input.action_release(&"attack")


func test_every_weapon_is_composed_and_named() -> void:
	var letters: Array[String] = []
	for weapon_type: WeaponType in ALL_WEAPONS.weapons:
		var label: String = weapon_type.display_name
		assert_does_not_have(letters, label.left(1), "%s: its own first letter" % label)
		letters.append(label.left(1))
		assert_ne(weapon_type.class_word, "", label)
		assert_not_null(weapon_type.delivery, label)
		assert_false(weapon_type.effects.is_empty(), label)
		assert_gt(weapon_type.draw_time, 0.0, label)
		var stats: Array[WeaponPart.Stat] = []
		for part: WeaponPart in weapon_type.parts:
			assert_does_not_have(stats, part.stat, "%s: one part per value" % label)
			stats.append(part.stat)
		var weapon: Weapon = weapon_type.create()
		assert_eq(weapon.type, weapon_type)
		assert_eq(weapon.ammo == null, weapon_type.feed == null, "%s: ammo when fed" % label)
		if weapon.ammo:
			assert_not_null(weapon.get_gauge(), label)
		if not weapon_type.is_melee():
			assert_not_null(weapon.get_muzzle(), label)
		weapon.free()


func test_every_part_shows_its_pips_on_the_weapon() -> void:
	for weapon_type: WeaponType in ALL_WEAPONS.weapons:
		var weapon: Weapon = weapon_type.create()
		var upgrades := Upgrades.new()
		upgrades.raise(weapon_type.parts[-1])
		weapon.apply_upgrades(upgrades)
		for part: WeaponPart in weapon_type.parts:
			var pips: MkPips = weapon.get_pips(part)
			var label: String = "%s %s" % [weapon_type.display_name, part.display_name]
			assert_not_null(pips, label)
			if pips:
				assert_eq(pips.get_child_count(), part.max_mk(), label)
				assert_eq(pips.lit_count(), 2 if part == weapon_type.parts[-1] else 1, label)
		weapon.free()


func test_harl_fire_rate_part_raises_its_attack_rate() -> void:
	assert_eq(_player.get_weapon_type(), HARL)
	var part: WeaponPart = HARL.get_part(WeaponPart.Stat.RATE)
	assert_eq(_player.weapon.attack_rate(), HARL.attack_rate)
	_player.upgrades.raise(part)
	assert_almost_eq(_player.weapon.attack_rate(), HARL.attack_rate * part.multiplier(2), 0.001)


func test_switching_draws_the_weapon_before_it_attacks() -> void:
	_go_outside()
	await wait_physics_frames(2)
	assert_true(_player.weapon_allowed, "outside the ship")
	assert_true(_player.switch_weapon())
	var dray: Weapon = _player.weapon
	assert_eq(dray.type, DRAY)
	assert_false(dray.is_drawn())
	assert_lt(dray.rotation.x, -0.5, "swings up from the hip")
	watch_signals(dray)
	Input.action_press(&"attack")
	await wait_physics_frames(roundi(DRAY.draw_time * 0.5 * Engine.physics_ticks_per_second))
	assert_signal_not_emitted(dray, "swung", "not drawn yet")
	await wait_physics_frames(roundi(DRAY.draw_time * 0.5 * Engine.physics_ticks_per_second) + 2)
	assert_true(dray.is_drawn())
	assert_signal_emitted(dray, "swung")
	assert_almost_eq(dray.rotation.x, 0.0, 0.01)


func test_switching_cancels_a_reload() -> void:
	_go_outside()
	await wait_physics_frames(2)
	var ammo := _player.get_ammo() as MagazineAmmo
	ammo.rounds = 1
	assert_true(_player.reload())
	_player.switch_weapon()
	_player.switch_weapon()
	ammo = _player.get_ammo() as MagazineAmmo
	assert_false(ammo.reloading)
	assert_eq(ammo.rounds, 0, "the magazine thrown away stays empty")


func test_building_a_weapon_takes_its_blueprint_and_its_ore() -> void:
	var station := await _use_weapon_station()
	station.lay_on_bench(BRASK)
	var build: StationPart = station.get_build_part()
	assert_true(build.visible, "not owned yet")
	assert_eq(station.selected, build)
	var card := station.card_menu as UpgradeCard
	assert_eq(card.weapon_type, BRASK)
	assert_true(card.get_buy_button().disabled, "no blueprint")
	assert_false(station.build(BRASK))
	_player.arsenal.learn(BRASK)
	station.refresh()
	assert_true(card.get_buy_button().disabled, "nothing in the hold")
	for ore_type: OreType in BRASK.build_cost:
		_player.hold.add(ore_type, BRASK.build_cost[ore_type] + 5.0)
	station.refresh()
	assert_false(card.get_buy_button().disabled)
	assert_true(card.press_primary())
	assert_true(_player.arsenal.owns(BRASK))
	assert_false(_player.arsenal.has_blueprint(BRASK), "the blueprint is used up")
	for ore_type: OreType in BRASK.build_cost:
		assert_eq(_player.hold.amount(ore_type), 5.0, "paid from the hold")
	assert_false(build.visible)
	assert_eq(station.selected.item, BRASK.parts[0], "on to its upgrades")
	assert_false(station.build(BRASK), "only once")


func test_blueprints_only_for_weapons_not_owned() -> void:
	assert_false(_player.arsenal.learn(HARL), "owned already")
	assert_true(_player.arsenal.learn(BRASK))
	assert_false(_player.arsenal.learn(BRASK), "known already")
	assert_true(_player.arsenal.has_blueprint(BRASK))
	var data: Dictionary = SaveGame.player_data(_player)
	var blueprints: Array = data["blueprints"]
	assert_eq(blueprints, [ResourceUID.path_to_uid(BRASK.resource_path)])


func test_debug_overlay_gives_every_blueprint() -> void:
	var overlay: CanvasLayer = get_tree().root.get_node("DebugOverlay") as CanvasLayer
	overlay.call(&"_give_blueprints")
	for weapon_type: WeaponType in ALL_WEAPONS.weapons:
		assert_true(
			_player.arsenal.owns(weapon_type) or _player.arsenal.has_blueprint(weapon_type),
			weapon_type.display_name
		)
	assert_false(_player.arsenal.owns(BRASK), "a blueprint, not built")


func _go_outside() -> void:
	# Weapons are holstered inside the ship, where the player starts.
	_player.global_position = _ship.to_global(Vector3(22.0, 0.0, 0.0))
	_player.reset_physics_interpolation()


func _use_weapon_station() -> WeaponStation:
	var station := _ship.get_node("Rooms/Lower/Weapons/UpgradeStation") as WeaponStation
	var use: Interactable = station.use_point
	_player.global_position = station.user_spot.global_position
	_player.reset_physics_interpolation()
	await wait_physics_frames(5)
	assert_eq(_player.interact(), use)
	await wait_process_frames(1)
	return station
