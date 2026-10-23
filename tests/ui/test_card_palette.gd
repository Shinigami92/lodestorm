extends GutTest
## The holo cards' look: the terminal theme's card variations, and `CardPalette` holding the same
## colors for text that changes its color in code.

const THEME: Theme = preload("res://assets/ui/terminal_theme.tres")
const CARDS: Array[String] = [
	"res://game/npcs/talk_card.tscn",
	"res://game/stations/bed/bed_card.tscn",
	"res://game/stations/flight/flight_card.tscn",
	"res://game/stations/heat_shield/heat_shield_card.tscn",
	"res://game/stations/hold/hold_card.tscn",
	"res://game/stations/loadout/loadout_card.tscn",
	"res://game/stations/med_bed/med_bed_card.tscn",
	"res://game/stations/navigator/navigator_card.tscn",
	"res://game/stations/refinery/furnace_card.tscn",
	"res://game/stations/refinery/rack_card.tscn",
	"res://game/stations/skill_graph/skill_card.tscn",
	"res://game/stations/upgrade/upgrade_card.tscn",
]


func test_the_palette_matches_the_theme() -> void:
	assert_eq(THEME.get_color(&"font_color", &"CardTitle"), CardPalette.TITLE)
	assert_eq(THEME.get_color(&"font_color", &"CardStatus"), CardPalette.STATUS)
	assert_eq(THEME.get_color(&"font_color", &"CardNote"), CardPalette.NOTE)
	for variation: StringName in [&"CardTitle", &"CardText", &"CardNote", &"CardStatus"]:
		assert_eq(THEME.get_type_variation_base(variation), &"Label", variation)
	assert_eq(THEME.get_type_variation_base(&"Card"), &"PanelContainer")


## Every card gets its panel and its text sizes from the theme, not from copies of its own.
func test_cards_use_the_card_variations() -> void:
	for path: String in CARDS:
		var card := (load(path) as PackedScene).instantiate() as Control
		add_child_autofree(card)
		assert_eq(card.theme_type_variation, &"Card", path)
		assert_false(card.has_theme_stylebox_override(&"panel"), path)
		for node: Node in card.find_children("*", "Label", true, false):
			var label := node as Label
			assert_false(
				label.has_theme_font_size_override(&"font_size"), "%s %s" % [path, label.name]
			)
