class_name QuestBoardCard
extends StationCard
## The quest board's holo card (see `QuestBoardStation`): a quest (its giver, where its step is
## handed in, the step with its goals and rewards, `QuestPanel`; "Track"), the done quests' group
## ("Show"/"Hide"), a job (what it reaches, the time left) or a tab (what it lists).

var _panel := QuestPanel.new()

@onready var _title: Label = %Title
@onready var _note: Label = %Note
@onready var _where: Label = %Where
@onready var _status: Label = %Status
@onready var _action: Button = %Action


func _ready() -> void:
	_panel.name = "Quest"
	%Layout.add_child(_panel)
	%Layout.move_child(_panel, _where.get_index() + 1)
	_action.pressed.connect(press_primary)


func show_part(part: StationPart) -> void:
	var board := station as QuestBoardStation
	visible = part != null and board != null
	if not visible:
		return
	_panel.visible = false
	_where.visible = false
	_status.visible = false
	_action.visible = false
	var entry: BoardEntry = board.entry_of(part)
	if not entry:
		_show_tab(board)
	elif entry.kind == BoardEntry.Kind.QUEST:
		_show_quest(board, entry)
	elif entry.kind == BoardEntry.Kind.DONE:
		_title.text = entry.title
		_note.text = tr("Quests whose last step is handed in.")
		_show_action(tr("Hide") if entry.done else tr("Show"), false)
	else:
		_show_job(entry)


func press_primary() -> bool:
	var board := station as QuestBoardStation
	var entry: BoardEntry = board.entry_of(board.selected) if board else null
	if not entry:
		return false
	if entry.kind == BoardEntry.Kind.DONE:
		board.toggle_done()
		return true
	if entry.kind == BoardEntry.Kind.QUEST and not entry.done and not entry.tracked:
		return board.track(entry.quest)
	return false


## The texts of the card (for tests and probes): title, note, where, status.
func get_texts() -> PackedStringArray:
	var texts: PackedStringArray = [_title.text, _note.text]
	texts.append(_where.text if _where.visible else "")
	texts.append(_status.text if _status.visible else "")
	return texts


## The card's button (for tests and probes): "Track", "Show" or "Hide".
func get_action() -> Button:
	return _action


## The quest's panel (for tests and probes).
func get_quest_panel() -> QuestPanel:
	return _panel


func _show_tab(board: QuestBoardStation) -> void:
	if board.tab == QuestBoardStation.Tab.QUESTS:
		_title.text = tr("Quests")
		_note.text = tr("What people asked of you, and how far it is.")
	else:
		_title.text = tr("Jobs")
		_note.text = tr("Upgrades, skills, miners and furnaces at work, and what's done.")


func _show_quest(board: QuestBoardStation, entry: BoardEntry) -> void:
	var quest: Quest = entry.quest
	var quests: QuestLog = board.get_quests()
	_title.text = tr(quest.title)
	_note.text = board.lists.npc_name(quest.giver)
	var profile: NpcProfile = NpcProfile.find(quest.giver)
	if profile and not profile.display_name.is_empty():
		_note.text = "%s · %s" % [_note.text, tr(profile.role)]
	if entry.done:
		_show_status(tr("Done"), CardPalette.GOOD)
		return
	var step: QuestStep = quests.current_step(quest)
	if step:
		var npc: StringName = quest.hand_in_npc(step)
		_where.visible = true
		_where.text = (
			tr("Hand in: %s (%s)") % [board.lists.npc_name(npc), board.lists.place_of(npc)]
		)
	_panel.visible = true
	var viewer: Player = board.viewer()
	_panel.show_quest(quest, quests, viewer.hold if viewer else null, false)
	_show_action(tr("Tracked") if entry.tracked else tr("Track"), entry.tracked)


func _show_job(entry: BoardEntry) -> void:
	_title.text = entry.title
	_note.text = entry.status
	if entry.ends_at <= 0.0:
		_show_status(tr("Done"), CardPalette.GOOD)
	else:
		var left: float = maxf(entry.ends_at - Time.get_unix_time_from_system(), 0.0)
		_show_status(tr("Time left: %s") % OfferCard.duration_text(left), CardPalette.STATUS)


func _show_status(text: String, color: Color) -> void:
	_status.visible = true
	_status.text = text
	_status.add_theme_color_override(&"font_color", color)


func _show_action(text: String, disabled: bool) -> void:
	_action.visible = true
	_action.text = text
	_action.disabled = disabled
