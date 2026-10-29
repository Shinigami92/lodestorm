extends "res://tests/support/menu_fit.gd"
## Every station's card and terminal fits in every language, and their text reads from the camera
## (the crew's and the colonists' words: `test_speech_fit.gd`).

const CARD_SCENE: PackedScene = preload("res://game/stations/upgrade/upgrade_card.tscn")
const LOADOUT_CARD_SCENE: PackedScene = preload("res://game/stations/loadout/loadout_card.tscn")
const SKILL_CARD_SCENE: PackedScene = preload("res://game/stations/skill_graph/skill_card.tscn")
const SKILL_TREE: SkillTree = preload("res://game/progression/skills/tree/skill_tree.tres")
const ALL_WEAPONS: Arsenal = preload("res://game/weapons/all_weapons.tres")
const FULL_HOLD := preload("res://tests/support/full_hold.gd")
const UPGRADES: Array[Upgrade] = [
	preload("res://game/progression/upgrades/armor.tres"),
	preload("res://game/progression/upgrades/miner_drill.tres"),
	preload("res://game/progression/upgrades/miner_tank.tres"),
	preload("res://game/progression/upgrades/miner_hose.tres"),
]
const TERMINALS: PackedStringArray = [
	"Rooms/Upper/Cabin1/Terminal",
]
## The most ores a place lists on the navigator and flight cards.
const MAX_ORES_SHOWN: int = 6
const STATIONS: PackedStringArray = [
	"Rooms/Lower/Weapons/UpgradeStation",
	"Rooms/Lower/Armor/UpgradeStation",
	"Rooms/Lower/Miners/MinerBay",
	"Rooms/Lower/Skills/SkillGraph",
	"Rooms/Lower/Armory/Locker1",
	"Rooms/Upper/Bridge/Navigator",
	"Rooms/Upper/Cockpit/FlightConsole",
	"Rooms/Upper/Cabin1/BedStation",
	"Rooms/Lower/MedicalBay/MedBed1",
	"Rooms/Lower/Armory/Quartermaster",
	"Rooms/Lower/EngineRoom/DriveCore",
]


func test_every_upgrade_card_fits_in_every_language() -> void:
	var upgrades: Array[Upgrade] = UPGRADES.duplicate()
	for weapon_type: WeaponType in ALL_WEAPONS.weapons:
		upgrades.append_array(weapon_type.get_upgrades())
	var hold: Dictionary[ItemType, float] = {}
	for upgrade: Upgrade in upgrades:
		for mk: int in range(2, upgrade.max_mk() + 1):
			for item: ItemType in upgrade.cost_of(mk):
				hold[item] = 99999.0
	_stop_map()
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
		for locale: String in SettingsList.languages():
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
					# The next level waits for the next planet.
					card.show_upgrade(upgrade, mk, hold, true, false, false, mk)
					await wait_process_frames(1)
					_assert_fits(card, layout, label + " at the ship's reach")
			# A weapon selected on the workbench's rack.
			for weapon_type: WeaponType in ALL_WEAPONS.weapons:
				for owned: bool in [true, false]:
					card.show_pick(weapon_type, owned)
					await wait_process_frames(1)
					_assert_fits(
						card, layout, "%s %s on the rack" % [locale, weapon_type.display_name]
					)
		viewport.queue_free()


func test_every_heat_shield_card_fits_in_every_language() -> void:
	var core := _ship.get_node("Rooms/Lower/EngineRoom/DriveCore") as HeatShieldStation
	var card := core.card_menu as HeatShieldCard
	var panel: WorldPanel = core.card
	var layout := Vector2(panel.size * panel.pixels_per_meter)
	var shield := HeatShield.new()
	var hold: Dictionary[ItemType, float] = {}
	for plate: ShieldPlate in shield.plates:
		for ore_type: OreType in plate.cost:
			hold[ore_type] = 99999.0
	# The longest list of bodies a plate opens.
	var opens: PackedStringArray = []
	for level: int in range(2, shield.max_mk() + 1):
		if core.opened_by(level).size() > opens.size():
			opens = core.opened_by(level)
	for locale: String in SettingsList.languages():
		TranslationServer.set_locale(locale)
		var names: PackedStringArray = []
		for body_name: String in opens:
			names.append(tr(body_name))
		for mk: int in range(1, shield.max_mk() + 1):
			shield.restore(mk, false, {})
			for level: int in range(2, shield.max_mk() + 1):
				var label: String = "%s plate MK%d at MK%d" % [locale, level, mk]
				card.visible = true
				# The tallest it gets (locked by a mission, every ore short) and the widest
				# buttons (enabled, the project's line shown).
				card.show_plate(shield, level, names, {}, true, true)
				await wait_process_frames(1)
				_assert_fits(card, layout, label)
				card.show_plate(shield, level, names, {}, false, false)
				await wait_process_frames(1)
				_assert_fits(card, layout, label + " guest")
				card.show_plate(shield, level, names, hold, false, true)
				await wait_process_frames(1)
				_assert_fits(card, layout, label + " enabled")
				shield.project = level == mk + 1
				card.show_plate(shield, level, names, hold, false, true)
				await wait_process_frames(1)
				_assert_fits(card, layout, label + " project")
				shield.project = false


func test_miner_bay_cards_fit_in_every_language() -> void:
	var bay := _ship.get_node("Rooms/Lower/Miners/MinerBay") as MinerBayStation
	var card := bay.card_menu as MinerCard
	var layout := Vector2(bay.card.size * bay.card.pixels_per_meter)
	var hold: Dictionary[ItemType, float] = {}
	for item: ItemType in bay.settings.build_cost:
		hold[item] = 99999.0
	var miner := CraftedMiner.new(6)
	miner.upgrades.start(CraftedMiner.PARTS[0], FULL_HOLD.fill(), 0.0)
	var building := CraftedMiner.new(6, TimedJob.new(1, 0.0, 21600.0))
	# The longest place a miner can be lost at.
	var longest: String = ""
	for body: CelestialBody in (_map.get_node("Voyage") as Voyage).settings.system.bodies:
		for region: Region in body.regions:
			var place: String = "%s, %s" % [body.display_name, region.display_name]
			if place.length() > longest.length():
				longest = place
	for locale: String in SettingsList.languages():
		TranslationServer.set_locale(locale)
		for along: bool in [true, false]:
			miner.going_along = along
			for locked: bool in [true, false]:
				card.show_miner(miner, 3, 6, locked, 1.0, true)
				await wait_process_frames(1)
				_assert_fits(card, layout, "%s miner along %s locked %s" % [locale, along, locked])
		card.show_cradle(6, bay.settings.build_cost, {}, 21600.0, longest, false, false)
		await wait_process_frames(1)
		_assert_fits(card, layout, "%s lost cradle" % locale)
		card.show_cradle(6, bay.settings.build_cost, hold, 21600.0, longest, true, true)
		await wait_process_frames(1)
		_assert_fits(card, layout, "%s cradle locked" % locale)
		for armed: bool in [true, false]:
			card.show_building(building, 1.0, true, armed, false)
			await wait_process_frames(1)
			_assert_fits(card, layout, "%s building armed %s" % [locale, armed])


func test_every_skill_card_fits_in_every_language() -> void:
	var panel: WorldPanel = (_ship.get_node("Rooms/Lower/Skills/SkillGraph") as Station).card
	var layout := Vector2(panel.size * panel.pixels_per_meter)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(layout)
	add_child_autofree(viewport)
	var card := SKILL_CARD_SCENE.instantiate() as SkillCard
	viewport.add_child(card)
	var hold: Dictionary[ItemType, float] = {}
	for skill: Skill in SKILL_TREE.get_skills():
		for rank: SkillRank in skill.ranks:
			for item: ItemType in rank.cost:
				hold[item] = 99999.0
	_stop_map()
	for locale: String in SettingsList.languages():
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
	_stop_map()
	for locale: String in SettingsList.languages():
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
	var voyage := _map.get_node("Voyage") as Voyage
	for locale: String in SettingsList.languages():
		TranslationServer.set_locale(locale)
		navigator.open(_player)
		await wait_process_frames(1)
		for body: CelestialBody in voyage.settings.system.bodies:
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
		voyage.choose(voyage.offers[0])
		await wait_process_frames(1)
		_assert_card_fits(console, "%s destination" % locale)
		console.close()


func test_navigator_and_flight_cards_fit_the_most_ores() -> void:
	var navigator := _ship.get_node("Rooms/Upper/Bridge/Navigator") as NavigatorStation
	var console := _ship.get_node("Rooms/Upper/Cockpit/FlightConsole") as FlightStation
	var voyage := _map.get_node("Voyage") as Voyage
	var body: CelestialBody = voyage.settings.system.bodies[0]
	for candidate: CelestialBody in voyage.settings.system.bodies:
		if not candidate.regions.is_empty():
			body = candidate
			break
	for locale: String in SettingsList.languages():
		TranslationServer.set_locale(locale)
		# The most ores a place lists, with the longest names in this language.
		var ores: Array[OreType] = OreCatalog.all().ores.duplicate()
		ores.sort_custom(
			func(a: OreType, b: OreType) -> bool:
				return a.get_display_name().length() > b.get_display_name().length()
		)
		ores.resize(MAX_ORES_SHOWN)
		navigator.open(_player)
		navigator.show_body(body)
		navigator.select(navigator.get_part(body.regions[0]))
		(navigator.card_menu as NavigatorCard)._show_ores(ores)
		await wait_process_frames(1)
		_assert_card_fits(navigator, "%s region with %d ores" % [locale, ores.size()])
		navigator.close()
		voyage.choose(voyage.offers[0])
		console.open(_player)
		(console.card_menu as FlightCard)._show_ores(ores)
		await wait_process_frames(1)
		_assert_card_fits(console, "%s destination with %d ores" % [locale, ores.size()])
		console.close()


func test_bed_card_fits_in_every_language() -> void:
	var bed := _ship.get_node("Rooms/Upper/Cabin1/BedStation") as BedStation
	var panel: WorldPanel = bed.card
	var card := bed.card_menu as BedCard
	for locale: String in SettingsList.languages():
		TranslationServer.set_locale(locale)
		for loses_run: bool in [false, true]:
			card.visible = true
			card.show_state(loses_run)
			await wait_process_frames(1)
			var layout := Vector2(panel.size * panel.pixels_per_meter)
			_assert_fits(card, layout, "%s bed, run lost %s" % [locale, loses_run])


func test_med_bed_card_fits_in_every_language() -> void:
	var bed := _ship.get_node("Rooms/Lower/MedicalBay/MedBed1") as MedBedStation
	var panel: WorldPanel = bed.card
	var card := bed.card_menu as MedBedCard
	for locale: String in SettingsList.languages():
		TranslationServer.set_locale(locale)
		# Wider than any suit's health gets (MK8 armor and every health skill: under 1000).
		for health: float in [9999.0]:
			card.visible = true
			card.show_health(health * 0.5, health)
			await wait_process_frames(1)
			var layout := Vector2(panel.size * panel.pixels_per_meter)
			_assert_fits(card, layout, "%s med bed, healing %d" % [locale, health])
			card.show_health(health, health)
			await wait_process_frames(1)
			_assert_fits(card, layout, "%s med bed, healed %d" % [locale, health])


func test_every_terminal_fits_in_every_language() -> void:
	for locale: String in SettingsList.languages():
		TranslationServer.set_locale(locale)
		for path: String in TERMINALS:
			var terminal := _ship.get_node(path) as Terminal
			terminal.panel.open(_player)
			await wait_process_frames(2)
			var layout := Vector2(terminal.panel.size * terminal.panel.pixels_per_meter)
			_assert_fits(terminal.panel.content, layout, "%s %s" % [locale, path])
			terminal.panel.close()


func test_text_reads_from_the_camera() -> void:
	var font_size: float = THEME.default_font_size
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
		if station is LoadoutStation:
			var at_wall: float = (station as LoadoutStation).wall_view_height
			assert_gte(text_height / at_wall, MIN_TEXT_HEIGHT, path + " at the wall")
	for path: String in NPCS.values():
		var npc := _ship.get_node(path) as Npc
		assert_gte(_bubble_text_height(npc.bubble, npc), MIN_TEXT_HEIGHT, path + " bubble")


## For a card laid out in a viewport of its own: the map stops processing, so each of the many
## frames the card waits for doesn't also run the whole ship.
func _stop_map() -> void:
	_map.process_mode = Node.PROCESS_MODE_DISABLED
