class_name FloorGuide
extends Node3D
## A marking painted on the floor: a text (`Text`, the rooms further on, separated by " · ") and
## an arrow (`Arrow`) beside it pointing the way. The marking is laid out for the English text,
## which often fills a narrow corridor: a translation never gets wider than it (unless a single
## room's name does), it wraps between rooms onto more lines instead. The arrow and the text's edge
## next to it stay where they are (the arrow often sits in a doorway); a longer text grows away
## from the arrow, so it never covers it.

const SEPARATOR := " · "
## Gap between the text's edge and the arrow's tail, in m.
const GAP: float = 0.3

## The text's size in m, as shown right now (translated, wrapped).
var text_size: Vector2
## The width in m from which the text wraps (the English text's width).
var max_width: float

## The English text (the label shows its translation).
var _source: String
## Arrow direction on the floor (unit vector along x or z, in the guide's space).
var _direction: Vector3
## The text's position for the English text.
var _text_origin: Vector3
## How far the text reaches towards the arrow for the English text, in m.
var _english_reach: float

@onready var _text: Label3D = $Text
@onready var _arrow: Node3D = $Arrow


func _ready() -> void:
	RenderLayers.put(self, RenderLayers.MARKINGS)
	_source = _text.text
	# The guide translates and wraps the text itself.
	_text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var offset := Vector3(_arrow.position.x, 0.0, _arrow.position.z)
	if absf(offset.x) >= absf(offset.z):
		_direction = Vector3(signf(offset.x), 0.0, 0.0)
	else:
		_direction = Vector3(0.0, 0.0, signf(offset.z))
	var english: Vector2 = measure(_source)
	max_width = english.x
	_text_origin = _text.position
	_english_reach = _half_extent(english)
	# How far the arrow reaches back from its origin, towards the text.
	var tail: float = 0.0
	for part: MeshInstance3D in _arrow.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = Transform3D(_arrow.basis) * part.transform * part.mesh.get_aabb()
		for i: int in 8:
			tail = maxf(tail, -box.get_endpoint(i).dot(_direction))
	var distance: float = maxf(offset.dot(_direction), _english_reach + GAP + tail)
	_arrow.position = _direction * distance + Vector3(0.0, _arrow.position.y, 0.0)
	_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_layout()


## The size in m of `text` as the label shows it.
func measure(text: String) -> Vector2:
	if _text.uppercase:
		text = text.to_upper()
	var font: Font = _text.font if _text.font else ThemeDB.fallback_font
	var size: Vector2 = font.get_multiline_string_size(
		text, HORIZONTAL_ALIGNMENT_CENTER, -1.0, _text.font_size
	)
	return size * _text.pixel_size


func _layout() -> void:
	_text.text = _wrap(tr(_source))
	text_size = measure(_text.text)
	_text.position = _text_origin - _direction * (_half_extent(text_size) - _english_reach)


## `text` with each line packed into lines no wider than `max_width`, breaking only between rooms.
func _wrap(text: String) -> String:
	var lines: PackedStringArray = []
	for line: String in text.split("\n"):
		var rooms: PackedStringArray = line.split(SEPARATOR)
		var current: String = rooms[0]
		for room: String in rooms.slice(1):
			var longer: String = current + SEPARATOR + room
			if measure(longer).x <= max_width:
				current = longer
			else:
				lines.append(current)
				current = room
		lines.append(current)
	return "\n".join(lines)


## How far the text reaches from its center towards the arrow. The label lies flat: its width
## runs along x, its height along z.
func _half_extent(size: Vector2) -> float:
	return (size.x if _direction.x != 0.0 else size.y) * 0.5
