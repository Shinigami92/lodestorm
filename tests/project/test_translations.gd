extends GutTest

const TRANSLATIONS := preload("res://tools/translations.gd")
const TEST_MAP := preload("res://tests/support/test_map.gd")


func after_each() -> void:
	TranslationServer.set_locale("en")


func test_template_is_up_to_date() -> void:
	var expected: String = TRANSLATIONS.template(TRANSLATIONS.extract())
	var actual: String = FileAccess.get_file_as_string(TRANSLATIONS.TEMPLATE_PATH)
	assert_eq(actual, expected, "texts changed: run tools/translations.sh")


func test_translations_are_up_to_date_and_complete() -> void:
	var entries: Array[Dictionary] = TRANSLATIONS.extract()
	var paths: PackedStringArray = TRANSLATIONS.translation_paths()
	assert_has(paths, "res://locale/de.po")
	for path: String in paths:
		var content: String = FileAccess.get_file_as_string(path)
		assert_eq(
			content, TRANSLATIONS.merge(entries, content), "%s: run tools/translations.sh" % path
		)
		assert_eq(
			TRANSLATIONS.untranslated(content), PackedStringArray(), "%s: untranslated" % path
		)


func test_merge_keeps_translations_and_drops_unused() -> void:
	var entries: Array[Dictionary] = [
		{&"context": "", &"id": "Bridge", &"references": ["a.tscn"]},
		{&"context": "verb", &"id": 'Mine "ore"\nnow', &"references": ["b.gd"]},
	]
	var existing: String = (
		'msgid ""\nmsgstr ""\n"Language: de\\n"\n\n'
		+ 'msgid "Bridge"\nmsgstr "Brücke"\n\nmsgid "Gone"\nmsgstr "Weg"\n'
	)
	var merged: String = TRANSLATIONS.merge(entries, existing)
	var translations: Dictionary[String, String] = TRANSLATIONS.parse(merged)
	assert_eq(translations.size(), 3)
	assert_eq(translations[""], "Language: de\n")
	assert_eq(translations[TRANSLATIONS.CONTEXT_SEPARATOR + "Bridge"], "Brücke")
	assert_eq(translations["verb" + TRANSLATIONS.CONTEXT_SEPARATOR + 'Mine "ore"\nnow'], "")
	assert_eq(TRANSLATIONS.untranslated(merged), PackedStringArray(['Mine "ore"\nnow']))


func test_german() -> void:
	TranslationServer.set_locale("de")
	assert_eq(tr("Bridge"), "Brücke")
	assert_eq(tr("All aboard"), "Alle an Bord")
	TranslationServer.set_locale("de_AT")
	assert_eq(tr("Bridge"), "Brücke", "regional variants use the language")


func test_unknown_language_shows_english() -> void:
	TranslationServer.set_locale("fr")
	assert_eq(tr("Bridge"), "Bridge")


func test_ship_shows_translated_texts() -> void:
	TranslationServer.set_locale("de")
	var map: Node3D = TEST_MAP.instantiate() as Node3D
	add_child_autofree(map)
	var sign: Label3D = map.get_node("Ship/Rooms/Upper/Bridge/Sign") as Label3D
	assert_eq(sign.text, "Bridge", "the scene keeps the English text")
	assert_eq(sign.tr(sign.text), "Brücke")
	assert_eq(sign.auto_translate_mode, Node.AUTO_TRANSLATE_MODE_INHERIT)
	var ship: Ship = map.get_node("Ship") as Ship
	var mission: Mission = map.get_node("Mission") as Mission
	mission.state = Mission.State.RETURNED
	await wait_process_frames(1)
	assert_eq(ship.countdown_text, "Alle an Bord")
