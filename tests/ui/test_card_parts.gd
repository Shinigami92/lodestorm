extends GutTest
## The pieces the holo cards share: badge rows, pip rows, a single badge in a heading, and the
## offer card's cost, time, status and button.

const KYRITE: OreType = preload("res://game/ores/types/ore_kyrite.tres")
const NOCTILE: OreType = preload("res://game/ores/types/ore_noctile.tres")
const UPGRADE_CARD: PackedScene = preload("res://game/stations/upgrade/upgrade_card.tscn")
const ARMOR: Upgrade = preload("res://game/progression/upgrades/armor.tres")


func test_badge_row_shows_items_unknown_ones_and_amounts() -> void:
	var row: BadgeRow = add_child_autofree(BadgeRow.new())
	row.show_items([KYRITE, null])
	assert_eq(row.get_child_count(), 2)
	assert_eq((row.get_child(0) as ItemBadge).item, KYRITE)
	assert_eq((row.get_child(1) as Label).text, "?")
	row.show_items([KYRITE, NOCTILE], {NOCTILE: 3})
	assert_eq(row.get_items(), [KYRITE, NOCTILE])
	var entry := row.get_child(1) as HBoxContainer
	assert_eq((entry.get_child(0) as ItemBadge).item, NOCTILE)
	assert_eq((entry.get_child(1) as Label).text, "3")


func test_badge_row_is_made_again_only_when_its_items_change() -> void:
	var row: BadgeRow = add_child_autofree(BadgeRow.new())
	var ores: Array[OreType] = [KYRITE]
	row.show_items(ores)
	var badge: Node = row.get_child(0)
	row.show_items(ores.duplicate())
	assert_same(row.get_child(0), badge, "typed or not, the same items keep their badges")
	row.show_items([NOCTILE])
	assert_ne(row.get_child(0), badge)
	row.show_items([])
	assert_eq(row.get_child_count(), 0)


func test_pip_row_lights_the_level_and_fades_beyond_reach() -> void:
	var row: PipRow = add_child_autofree(PipRow.new())
	row.show_level(2, 5, 3, 0.5)
	assert_eq(row.get_child_count(), 5)
	var colors: Array[Color] = []
	for pip: ColorRect in row.get_children():
		colors.append(pip.color)
	assert_eq(
		colors, [PipRow.LIT, PipRow.LIT, PipRow.DARK, PipRow.OUT_OF_REACH, PipRow.OUT_OF_REACH]
	)
	var fill := row.get_child(2).get_node(^"Fill") as ColorRect
	assert_true(fill.visible, "the level under way fills its pip")
	assert_almost_eq(fill.size.x, row.pip_size.x * 0.5, 0.01)
	row.show_level(1, 3)
	assert_eq(row.get_child_count(), 3)
	assert_false((row.get_child(2).get_node(^"Fill") as ColorRect).visible)


func test_badge_slot_reuses_its_badge_and_hides_when_empty() -> void:
	var slot: CenterContainer = add_child_autofree(CenterContainer.new())
	ItemBadge.show_in(slot, KYRITE, false)
	var badge := slot.get_child(0) as ItemBadge
	assert_eq(badge.get_shown_name(), "")
	ItemBadge.show_in(slot, NOCTILE, false)
	assert_same(slot.get_child(0), badge)
	assert_eq(badge.item, NOCTILE)
	assert_true(slot.visible)
	ItemBadge.show_in(slot, null)
	assert_false(slot.visible)


func test_offer_says_how_long_only_when_it_can_start() -> void:
	var card: UpgradeCard = add_child_autofree(UPGRADE_CARD.instantiate())
	var cost: Dictionary[ItemType, int] = {KYRITE: 4}
	card.show_offer(cost, {}, 90.0, "Upgrade", false)
	assert_eq(card.get_time().text, "Takes 1:30")
	assert_true(card.get_time().visible)
	assert_false(card.get_status().visible)
	assert_true(card.get_action_button().disabled)
	card.show_offer(cost, {}, 90.0, "Upgrade", false, true)
	assert_false(card.get_time().visible, "a status line takes its place")
	assert_eq(card.get_status().text, "Locked until everyone is back aboard.")
	card.show_offer(cost, {}, -1.0, "Upgrade", true, false, "Not yet.")
	assert_eq(card.get_status().text, "Not yet.")
	assert_false(card.get_action_button().disabled)


func test_running_offer_says_time_left_and_stops_twice() -> void:
	var card: UpgradeCard = add_child_autofree(UPGRADE_CARD.instantiate())
	card.show_upgrade(ARMOR)
	card.show_running(3725.0, true)
	assert_eq(card.get_time().text, "Time left: 1:02:05")
	assert_eq(card.get_action_button().text, "Stop")
	assert_false(card.get_status().visible)
	card.show_running(3725.0, true, true)
	assert_eq(card.get_action_button().text, "Stop for sure")
	assert_eq(card.get_status().text, "Stop? The whole cost goes back to the hold.")
	card.show_running(10.0, false, true, false, "Only the bars done stay.")
	assert_eq(card.get_status().text, "Only the bars done stay.")
	assert_true(card.get_action_button().disabled)
