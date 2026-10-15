extends GutTest
## Every 3D menu fits its screen or card in every language, and its text reads from the camera.

const TEST_MAP := preload("res://tests/support/test_map.gd")
const CARD_SCENE: PackedScene = preload("res://scenes/ui/upgrade_card.tscn")
const LOADOUT_CARD_SCENE: PackedScene = preload("res://scenes/ui/loadout_card.tscn")
const SKILL_CARD_SCENE: PackedScene = preload("res://scenes/ui/skill_card.tscn")
const SKILL_TREE: SkillTree = preload("res://scenes/skills/skill_tree.tres")
const ALL_WEAPONS: Arsenal = preload("res://scenes/weapons/all_weapons.tres")
const UPGRADES: Array[Upgrade] = [
	preload("res://scenes/upgrades/armor.tres"),
	preload("res://scenes/upgrades/miner_drill.tres"),
	preload("res://scenes/upgrades/miner_tank.tres"),
	preload("res://scenes/upgrades/miner_hose.tres"),
]
const TERMINALS: PackedStringArray = [
	"Rooms/Upper/Cabin1/Terminal",
]
## Body text is at least this part of the view's height (see GAME_DESIGN.md, UI).
const MIN_TEXT_HEIGHT: float = 0.02
const STATIONS: PackedStringArray = [
	"Rooms/Lower/Weapons/UpgradeStation",
	"Rooms/Lower/Armor/UpgradeStation",
	"Rooms/Lower/Miners/UpgradeStation",
	"Rooms/Lower/Skills/SkillGraph",
	"Rooms/Lower/Armory/Locker1",
	"Rooms/Upper/Bridge/Navigator",
	"Rooms/Upper/Cockpit/FlightConsole",
	"Rooms/Upper/Cabin1/BedStation",
]

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
	TranslationServer.set_locale("en")


func test_every_upgrade_card_fits_in_every_language() -> void:
	var upgrades: Array[Upgrade] = UPGRADES.duplicate()
	for weapon_type: WeaponType in ALL_WEAPONS.weapons:
		upgrades.append_array(weapon_type.get_upgrades())
	var hold: Dictionary[OreType, float] = {}
	for upgrade: Upgrade in upgrades:
		for level: UpgradeLevel in upgrade.levels:
			for ore_type: OreType in level.cost:
				hold[ore_type] = 99999.0
	for path: String in STATIONS:
		if not _ship.get_node(path) is UpgradeStation:
			continue
		var panel: WorldPanel = (_ship.get_node(path) as Station).card
		var layout := Vector2(panel.size * panel.pixels_per_meter)
		var viewport := SubViewport.new()
		viewport.size = Vector2i(layout)
		add_child_autofree(viewport)
		var card := CARD_SCENE.instantiate() as UpgradeCard
		viewport.add_child(card)
		for locale: String in SettingsMenu.languages():
			TranslationServer.set_locale(locale)
			for upgrade: Upgrade in upgrades:
				for mk: int in range(1, upgrade.max_mk() + 1):
					var label: String = (
						"%s %s MK%d on %s" % [locale, upgrade.display_name, mk, path]
					)
					# The tallest it gets (locked by a mission, every ore short), and with its
					# buttons enabled (their style is wider than the disabled one).
					card.show_upgrade(upgrade, mk, hold, mk == 1, true, false)
					await wait_process_frames(1)
					_assert_fits(card, layout, label)
					card.show_upgrade(upgrade, mk, hold, true, false, true)
					await wait_process_frames(1)
					_assert_fits(card, layout, label + " enabled")
		viewport.queue_free()


func test_every_skill_card_fits_in_every_language() -> void:
	var panel: WorldPanel = (_ship.get_node("Rooms/Lower/Skills/SkillGraph") as Station).card
	var layout := Vector2(panel.size * panel.pixels_per_meter)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(layout)
	add_child_autofree(viewport)
	var card := SKILL_CARD_SCENE.instantiate() as SkillCard
	viewport.add_child(card)
	var hold: Dictionary[OreType, float] = {}
	for skill: Skill in SKILL_TREE.get_skills():
		for rank: SkillRank in skill.ranks:
			for ore_type: OreType in rank.cost:
				hold[ore_type] = 99999.0
	for locale: String in SettingsMenu.languages():
		TranslationServer.set_locale(locale)
		for skill: Skill in SKILL_TREE.get_skills():
			for rank: int in range(0, skill.max_rank() + 1):
				var label: String = "%s %s rank %d" % [locale, skill.display_name, rank]
				# The tallest it gets (not open yet, locked by a mission), and with its buttons
				# enabled (their style is wider than the disabled one).
				card.show_skill(skill, rank, hold, skill.requires == null, true, false)
				await wait_process_frames(1)
				_assert_fits(card, layout, label)
				card.show_skill(skill, rank, hold, true, false, true)
				await wait_process_frames(1)
				_assert_fits(card, layout, label + " enabled")


func test_every_locker_card_fits_in_every_language() -> void:
	var panel: WorldPanel = (_ship.get_node("Rooms/Lower/Armory/Locker1") as Station).card
	var layout := Vector2(panel.size * panel.pixels_per_meter)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(layout)
	add_child_autofree(viewport)
	var card := LOADOUT_CARD_SCENE.instantiate() as LoadoutCard
	viewport.add_child(card)
	for locale: String in SettingsMenu.languages():
		TranslationServer.set_locale(locale)
		for weapon_type: WeaponType in ALL_WEAPONS.weapons:
			# Locked by a mission (buttons disabled) and usable (enabled buttons are wider), with
			# either slot selected (framed amber).
			for locked: bool in [true, false]:
				for selected_slot: int in 2:
					card.show_weapon(weapon_type, Upgrades.new(), true, locked, 0, selected_slot)
					await wait_process_frames(1)
					var label: String = (
						"%s %s locked %s slot %d"
						% [locale, weapon_type.display_name, locked, selected_slot + 1]
					)
					_assert_fits(card, layout, label)


func test_navigator_and_flight_cards_fit_in_every_language() -> void:
	var navigator := _ship.get_node("Rooms/Upper/Bridge/Navigator") as NavigatorStation
	var console := _ship.get_node("Rooms/Upper/Cockpit/FlightConsole") as FlightStation
	var mission := _map.get_node("Mission") as Mission
	for locale: String in SettingsMenu.languages():
		TranslationServer.set_locale(locale)
		navigator.open(_player)
		await wait_process_frames(1)
		for body: CelestialBody in mission.settings.system.bodies:
			navigator.show_system()
			navigator.select(navigator.get_part(body))
			await wait_process_frames(1)
			_assert_card_fits(navigator, "%s %s" % [locale, body.display_name])
			navigator.show_body(body)
			for region: Region in body.regions:
				navigator.select(navigator.get_part(region))
				await wait_process_frames(1)
				_assert_card_fits(navigator, "%s %s" % [locale, region.display_name])
				navigator.show_region(region)
				await wait_process_frames(1)
				_assert_card_fits(navigator, "%s %s landing site" % [locale, region.display_name])
				navigator.show_body(body)
		navigator.close()
		console.open(_player)
		await wait_process_frames(1)
		_assert_card_fits(console, "%s no destination" % locale)
		mission.choose(mission.offers[0])
		await wait_process_frames(1)
		_assert_card_fits(console, "%s destination" % locale)
		console.close()


func test_bed_card_fits_in_every_language() -> void:
	var bed := _ship.get_node("Rooms/Upper/Cabin1/BedStation") as BedStation
	var panel: WorldPanel = bed.card
	var card := bed.card_menu as BedCard
	for locale: String in SettingsMenu.languages():
		TranslationServer.set_locale(locale)
		for loses_run: bool in [false, true]:
			card.visible = true
			card.show_state(loses_run)
			await wait_process_frames(1)
			var layout := Vector2(panel.size * panel.pixels_per_meter)
			_assert_fits(card, layout, "%s bed, run lost %s" % [locale, loses_run])


func test_every_terminal_fits_in_every_language() -> void:
	for locale: String in SettingsMenu.languages():
		TranslationServer.set_locale(locale)
		for path: String in TERMINALS:
			var terminal := _ship.get_node(path) as Terminal
			terminal.panel.open(_player)
			await wait_process_frames(2)
			var layout := Vector2(terminal.panel.size * terminal.panel.pixels_per_meter)
			_assert_fits(terminal.panel.content, layout, "%s %s" % [locale, path])
			terminal.panel.close()


func test_text_reads_from_the_camera() -> void:
	var theme: Theme = load("res://assets/ui/terminal_theme.tres")
	var font_size: float = theme.default_font_size
	for path: String in TERMINALS:
		var terminal := _ship.get_node(path) as Terminal
		var panel: WorldPanel = terminal.panel
		var text_height: float = font_size / panel.pixels_per_meter * panel.global_basis.y.length()
		assert_gte(text_height / panel.view_height, MIN_TEXT_HEIGHT, path)
	for path: String in STATIONS:
		var station := _ship.get_node(path) as Station
		var card: WorldPanel = station.card
		var text_height: float = font_size / card.pixels_per_meter * card.global_basis.y.length()
		assert_gte(text_height / station.view_height, MIN_TEXT_HEIGHT, path)


func _assert_card_fits(station: Station, label: String) -> void:
	var panel: WorldPanel = station.card
	_assert_fits(station.card_menu, Vector2(panel.size * panel.pixels_per_meter), label)


func _assert_fits(content: Control, layout: Vector2, label: String) -> void:
	var needed: Vector2 = content.get_combined_minimum_size()
	assert_lte(needed.x, layout.x + 0.5, "%s: %s wide" % [label, needed.x])
	assert_lte(needed.y, layout.y + 0.5, "%s: %s high" % [label, needed.y])
