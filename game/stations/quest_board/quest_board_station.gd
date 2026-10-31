class_name QuestBoardStation
extends Station
## The quest board on the bridge's back wall (see docs/design/missions.md, Quests): a screen with
## three tabs, the ship's quests (`BoardLists.quest_lines`), the jobs of whoever looks at it
## (`BoardLists.job_lines`, the ones finished since they last looked on top) and the ship's messages
## (`BoardLists.message_lines`), played aloud from its speaker (`BoardSpeaker`), an amber marker
## above it while one is unheard. Its parts are the open tab and the screen's lines (a `StationPart`
## on each line's right end; the screen marks the selected and hovered one); `move_*` up and down
## walk the lines and scroll the list, left and right and `tab_prev`/`tab_next` switch tabs, the
## wheel scrolls. The card beside the board shows the selected line: a quest with "Track" and "Set
## as destination" (where its step goes, `QuestVisit.destination`: chosen as at the navigator, the
## pilot then sets course from the cockpit), the done quests' group with "Show"/"Hide", a job, a
## message with "Play"/"Stop", or the tab. Closing it after the jobs were shown clears its user's
## finished ones (`FinishedJobs`).

enum Tab { QUESTS, JOBS, MESSAGES }

## Seconds between updates of the list (time left, progress) while nothing changes it.
const REFRESH: float = 1.0
## Gap between the board's right edge and the card, in m.
const CARD_GAP: float = 0.3
## Where the marker of unheard messages floats: above the board's top right corner (clear of the
## room's sign over its middle), in m.
const MARKER_HEIGHT: float = 3.75
const MARKER_SIDE: float = 2.45

## The tab shown.
var tab: Tab = Tab.QUESTS
## Whether the done quests' group is open.
var show_done: bool = false
## The lines of the tab shown.
var entries: Array[BoardEntry] = []
## The first entry on the screen (the list's scroll).
var first: int = 0
## Builds the lines.
var lists := BoardLists.new()
## The quest log shown, when not the ship's (tests).
var quests: QuestLog
## The messages shown, when not the ship's (tests).
var messages: MessageLog
## Plays the messages.
var speaker := BoardSpeaker.new()

var _row_parts: Array[StationPart] = []
var _tab_parts: Array[StationPart] = []
## Whether the jobs were shown since it was opened, and to whom.
var _jobs_shown: bool = false
var _looker: Player
var _since_refresh: float = 0.0
var _marker_time: float = 0.0
## Floats above the board while a message is unheard.
var _unheard_marker: MeshInstance3D

@onready var screen: WorldPanel = $Screen


func _ready() -> void:
	super()
	var parts := Node3D.new()
	parts.name = "Parts"
	add_child(parts)
	for i: int in BoardScreen.TABS:
		_tab_parts.append(_add_part(parts, "Tab%d" % i))
	for i: int in BoardScreen.LINES:
		_row_parts.append(_add_part(parts, "Line%d" % i))
	speaker.name = "Speaker"
	speaker.position = screen.position
	add_child(speaker)
	_add_unheard_marker()
	update_list()


func _process(delta: float) -> void:
	super(delta)
	_since_refresh += delta
	if _since_refresh >= REFRESH:
		update_list()
	_mark()
	_float_marker(delta)


## The quest log shown: `quests` when set, else the ship's.
func get_quests() -> QuestLog:
	if quests:
		return quests
	return ship.quests if ship else null


## The messages shown: `messages` when set, else the ship's.
func get_messages() -> MessageLog:
	if messages:
		return messages
	return ship.messages if ship else null


## Plays the message of `entry` from the start, or stops it while it plays. Returns whether it
## plays now.
func play(entry: BoardEntry) -> bool:
	if not entry or not entry.received:
		return false
	if speaker.playing_entry == entry.received:
		speaker.stop_message()
		refresh()
		return false
	speaker.play_message(entry.received, get_messages())
	refresh()
	return true


## Makes the lines again (the viewer's jobs, the quests' progress), keeping the selected one.
func update_list() -> void:
	_since_refresh = 0.0
	var board := _board()
	if not board:
		return
	var kept: String = ""
	var at: int = _row_parts.find(selected)
	if at >= 0 and first + at < entries.size():
		kept = entries[first + at].key
	var player: Player = viewer() if is_inside_tree() else null
	var quest_log: QuestLog = get_quests()
	var message_log: MessageLog = get_messages()
	if tab == Tab.QUESTS:
		entries = (
			lists.quest_lines(quest_log, show_done) if quest_log else ([] as Array[BoardEntry])
		)
	elif tab == Tab.JOBS:
		entries = lists.job_lines(player, Time.get_unix_time_from_system())
	else:
		entries = (lists.message_lines(message_log) if message_log else ([] as Array[BoardEntry]))
	first = clampi(first, 0, maxi(entries.size() - BoardScreen.LINES, 0))
	var unheard: int = message_log.unheard() if message_log else 0
	var news: Array[int] = [0, player.finished_jobs.entries.size() if player else 0, unheard]
	_unheard_marker.visible = unheard > 0
	board.show_tabs(tab, news)
	board.show_lines(entries, first)
	_place_parts(board)
	if not kept.is_empty() and user:
		var index: int = entries.find_custom(func(e: BoardEntry) -> bool: return e.key == kept)
		_select_entry(index if index >= 0 else _nearest_selectable(first + at))
	elif user:
		refresh()


## The line `part` shows (null: a tab, or nothing).
func entry_of(part: StationPart) -> BoardEntry:
	var at: int = _row_parts.find(part)
	return entries[first + at] if at >= 0 and first + at < entries.size() else null


## Shows tab `to` (wrapping around), its first line selected while it's used.
func set_tab(to: int) -> void:
	tab = wrapi(to, 0, Tab.size()) as Tab
	first = 0
	if tab == Tab.JOBS and user:
		_jobs_shown = true
		_looker = user
	update_list()
	if user:
		select(_tab_parts[tab])


## Opens or closes the done quests' group, keeping it selected.
func toggle_done() -> void:
	show_done = not show_done
	update_list()
	_select_entry(entries.find_custom(func(e: BoardEntry) -> bool: return e.key == "done"))


## Tracks `quest` (the session follows it). Returns whether it does.
func track(quest: Quest) -> bool:
	var quest_log: QuestLog = get_quests()
	if not quest_log or not quest_log.track(quest):
		return false
	update_list()
	return true


## Where the ship would go for `quest`'s active step (see `QuestVisit.destination`): the mission
## on offer in its region or the visit to its station, or null (all done aboard, or nothing on offer
## there, e.g. out of the heat shield's reach).
func course_for(quest: Quest) -> MissionBrief:
	var voyage: Voyage = ship.voyage if ship else null
	var quest_log: QuestLog = get_quests()
	var system: StarSystem = voyage.settings.system if voyage and voyage.settings else null
	if not system or not quest_log:
		return null
	var id: StringName = QuestVisit.destination(quest_log, quest)
	if id.is_empty():
		return null
	var region: Region = system.region_by_id(id)
	if region:
		return voyage.offer_for(region)
	var station: CelestialBody = system.body_by_id(id)
	return voyage.offer_for_station(station) if station else null


## Chooses where `quest`'s active step goes as the destination (`course_for`, like at the
## navigator). Returns whether it did.
func choose_course(quest: Quest) -> bool:
	var offer: MissionBrief = course_for(quest)
	if not offer or offer == ship.voyage.brief or not ship.voyage.choose(offer):
		return false
	refresh()
	return true


## Scrolls the list by `lines` (down: positive), keeping the selection on the screen.
func scroll(lines: int) -> void:
	var at: int = _row_parts.find(selected)
	var index: int = first + at if at >= 0 else -1
	first = clampi(first + lines, 0, maxi(entries.size() - BoardScreen.LINES, 0))
	update_list()
	if index >= 0 and user:
		var visible_index: int = clampi(index, first, first + BoardScreen.LINES - 1)
		_select_entry(_nearest_selectable(visible_index))


func get_parts() -> Array[StationPart]:
	var parts: Array[StationPart] = []
	if not _tab_parts.is_empty():
		parts.append(_tab_parts[tab])
	for part: StationPart in _row_parts:
		if part.visible:
			parts.append(part)
	return parts


func get_pickable_parts() -> Array[StationPart]:
	return _tab_parts + get_parts().slice(1)


## Up and down walk the selectable lines (scrolling), up from the first one reaches the tab; left
## and right switch tabs.
func step(direction: Vector2) -> void:
	if direction.x != 0.0:
		set_tab(tab + int(signf(direction.x)))
		return
	var at: int = _row_parts.find(selected)
	var index: int = first + at if at >= 0 else -1
	var next: int = index
	while true:
		next += int(signf(direction.y))
		if next < 0 or next >= entries.size() or entries[next].is_selectable():
			break
	if next < 0:
		first = 0
		update_list()
		select(_tab_parts[tab])
	elif next < entries.size():
		_select_entry(next)


func _opened() -> void:
	_jobs_shown = tab == Tab.JOBS
	_looker = user
	screen.set_on_top(true)
	update_list()
	_select_entry(_nearest_selectable(first))
	super()


func _closed() -> void:
	if _jobs_shown and is_instance_valid(_looker):
		_looker.finished_jobs.clear()
	_jobs_shown = false
	_looker = null
	screen.set_on_top(false)
	super()
	update_list()


func _cycle(by: int) -> void:
	set_tab(tab + by)


func _shortcut(event: InputEvent) -> bool:
	var wheel := event as InputEventMouseButton
	if not wheel or not wheel.pressed:
		return false
	if wheel.button_index == MOUSE_BUTTON_WHEEL_UP or wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		scroll(-1 if wheel.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
		return true
	return false


func _picked(part: StationPart) -> void:
	var at: int = _tab_parts.find(part)
	if at >= 0 and at != tab:
		set_tab(at)
	else:
		select(part)


## The line or tab under the mouse cursor on the screen, or null.
func _part_at(camera: Camera3D, screen_position: Vector2) -> StationPart:
	var board := _board()
	if not board:
		return null
	var pixel: Vector2 = screen.pixel_at(
		camera.project_ray_origin(screen_position), camera.project_ray_normal(screen_position)
	)
	if pixel == Vector2.INF:
		return null
	var at_tab: int = board.tab_at(pixel)
	if at_tab >= 0:
		return _tab_parts[at_tab]
	var line: int = board.line_at(pixel)
	return _row_parts[line] if line >= 0 and _row_parts[line].visible else null


## The card beside the board's right edge, level with the selected line (within the board).
func _card_position(camera: Camera3D) -> Vector3:
	var right: Vector3 = screen.global_basis.x.normalized()
	var up: Vector3 = screen.global_basis.y.normalized()
	var half: Vector2 = card.size * 0.5
	var level: float = up.dot(selected.global_position - screen.global_position)
	var reach: float = maxf(screen.size.y * 0.5 - half.y, 0.0)
	var along: float = screen.size.x * 0.5 + CARD_GAP + half.x
	return (
		screen.global_position
		+ right * along
		+ up * clampf(level, -reach, reach)
		+ camera.global_basis.z * 0.05
	)


## Selects entry `index` (scrolling it onto the screen), or the tab when there's none.
func _select_entry(index: int) -> void:
	if index < 0 or index >= entries.size() or not entries[index].is_selectable():
		select(_tab_parts[tab] if not _tab_parts.is_empty() else null)
		return
	if index < first or index >= first + BoardScreen.LINES:
		var top: int = index if index < first else index - BoardScreen.LINES + 1
		first = clampi(top, 0, maxi(entries.size() - BoardScreen.LINES, 0))
		var board := _board()
		board.show_lines(entries, first)
		_place_parts(board)
	select(_row_parts[index - first])


## The selectable entry nearest `index` (looking down first), or -1.
func _nearest_selectable(index: int) -> int:
	for offset: int in entries.size():
		for candidate: int in [index + offset, index - offset]:
			if candidate >= 0 and candidate < entries.size():
				if entries[candidate].is_selectable():
					return candidate
	return -1


## Puts the parts at their lines' right ends (and the tabs'), shown where a line can be selected.
func _place_parts(board: BoardScreen) -> void:
	for i: int in _row_parts.size():
		var entry: BoardEntry = entries[first + i] if first + i < entries.size() else null
		_row_parts[i].visible = entry != null and entry.is_selectable()
		var rect: Rect2 = board.line_rect(i)
		_row_parts[i].position = _on_screen(Vector2(rect.end.x, rect.get_center().y))
	for i: int in _tab_parts.size():
		var rect: Rect2 = board.tab_rect(i)
		_tab_parts[i].position = _on_screen(rect.get_center())


## Where `pixel` (on the screen's menu) is, in its local space.
func _on_screen(pixel: Vector2) -> Vector3:
	var layout: Vector2 = screen.size * screen.pixels_per_meter
	var uv: Vector2 = pixel / layout
	var local := Vector3((uv.x - 0.5) * screen.size.x, (0.5 - uv.y) * screen.size.y, 0.0)
	return screen.transform * local


## Marks the selected and hovered line and tab on the screen.
func _mark() -> void:
	var board := _board()
	if board:
		board.mark(
			_row_parts.find(selected),
			_row_parts.find(hovered),
			_tab_parts.find(selected),
			_tab_parts.find(hovered)
		)


## The amber marker of unheard messages (round, like an NPC's for something new).
func _add_unheard_marker() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.1
	sphere.height = 0.2
	sphere.radial_segments = 16
	sphere.rings = 8
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = CardPalette.STATUS
	sphere.material = material
	_unheard_marker = MeshInstance3D.new()
	_unheard_marker.name = "UnheardMarker"
	_unheard_marker.mesh = sphere
	_unheard_marker.layers = 8
	_unheard_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_unheard_marker.position = Vector3(MARKER_SIDE, MARKER_HEIGHT, screen.position.z)
	_unheard_marker.visible = false
	add_child(_unheard_marker)


## Bobs the marker of unheard messages while it shows.
func _float_marker(delta: float) -> void:
	if not _unheard_marker.visible:
		return
	_marker_time += delta
	_unheard_marker.position.y = MARKER_HEIGHT + 0.04 * sin(_marker_time * 3.0)


func _board() -> BoardScreen:
	return screen.content as BoardScreen if screen else null


func _add_part(parent: Node3D, part_name: String) -> StationPart:
	var part := StationPart.new()
	part.name = part_name
	part.pick_radius = 0.0
	parent.add_child(part)
	return part
