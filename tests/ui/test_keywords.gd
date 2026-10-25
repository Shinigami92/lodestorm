extends GutTest
## Names stand out in spoken lines (`Keywords`), read from where they're defined.

const THEME: Theme = preload("res://assets/ui/terminal_theme.tres")

var _locale: String


func before_each() -> void:
	_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")


func after_each() -> void:
	TranslationServer.set_locale(_locale)


func test_names_of_every_kind_are_found() -> void:
	var names: PackedStringArray = Keywords.names()
	# A person (also one at a station), a planet, a region, a weapon, an ore, an alloy.
	for expected: String in [
		"Brannik", "Kade", "Torvane", "Redscar Flats", "Brask", "Kyrite", "Cobrel"
	]:
		assert_has(names, expected)
	assert_false(names.has(""), "colonists have no name")
	assert_false(names.has("Stalker"), "alien strains are common words")


func test_names_are_colored() -> void:
	var color: String = Keywords.COLOR.to_html(false)
	assert_eq(
		Keywords.highlight("Ask Kade about Redscar Flats."),
		"Ask [color=#%s]Kade[/color] about [color=#%s]Redscar Flats[/color]." % [color, color]
	)


func test_a_station_is_also_found_by_its_short_name() -> void:
	TranslationServer.set_locale("de")
	var color: String = Keywords.COLOR.to_html(false)
	assert_eq(
		Keywords.highlight("Auf Ostra, Waypost Ostra"),
		"Auf [color=#%s]Ostra[/color], [color=#%s]Waypost Ostra[/color]" % [color, color]
	)


func test_only_whole_names_match() -> void:
	assert_eq(Keywords.highlight("Out of range, Nellie."), "Out of range, Nellie.")
	assert_eq(Keywords.highlight("brask"), "brask", "the case counts")


func test_a_possessive_keeps_the_name_whole() -> void:
	var color: String = Keywords.COLOR.to_html(false)
	assert_eq(
		Keywords.highlight("Gaulm's moons, Gaulms Monde"),
		"[color=#%s]Gaulm[/color]'s moons, [color=#%s]Gaulms[/color] Monde" % [color, color]
	)


func test_brackets_stay_text() -> void:
	assert_eq(Keywords.highlight("[b]no[/b]"), "[lb]b]no[lb]/b]")


func test_the_bubbles_text_color_comes_from_the_theme() -> void:
	assert_eq(
		THEME.get_color(&"default_color", &"RichTextLabel"),
		THEME.get_color(&"font_color", &"Label")
	)


func test_a_bubble_shows_the_line_with_its_names_highlighted() -> void:
	var bubble := (load("res://game/npcs/speech_bubble.tscn") as PackedScene).instantiate()
	add_child_autofree(bubble)
	var speech := bubble as SpeechBubble
	speech.show_line("Nell runs the bar.")
	assert_eq(speech.get_line(), "Nell runs the bar.")
	var text := speech.find_child("Text") as RichTextLabel
	assert_eq(text.get_parsed_text(), "Nell runs the bar.")
	assert_string_contains(text.text, "[color=")
