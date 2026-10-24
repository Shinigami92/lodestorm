extends GutTest
## The ore exchange on the depot's counter at Waypost Ostra (`ExchangeStation`): opening it in
## front of the counter, picking the ores and the amount on its card, trading from the player's
## hold, and the card saying why nothing can be traded.

const TEST_MAP := preload("res://tests/support/map_fixture.gd")
const THEME: Theme = preload("res://assets/ui/terminal_theme.tres")
const KYRITE: OreType = preload("res://game/ores/types/ore_kyrite.tres")
const OLVANE: OreType = preload("res://game/ores/types/ore_olvane.tres")
const VYREL: OreType = preload("res://game/ores/types/ore_vyrel.tres")
const MERIDINE: OreType = preload("res://game/ores/types/ore_meridine.tres")

var _map: Node3D
var _player: Player
var _station: SpaceStation
var _exchange: ExchangeStation


func before_each() -> void:
	SaveGame.directory = ""
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	var voyage := _map.get_node("Voyage") as Voyage
	await wait_physics_frames(2)
	var ostra: CelestialBody = voyage.settings.system.body_by_id(&"ostra")
	voyage.select(voyage.offer_for_station(ostra))
	voyage.skip_flight()
	await wait_physics_frames(2)
	_station = voyage.location as SpaceStation
	_exchange = _station.get_node("OreExchange") as ExchangeStation


func after_each() -> void:
	TranslationServer.set_locale("en")


func test_used_in_front_of_the_counter_beside_kade() -> void:
	assert_eq(
		Interactable.nearest(get_tree(), _exchange.use_point.global_position), _exchange.use_point
	)
	var kade := _station.get_node("People/Kade") as Npc
	assert_eq(
		Interactable.nearest(get_tree(), kade.use_point.global_position),
		kade.use_point,
		"Kade is still talked to beside it"
	)
	assert_eq(_exchange.get_parts().size(), 2, "a hopper in, a hopper out")


func test_trades_from_the_players_hold() -> void:
	_player.hold.add(KYRITE, 40.0)
	_player.hold.add(VYREL, 1.0)
	assert_true(_exchange.open(_player))
	# The ore the hold has most of goes in, the commonest other one comes out.
	assert_eq(_exchange.ore_in, KYRITE)
	assert_eq(_exchange.ore_out, VYREL)
	var card := _exchange.card_menu as ExchangeCard
	card.get_count_button(10).pressed.emit()
	card.get_count_button(10).pressed.emit()
	assert_eq(_exchange.get_count(), 13, "at most what 40 pay for")
	assert_true(card.get_count_button(1).disabled)
	assert_true(card.press_primary())
	assert_eq(_player.hold.amount(KYRITE), 1.0)
	assert_eq(_player.hold.amount(VYREL), 14.0)
	# Nothing left that goes in but Vyrel, and nothing else found to get for it but Kyrite.
	assert_eq(_exchange.ore_in, VYREL)
	assert_eq(_exchange.ore_out, KYRITE)
	assert_eq(_exchange.get_count(), 1, "starts from one again")
	_exchange.close()


func test_tab_picks_the_selected_hoppers_ore() -> void:
	for ore: OreType in [KYRITE, OLVANE, VYREL, MERIDINE] as Array[OreType]:
		_player.hold.add(ore, 30.0)
	assert_true(_exchange.open(_player))
	_exchange.ore_in = KYRITE
	_exchange.ore_out = OLVANE
	_exchange.select(_exchange.get_in_hopper())
	_exchange._cycle(1)
	assert_eq(_exchange.ore_in, VYREL, "skips the ore coming out")
	_exchange._cycle(1)
	assert_eq(_exchange.ore_in, MERIDINE, "a signature ore goes in")
	_exchange.select(_exchange.get_out_hopper())
	_exchange._cycle(1)
	assert_eq(_exchange.ore_out, VYREL)
	_exchange._cycle(1)
	assert_eq(_exchange.ore_out, KYRITE, "never a signature ore out")
	_exchange._cycle(-1)
	assert_eq(_exchange.ore_out, VYREL)
	_exchange.close()


func test_says_why_nothing_can_be_traded() -> void:
	_player.hold.add(KYRITE, 2.0)
	assert_true(_exchange.open(_player))
	var card := _exchange.card_menu as ExchangeCard
	assert_null(_exchange.ore_in)
	assert_true(card.get_status().visible)
	assert_string_contains(card.get_status().text, "no ore to trade")
	assert_true(card.get_action_button().disabled)
	assert_false(card.press_primary())
	_exchange.close()
	_player.hold.add(KYRITE, 10.0)
	assert_true(_exchange.open(_player))
	assert_eq(_exchange.ore_in, KYRITE)
	assert_null(_exchange.ore_out, "only Kyrite was ever found")
	assert_string_contains(card.get_status().text, "no other ore")
	assert_true(card.get_action_button().disabled)
	_exchange.close()


func test_card_fits_in_every_language() -> void:
	_player.hold.add(KYRITE, 99999.0)
	_player.hold.add(VYREL, 99999.0)
	assert_true(_exchange.open(_player))
	_exchange.step_count(9999)
	var panel: WorldPanel = _exchange.card
	var layout := Vector2(panel.size * panel.pixels_per_meter)
	for locale: String in SettingsList.languages():
		TranslationServer.set_locale(locale)
		for hopper: StationPart in _exchange.get_parts():
			_exchange.select(hopper)
			await wait_process_frames(1)
			var needed: Vector2 = _exchange.card_menu.get_combined_minimum_size()
			assert_lte(needed.x, layout.x + 0.5, "%s %s: %s wide" % [locale, hopper.name, needed.x])
			assert_lte(needed.y, layout.y + 0.5, "%s %s: %s high" % [locale, hopper.name, needed.y])
	# The status lines too.
	_exchange.close()
	_player.hold.items.clear()
	for locale: String in SettingsList.languages():
		TranslationServer.set_locale(locale)
		assert_true(_exchange.open(_player))
		await wait_process_frames(1)
		var needed: Vector2 = _exchange.card_menu.get_combined_minimum_size()
		assert_lte(needed.y, layout.y + 0.5, "%s nothing to trade: %s high" % [locale, needed.y])
		_exchange.close()


func test_card_text_reads_from_the_camera() -> void:
	var card: WorldPanel = _exchange.card
	var text_height: float = (
		THEME.default_font_size / card.pixels_per_meter * card.global_basis.y.length()
	)
	assert_gte(text_height / _exchange.view_height, 0.02)
