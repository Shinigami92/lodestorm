class_name BoardScreen
extends PanelContainer
## The quest board's screen (see `QuestBoardStation`): its tabs (Quests, Jobs) over a list of
## `LINES` lines showing the board's `BoardEntry`s from a scroll position. Headings are amber, a
## quest's line has its giver and a bar for its active step, the tracked one a filled diamond, a
## job its time left. The station marks the selected and the hovered line (or tab) and asks where
## they are (`line_rect`, `line_at`) to place its parts and to point with the mouse.

## Lines the list shows at once.
const LINES: int = 10
## Height of a line, in px.
const LINE_HEIGHT: float = 52.0
## Width of a quest's step bar, in px.
const BAR_WIDTH: float = 120.0
const BAR_HEIGHT: float = 8.0
## How many tabs (`QuestBoardStation.Tab`).
const TABS: int = 2

var _tabs: Array[PanelContainer] = []
var _tab_labels: Array[Label] = []
var _rows: Array[PanelContainer] = []
var _markers: Array[BoardMarker] = []
var _titles: Array[Label] = []
var _notes: Array[Label] = []
var _bars: Array[ProgressBar] = []
## The entries shown on each line (null: empty).
var _shown: Array[BoardEntry] = []
var _styles: Dictionary[StringName, StyleBox] = {}
var _open_tab: int = 0


func _ready() -> void:
	_styles[&"selected"] = _frame(CardPalette.STATUS, 0.14)
	_styles[&"hovered"] = _frame(Color(CardPalette.STATUS, 0.45), 0.0)
	_styles[&"active"] = _frame(Color(CardPalette.TITLE, 0.6), 0.1)
	_styles[&"none"] = _frame(Color.TRANSPARENT, 0.0)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override(&"separation", 10)
	add_child(layout)
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override(&"separation", 12)
	layout.add_child(tab_row)
	for i: int in TABS:
		var tab := PanelContainer.new()
		var label: Label = _label(&"CardTitle")
		tab.add_child(label)
		tab_row.add_child(tab)
		_tabs.append(tab)
		_tab_labels.append(label)
	var list := VBoxContainer.new()
	list.add_theme_constant_override(&"separation", 0)
	layout.add_child(list)
	for i: int in LINES:
		_add_row(list)
	_shown.resize(LINES)
	_update_tab_texts([])


## Shows `tab` (a `QuestBoardStation.Tab`) as the open one, with `news` beside each tab's name (a
## count, 0: none; e.g. the jobs finished and not seen yet).
func show_tabs(tab: int, news: Array[int]) -> void:
	_open_tab = tab
	_update_tab_texts(news)
	for i: int in _tabs.size():
		_tab_labels[i].modulate = Color.WHITE if i == tab else CardPalette.DIMMED


## Shows `entries` from `first` on, one per line.
func show_lines(entries: Array[BoardEntry], first: int) -> void:
	for i: int in LINES:
		var index: int = first + i
		var entry: BoardEntry = entries[index] if index >= 0 and index < entries.size() else null
		_shown[i] = entry
		_show_line(i, entry)


## Marks the line `selected` and the line `hovered` (-1: none), and the tab `selected_tab` and
## `hovered_tab` (-1: none).
func mark(selected: int, hovered: int, selected_tab: int, hovered_tab: int) -> void:
	for i: int in LINES:
		var style: StringName = &"none"
		if i == selected:
			style = &"selected"
		elif i == hovered:
			style = &"hovered"
		_rows[i].add_theme_stylebox_override(&"panel", _styles[style])
	for i: int in _tabs.size():
		var style: StringName = &"active" if i == _open_tab else &"none"
		if i == selected_tab:
			style = &"selected"
		elif i == hovered_tab:
			style = &"hovered"
		_tabs[i].add_theme_stylebox_override(&"panel", _styles[style])


## Where line `index` is on the screen, in px.
func line_rect(index: int) -> Rect2:
	return _rows[index].get_global_rect()


## Where tab `index` is on the screen, in px.
func tab_rect(index: int) -> Rect2:
	return _tabs[index].get_global_rect()


## The line at `pixel` (on the screen, in px), or -1.
func line_at(pixel: Vector2) -> int:
	for i: int in LINES:
		if _rows[i].get_global_rect().has_point(pixel):
			return i
	return -1


## The tab at `pixel` (on the screen, in px), or -1.
func tab_at(pixel: Vector2) -> int:
	for i: int in _tabs.size():
		if _tabs[i].get_global_rect().has_point(pixel):
			return i
	return -1


## The texts on line `index`: its title and its note (for tests and probes).
func get_line_texts(index: int) -> PackedStringArray:
	return [_titles[index].text, _notes[index].text]


## Whether line `index`'s texts fit without being cut short (for the fit test).
func line_fits(index: int) -> bool:
	var title: Label = _titles[index]
	var font: Font = title.get_theme_font(&"font")
	var width: float = (
		font
		. get_string_size(
			title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, title.get_theme_font_size(&"font_size")
		)
		. x
	)
	return width <= title.size.x + 0.5


func _update_tab_texts(news: Array[int]) -> void:
	for i: int in _tab_labels.size():
		var count: int = news[i] if i < news.size() else 0
		var named: String = tr("Quests") if i == 0 else tr("Jobs")
		_tab_labels[i].text = named + (" (%d)" % count if count > 0 else "")


func _show_line(i: int, entry: BoardEntry) -> void:
	var title: Label = _titles[i]
	var note: Label = _notes[i]
	title.text = entry.title if entry else ""
	note.text = entry.note if entry else ""
	var heading: bool = entry != null and entry.kind == BoardEntry.Kind.HEADING
	title.theme_type_variation = &"CardStatus" if heading else &""
	title.modulate = (
		CardPalette.NOTE if entry and entry.kind == BoardEntry.Kind.NOTE else Color.WHITE
	)
	var done: bool = entry != null and entry.kind == BoardEntry.Kind.QUEST and entry.done
	if done or (entry and entry.kind == BoardEntry.Kind.JOB and entry.ends_at <= 0.0):
		note.add_theme_color_override(&"font_color", CardPalette.GOOD)
	else:
		note.remove_theme_color_override(&"font_color")
	_bars[i].visible = entry != null and entry.progress >= 0.0
	_bars[i].value = entry.progress if entry else 0.0
	var marker: BoardMarker = _markers[i]
	marker.shape = BoardMarker.Shape.NONE
	if entry and entry.kind == BoardEntry.Kind.QUEST and not entry.done:
		marker.shape = BoardMarker.Shape.TRACKED if entry.tracked else BoardMarker.Shape.ACTIVE
	elif entry and entry.kind == BoardEntry.Kind.DONE:
		marker.shape = BoardMarker.Shape.OPEN if entry.done else BoardMarker.Shape.CLOSED
	marker.queue_redraw()


func _add_row(list: VBoxContainer) -> void:
	var row := PanelContainer.new()
	row.custom_minimum_size.y = LINE_HEIGHT
	row.add_theme_stylebox_override(&"panel", _styles[&"none"])
	list.add_child(row)
	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 14)
	row.add_child(line)
	var marker := BoardMarker.new()
	line.add_child(marker)
	var title := _label(&"")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line.add_child(title)
	var note := _label(&"CardNote")
	line.add_child(note)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.max_value = 1.0
	bar.show_percentage = false
	bar.add_theme_stylebox_override(&"background", _frame(Color(CardPalette.STATUS, 0.35), 0.0))
	var fill := StyleBoxFlat.new()
	fill.bg_color = CardPalette.STATUS
	bar.add_theme_stylebox_override(&"fill", fill)
	line.add_child(bar)
	_rows.append(row)
	_markers.append(marker)
	_titles.append(title)
	_notes.append(note)
	_bars.append(bar)


## A label of the card's `variation` (texts set from code are translated already).
func _label(variation: StringName) -> Label:
	var label := Label.new()
	label.theme_type_variation = variation
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


## A frame in `color` with a fill of it at `fill` opacity.
static func _frame(color: Color, fill: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color, color.a * fill)
	style.border_color = color
	style.set_border_width_all(2)
	style.set_content_margin_all(6.0)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	return style
