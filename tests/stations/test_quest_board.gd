extends "res://tests/support/menu_fit.gd"
## The quest board on the bridge (`QuestBoardStation`, `BoardLists`, `QuestBoardCard`): the quests
## in their groups, tracking, the done group, the jobs with the finished ones on top until seen,
## the messages played from its speaker (heard to the end, its marker while one is unheard),
## walking and scrolling the lines, and its screen and card fitting in every language.

const QUEST_LOG_TEST := preload("res://tests/quests/test_quest_log.gd")
const FULL_HOLD := preload("res://tests/support/full_hold.gd")
const BOARD: String = "Rooms/Upper/Bridge/QuestBoard"
const ARMOR: Upgrade = preload("res://game/progression/upgrades/armor.tres")
const DASH: Skill = preload("res://game/progression/skills/tree/dash.tres")
const MERISK: AlloyType = preload("res://game/refinery/alloys/alloy_merisk.tres")
const KYRITE: OreType = preload("res://game/ores/types/ore_kyrite.tres")

var _board: QuestBoardStation


func before_each() -> void:
	await super()
	_board = _ship.get_node(BOARD) as QuestBoardStation


func test_quests_in_their_groups() -> void:
	var quests: Array[Quest] = _accept_quests(
		[Quest.Kind.SIDE, Quest.Kind.MAIN, Quest.Kind.REQUEST, Quest.Kind.SIDE]
	)
	_finish(quests[3])
	_board.update_list()
	assert_eq(
		_lines(),
		(
			[
				"heading Main",
				"quest q1",
				"heading Side",
				"quest q0",
				"heading Requests",
				"quest q2",
				"done Done (1)",
			]
			as Array[String]
		)
	)
	var first: BoardEntry = _board.entries[3]
	assert_true(first.tracked, "the first one accepted is tracked")
	assert_eq(first.note, "Brannik", "its giver")
	_board.toggle_done()
	var lines: Array[String] = _lines()
	assert_eq(lines[lines.size() - 1], "quest q3", "the done group opened")
	assert_true(_board.entries[_board.entries.size() - 1].done)


func test_no_quests_says_so() -> void:
	_board.update_list()
	assert_eq(_board.entries.size(), 1)
	assert_eq(_board.entries[0].kind, BoardEntry.Kind.NOTE)


func test_the_card_tracks_a_quest() -> void:
	var quests: Array[Quest] = _accept_quests([Quest.Kind.SIDE, Quest.Kind.SIDE])
	_board.open(_player)
	await wait_process_frames(2)
	var card := _board.card_menu as QuestBoardCard
	assert_eq(_board.entry_of(_board.selected).quest, quests[0], "the first line selected")
	assert_true(card.get_action().disabled, "tracked already")
	_board.step(Vector2.DOWN)
	assert_eq(_board.entry_of(_board.selected).quest, quests[1])
	assert_eq(card.get_texts()[2], "Hand in: Brannik (aboard)")
	assert_false(card.get_action().disabled)
	assert_true(card.press_primary())
	assert_eq(_ship.quests.get_tracked(), quests[1])
	assert_eq(_board.entry_of(_board.selected).quest, quests[1], "still selected")
	assert_true(_board.entry_of(_board.selected).tracked)
	_board.close()


func test_walking_the_lines_and_the_tabs() -> void:
	_accept_quests([Quest.Kind.MAIN, Quest.Kind.SIDE])
	_board.open(_player)
	await wait_process_frames(2)
	assert_eq(_board.entry_of(_board.selected).quest.id, &"q0", "past the heading")
	_board.step(Vector2.DOWN)
	assert_eq(_board.entry_of(_board.selected).quest.id, &"q1", "over the next heading")
	_board.step(Vector2.DOWN)
	assert_eq(_board.entry_of(_board.selected).quest.id, &"q1", "the last one")
	_board.step(Vector2.UP)
	_board.step(Vector2.UP)
	assert_null(_board.entry_of(_board.selected), "up to the tab")
	assert_eq(_board.get_parts()[0], _board.selected)
	_board.step(Vector2.RIGHT)
	assert_eq(_board.tab, QuestBoardStation.Tab.JOBS)
	_board.step(Vector2.RIGHT)
	assert_eq(_board.tab, QuestBoardStation.Tab.MESSAGES)
	_board.step(Vector2.RIGHT)
	assert_eq(_board.tab, QuestBoardStation.Tab.QUESTS, "around")
	_board.close()


func test_a_long_list_scrolls_with_the_selection() -> void:
	var count: int = BoardScreen.LINES * 2
	var kinds: Array[Quest.Kind] = []
	kinds.resize(count)
	kinds.fill(Quest.Kind.SIDE)
	_accept_quests(kinds)
	_board.open(_player)
	await wait_process_frames(2)
	for i: int in count - 1:
		_board.step(Vector2.DOWN)
	assert_eq(_board.entry_of(_board.selected).quest.id, StringName("q%d" % (count - 1)))
	assert_eq(_board.first, _board.entries.size() - BoardScreen.LINES, "scrolled to the end")
	_board.scroll(-BoardScreen.LINES)
	assert_eq(_board.first, _board.entries.size() - BoardScreen.LINES * 2)
	var shown: BoardEntry = _board.entry_of(_board.selected)
	assert_not_null(shown, "the selection stays on the screen")
	_board.close()


func test_jobs_finished_show_until_seen() -> void:
	FULL_HOLD.fill(_player.hold)
	var now: float = Time.get_unix_time_from_system()
	assert_true(_player.upgrades.start(ARMOR, _player.hold, now))
	assert_true(_player.skills.start(DASH, _player.hold, now - 1.0e6))
	assert_true(_player.refining.start(1, MERISK, 3, _player.hold, now))
	_player.skills.update(now)
	_board.set_tab(QuestBoardStation.Tab.JOBS)
	var lines: Array[String] = _lines()
	assert_eq(lines[0], "heading Finished")
	assert_eq(lines[1], "job Dash")
	assert_eq(lines[2], "heading Under way")
	assert_eq(lines.size(), 5, "the armor and the batch")
	assert_true(_board.entries[1].note == "Done")
	_board.set_tab(QuestBoardStation.Tab.QUESTS)
	_board.open(_player)
	_board.close()
	assert_eq(_player.finished_jobs.entries.size(), 1, "the jobs weren't shown")
	_board.open(_player)
	_board.set_tab(QuestBoardStation.Tab.JOBS)
	await wait_process_frames(2)
	var card := _board.card_menu as QuestBoardCard
	_board.step(Vector2.DOWN)
	assert_eq(card.get_texts()[0], "Dash")
	assert_eq(card.get_texts()[1], "Rank 1 done")
	_board.close()
	assert_true(_player.finished_jobs.entries.is_empty(), "seen")
	assert_eq(_lines()[0], "heading Under way")


func test_messages_play_until_heard() -> void:
	var messages: MessageLog = _ship.messages
	var selin: NpcProfile = NpcProfile.find(&"councillor")
	var kade: NpcProfile = NpcProfile.find(&"depot_master")
	messages.received.append(ReceivedMessage.calling(selin, 0))
	messages.received.append(ReceivedMessage.calling(kade, 1))
	_board.set_tab(QuestBoardStation.Tab.MESSAGES)
	assert_eq(_lines(), ["message " + kade.calls[1], "message " + selin.calls[0]] as Array[String])
	assert_eq(_board.entries[0].note, "Kade", "who left it")
	var marker := _board.get_node("UnheardMarker") as Node3D
	assert_true(marker.visible, "two unheard")
	_board.open(_player)
	await wait_process_frames(2)
	var card := _board.card_menu as QuestBoardCard
	assert_eq(_board.entry_of(_board.selected).received, messages.received[1], "the newest")
	assert_eq(card.get_texts()[0], "Kade")
	assert_eq(card.get_texts()[3], kade.calls[1])
	assert_eq(card.get_action().text, "Play")
	assert_true(card.press_primary())
	assert_eq(_board.speaker.playing_entry, messages.received[1])
	assert_eq(card.get_action().text, "Stop")
	card.press_primary()
	assert_null(_board.speaker.playing_entry, "stopped")
	assert_false(messages.received[1].heard, "not to the end")
	card.press_primary()
	_board.speaker._process(1000.0)
	assert_true(messages.received[1].heard, "played to the end")
	assert_null(_board.speaker.playing_entry)
	_board.update_list()
	assert_true(marker.visible, "Selin's still unheard")
	messages.hear(messages.received[0])
	_board.update_list()
	assert_false(marker.visible)
	_board.close()


func test_board_fits_in_every_language() -> void:
	var kinds: Array[Quest.Kind] = []
	for kind: Quest.Kind in [Quest.Kind.MAIN, Quest.Kind.SIDE, Quest.Kind.REQUEST]:
		kinds.append_array([kind, kind])
	var quests: Array[Quest] = _accept_quests(kinds)
	var widest: Quest = quests[1]
	# The most a step asks and pays: three goals, six ores short in the hold, every reward.
	var ores: Array[OreType] = OreCatalog.all().ores.slice(0, 6)
	var step: QuestStep = widest.steps[0]
	step.goals.clear()
	for ore: OreType in ores.slice(0, 3):
		var deliver := DeliverGoal.new()
		deliver.item = ore
		deliver.amount = 9999
		step.goals.append(deliver)
	for ore: OreType in ores:
		step.items[ore] = 999
	step.blueprint = load("res://game/weapons/types/brask/brask.tres") as WeaponType
	_ship.quests.progress.erase(widest.id)
	_finish(quests[5])
	_player.finished_jobs.add(FinishedJob.new(ARMOR, 8))
	for profile: NpcProfile in NpcProfile.all():
		for line: int in profile.calls.size():
			_ship.messages.received.append(ReceivedMessage.calling(profile, line))
	var screen := _board.screen.content as BoardScreen
	var layout := Vector2(_board.screen.size * _board.screen.pixels_per_meter)
	for locale: String in SettingsList.languages():
		TranslationServer.set_locale(locale)
		_board.open(_player)
		for tab: int in QuestBoardStation.Tab.size():
			_board.set_tab(tab)
			_board.show_done = true
			_board.update_list()
			await wait_process_frames(1)
			_assert_fits(screen, layout, "%s board, tab %d" % [locale, tab])
			_assert_card_fits(_board, "%s tab %d" % [locale, tab])
			for line: int in mini(_board.entries.size(), BoardScreen.LINES):
				if not _board.entries[line].is_selectable():
					assert_true(
						screen.line_fits(line), "%s %s" % [locale, _board.entries[line].title]
					)
			for i: int in _board.entries.size():
				if _board.entries[i].is_selectable():
					_board._select_entry(i)
					await wait_process_frames(1)
					_assert_card_fits(_board, "%s %s" % [locale, _board.entries[i].title])
		_board.close()


## Accepts a test quest per kind in `kinds` (ids q0, q1, ...; Brannik's), in that order.
func _accept_quests(kinds: Array[Quest.Kind]) -> Array[Quest]:
	var quests: Array[Quest] = []
	_ship.quests.catalog = QuestCatalog.new()
	for i: int in kinds.size():
		var quest: Quest = QUEST_LOG_TEST.make_quest(StringName("q%d" % i), &"quartermaster")
		quest.kind = kinds[i]
		quest.title = "Quest %d" % i
		_ship.quests.catalog.quests.append(quest)
		quests.append(quest)
	for quest: Quest in quests:
		_ship.quests.accept(quest, [_player])
	return quests


## Sets every step of `quest` handed in (it's done).
func _finish(quest: Quest) -> void:
	for step: QuestStep in quest.steps:
		_ship.quests.story.set_flag(quest.step_flag(step))
	_ship.quests.story.set_flag(quest.flag())


## The board's lines as "<kind> <title or quest id>".
func _lines() -> Array[String]:
	var lines: Array[String] = []
	for entry: BoardEntry in _board.entries:
		var kind: String = (BoardEntry.Kind.find_key(entry.kind) as String).to_lower()
		var named: String = String(entry.quest.id) if entry.quest else entry.title
		lines.append("%s %s" % [kind, named])
	return lines
