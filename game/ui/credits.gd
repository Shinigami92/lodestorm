class_name Credits
extends ScrollContainer
## The credits (a page of the settings, and shown at the title view after a while without input):
## who made the game, the tools, and the third-party licenses (Godot's own and those of the
## components it's built from). The sound sources join them with the sound effects. Scrolls with
## the mouse wheel and the up and down directions (`scroll_step`), or by itself (`scroll_speed`),
## starting over at the end.

## Who made the game and the tools, as they're named (not translated).
const TEAM: String = "Shinigami92"
const TOOLS: PackedStringArray = [
	"Godot Engine", "Blender", "Claude Code", "GUT", "gdtoolkit", "godot-ai", "ruff"
]
## The licenses of the fonts the game ships (their texts are exported with them, see
## export_presets.cfg's include filter).
const FONT_LICENSES: Dictionary[String, String] = {
	"Tilt Neon": "res://assets/fonts/tilt_neon/OFL.txt",
}
const BODY_COLOR := Color(1.0, 1.0, 1.0, 0.8)
## Font size of the license texts: smaller than the body text (long legal text, read rarely), still
## at the smallest size that reads.
const SMALL_FONT_SIZE: int = 24
## Seconds the end stays before scrolling by itself starts over.
const END_PAUSE: float = 3.0

## How far `ui_up`/`ui_down` scroll, in pixels.
@export var scroll_step: int = 120
## Pixels per second it scrolls by itself (0: still).
@export var scroll_speed: float = 0.0

var _scrolled: float = 0.0
var _end_time: float = 0.0

@onready var _team: Label = %Team
@onready var _tools: Label = %Tools
@onready var _licenses: VBoxContainer = %Licenses


func _ready() -> void:
	_team.text = TEAM
	_tools.text = "\n".join(TOOLS)
	for font_name: String in FONT_LICENSES:
		var license: String = FileAccess.get_file_as_string(FONT_LICENSES[font_name])
		_add_license_text(font_name + "\n\n" + license)
	_add_license_text(Engine.get_license_text())
	var components: PackedStringArray = []
	for component: Dictionary in Engine.get_copyright_info():
		var lines: PackedStringArray = [str(component["name"])]
		for part: Dictionary in component["parts"]:
			for copyright: String in part["copyright"]:
				lines.append("© " + copyright)
			lines.append(str(part["license"]))
		components.append("\n".join(lines))
	_add_license_text("\n\n".join(components))
	var license_info: Dictionary = Engine.get_license_info()
	for license_name: String in license_info:
		_add_license_text(license_name + "\n\n" + str(license_info[license_name]))


func _process(delta: float) -> void:
	if scroll_speed <= 0.0 or not is_visible_in_tree():
		return
	var end: float = maxf(get_v_scroll_bar().max_value - size.y, 0.0)
	if _scrolled >= end:
		_end_time += delta
		if _end_time >= END_PAUSE:
			restart()
		return
	_scrolled = minf(_scrolled + scroll_speed * delta, end)
	scroll_vertical = roundi(_scrolled)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	for action: StringName in [&"ui_up", &"ui_down"]:
		if event.is_action_pressed(action, true):
			scroll_vertical += scroll_step * (-1 if action == &"ui_up" else 1)
			_scrolled = scroll_vertical
			get_viewport().set_input_as_handled()


## Back to the top.
func restart() -> void:
	_scrolled = 0.0
	_end_time = 0.0
	scroll_vertical = 0


func _add_license_text(text: String) -> void:
	var label := Label.new()
	label.text = text
	# Legal texts stay as they are.
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 1.0
	label.add_theme_font_size_override(&"font_size", SMALL_FONT_SIZE)
	label.add_theme_color_override(&"font_color", BODY_COLOR)
	_licenses.add_child(label)
