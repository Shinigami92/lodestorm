extends GutTest

const TEST_MAP := preload("res://tests/support/test_map.gd")

var _guides: Array[FloorGuide] = []


func before_each() -> void:
	var map: Node3D = TEST_MAP.instantiate() as Node3D
	add_child_autofree(map)
	_guides.clear()
	for guide: Node in map.find_children("*", "FloorGuide", true, false):
		_guides.append(guide as FloorGuide)


func after_each() -> void:
	TranslationServer.set_locale("en")


func test_ship_has_guides() -> void:
	assert_gt(_guides.size(), 10)


func test_english_text_is_shown_as_is() -> void:
	for guide: FloorGuide in _guides:
		var text: Label3D = guide.get_node("Text") as Label3D
		assert_false(text.text.is_empty())
		assert_eq(
			text.auto_translate_mode, Node.AUTO_TRANSLATE_MODE_DISABLED, "the guide translates"
		)
		assert_almost_eq(guide.text_size.x, guide.max_width, 0.001, guide.name)


func test_arrow_clears_the_text() -> void:
	for locale: String in ["en", "de"]:
		TranslationServer.set_locale(locale)
		for guide: FloorGuide in _guides:
			var direction: Vector3 = _direction(guide)
			var text: Label3D = guide.get_node("Text") as Label3D
			var reach: float = (
				text.position.dot(direction)
				+ (guide.text_size.x if direction.x != 0.0 else guide.text_size.y) * 0.5
			)
			var arrow: Node3D = guide.get_node("Arrow") as Node3D
			var tail: float = arrow.position.dot(direction) - _arrow_tail(arrow, direction)
			assert_gt(tail - reach, FloorGuide.GAP - 0.001, "%s (%s)" % [guide.name, locale])


func test_translation_wraps_between_rooms_within_english_width() -> void:
	var arrows: Dictionary[FloorGuide, Vector3] = {}
	var english: Dictionary[FloorGuide, String] = {}
	for guide: FloorGuide in _guides:
		arrows[guide] = (guide.get_node("Arrow") as Node3D).position
		english[guide] = (guide.get_node("Text") as Label3D).text
	TranslationServer.set_locale("de")
	var wrapped: int = 0
	for guide: FloorGuide in _guides:
		var text: Label3D = guide.get_node("Text") as Label3D
		var german: String = guide.tr(english[guide])
		assert_ne(german, english[guide], "%s is translated" % guide.name)
		var rooms: String = text.text.replace("\n", FloorGuide.SEPARATOR)
		assert_eq(rooms, german.replace("\n", FloorGuide.SEPARATOR), "only line breaks change")
		for line: String in text.text.split("\n"):
			assert_false(line.begins_with("·") or line.ends_with("·"), line)
			if FloorGuide.SEPARATOR in line:
				assert_lt(guide.measure(line).x, guide.max_width + 0.001, line)
		if text.text.count("\n") > german.count("\n"):
			wrapped += 1
		var arrow: Vector3 = (guide.get_node("Arrow") as Node3D).position
		assert_eq(arrow, arrows[guide], "%s: the arrow stays" % guide.name)
	assert_gt(wrapped, 0, "German needs wrapping somewhere")


func test_switching_back_restores_english() -> void:
	var texts: Dictionary[FloorGuide, String] = {}
	for guide: FloorGuide in _guides:
		texts[guide] = (guide.get_node("Text") as Label3D).text
	TranslationServer.set_locale("de")
	TranslationServer.set_locale("en")
	for guide: FloorGuide in _guides:
		assert_eq((guide.get_node("Text") as Label3D).text, texts[guide])


static func _direction(guide: FloorGuide) -> Vector3:
	var offset: Vector3 = (guide.get_node("Arrow") as Node3D).position
	if absf(offset.x) >= absf(offset.z):
		return Vector3(signf(offset.x), 0.0, 0.0)
	return Vector3(0.0, 0.0, signf(offset.z))


static func _arrow_tail(arrow: Node3D, direction: Vector3) -> float:
	var tail: float = 0.0
	for part: MeshInstance3D in arrow.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = Transform3D(arrow.basis) * part.transform * part.mesh.get_aabb()
		for i: int in 8:
			tail = maxf(tail, -box.get_endpoint(i).dot(direction))
	return tail
