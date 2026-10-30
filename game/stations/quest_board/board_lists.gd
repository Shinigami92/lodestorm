class_name BoardLists
extends RefCounted
## What the quest board lists (see `QuestBoardStation`), as `BoardEntry` lines: the quests in
## groups by kind (main, side, requests) and the done ones in a group that opens, or a player's
## jobs (the ones finished since they last looked on top, then the ones under way, soonest first).

const ARSENAL: Arsenal = preload("res://game/weapons/all_weapons.tres")
const STAR_SYSTEM: StarSystem = preload("res://game/world/star_system.tres")
## The quest groups in their order.
const GROUPS: Array[Quest.Kind] = [Quest.Kind.MAIN, Quest.Kind.SIDE, Quest.Kind.REQUEST]

## The weapon each weapon part belongs to (read once).
var _weapon_of: Dictionary[Upgrade, WeaponType] = {}


## The quests in `quests` (the ship's log): the active ones in their groups (in the order they
## were accepted), then the done ones' group, opened when `show_done` (newest first).
func quest_lines(quests: QuestLog, show_done: bool) -> Array[BoardEntry]:
	var lines: Array[BoardEntry] = []
	var done: Array[Quest] = []
	for kind: Quest.Kind in GROUPS:
		var heading := BoardEntry.new(BoardEntry.Kind.HEADING, group_name(kind))
		for id: StringName in quests.accepted:
			var quest: Quest = quests.catalog.find(id)
			if not quest or quest.kind != kind:
				continue
			if quests.is_done(quest):
				done.push_front(quest)
				continue
			if heading:
				lines.append(heading)
				heading = null
			lines.append(quest_line(quest, quests))
	if lines.is_empty():
		lines.append(BoardEntry.new(BoardEntry.Kind.NOTE, tr("No quests yet. Talk to people.")))
	if not done.is_empty():
		var group := BoardEntry.new(BoardEntry.Kind.DONE, tr("Done (%d)") % done.size(), "done")
		group.done = show_done
		lines.append(group)
		if show_done:
			for quest: Quest in done:
				lines.append(quest_line(quest, quests))
	return lines


## The line of `quest` (accepted) in `quests`.
func quest_line(quest: Quest, quests: QuestLog) -> BoardEntry:
	var line := BoardEntry.new(BoardEntry.Kind.QUEST, tr(quest.title), "quest:%s" % quest.id)
	line.quest = quest
	line.done = quests.is_done(quest)
	line.tracked = quests.tracked == quest.id
	line.note = npc_name(quest.giver)
	if line.done:
		line.note = tr("Done")
		return line
	var step: QuestStep = quests.current_step(quest)
	if step and not step.goals.is_empty():
		var sum: float = 0.0
		for i: int in step.goals.size():
			sum += clampf(quests.goal_progress(quest, i) / step.goals[i].target(), 0.0, 1.0)
		line.progress = sum / step.goals.size()
	return line


## `player`'s jobs at `now` (Unix seconds): the finished ones they haven't seen (newest first),
## then the ones under way (soonest done first).
func job_lines(player: Player, now: float) -> Array[BoardEntry]:
	var lines: Array[BoardEntry] = []
	if not player:
		return lines
	if not player.finished_jobs.entries.is_empty():
		lines.append(BoardEntry.new(BoardEntry.Kind.HEADING, tr("Finished")))
		for i: int in player.finished_jobs.entries.size():
			var job: FinishedJob = player.finished_jobs.entries[i]
			var line: BoardEntry = _job(job.item, job.level, job.miner, 0.0, "finished:%d" % i)
			line.note = tr("Done")
			line.status = _done_status(job.item, job.level)
			lines.append(line)
	var running: Array[BoardEntry] = _running(player, now)
	running.sort_custom(func(a: BoardEntry, b: BoardEntry) -> bool: return a.ends_at < b.ends_at)
	if not running.is_empty():
		lines.append(BoardEntry.new(BoardEntry.Kind.HEADING, tr("Under way")))
		for line: BoardEntry in running:
			line.note = OfferCard.duration_text(maxf(line.ends_at - now, 0.0))
		lines.append_array(running)
	if lines.is_empty():
		lines.append(BoardEntry.new(BoardEntry.Kind.NOTE, tr("Nothing under way.")))
	return lines


## The heading of the quests of `kind`.
func group_name(kind: Quest.Kind) -> String:
	match kind:
		Quest.Kind.MAIN:
			return tr("Main")
		Quest.Kind.REQUEST:
			return tr("Requests")
	return tr("Side")


## The name of the NPC with `id` (an `NpcProfile.id`), or the id itself when there's none.
func npc_name(id: StringName) -> String:
	var profile: NpcProfile = NpcProfile.find(id)
	if not profile:
		return String(id)
	return profile.display_name if not profile.display_name.is_empty() else tr(profile.role)


## Where the NPC with `id` is found: aboard, or the name of the station they live on.
func place_of(id: StringName) -> String:
	var profile: NpcProfile = NpcProfile.find(id)
	if not profile or profile.station.is_empty():
		return tr("aboard")
	var body: CelestialBody = STAR_SYSTEM.body_by_id(profile.station)
	return tr(body.display_name) if body else String(profile.station)


## The jobs under way of `player` (their `ends_at` set, not yet their note).
func _running(player: Player, now: float) -> Array[BoardEntry]:
	var lines: Array[BoardEntry] = []
	for upgrade: Upgrade in player.upgrades.jobs:
		lines.append(_timed(upgrade, player.upgrades.jobs[upgrade], 0))
	for skill: Skill in player.skills.jobs:
		lines.append(_timed(skill, player.skills.jobs[skill], 0))
	for miner: CraftedMiner in player.fleet.miners.values():
		if miner.build:
			lines.append(_timed(null, miner.build, miner.number))
		for upgrade: Upgrade in miner.upgrades.jobs:
			lines.append(_timed(upgrade, miner.upgrades.jobs[upgrade], miner.number))
	for slot: int in Refining.SLOTS:
		var batch: AlloyBatch = player.refining.get_batch(slot)
		if batch:
			var ends_at: float = now + batch.time_left(now)
			var line: BoardEntry = _job(batch.alloy, batch.bars, 0, ends_at, "batch:%d" % slot)
			line.status = tr("%d of %d bars done") % [batch.done, batch.bars]
			lines.append(line)
	return lines


## A line for `job` (a `TimedJob`) of `item` (null: building `miner`).
func _timed(item: Resource, job: TimedJob, miner: int) -> BoardEntry:
	var line: BoardEntry = _job(item, job.level, miner, job.started + job.seconds, "")
	line.status = _running_status(item, job.level)
	return line


## A job's line: its name with its level, when it's done (`ends_at`, 0: finished) and its `key`
## (empty: made from the job).
func _job(item: Resource, level: int, miner: int, ends_at: float, key: String) -> BoardEntry:
	var line := BoardEntry.new(BoardEntry.Kind.JOB, _job_title(item, level, miner))
	line.ends_at = ends_at
	if key.is_empty():
		key = "job:%s:%d" % [SaveData.uid_of(item) if item else "miner", miner]
	line.key = key
	return line


## What a job is called on the list, e.g. "Harl · Damage MK3", "M-02 · Drill MK2", "Dash 2",
## "Ferrite ×4" (bars) or "Miner M-03" (built).
func _job_title(item: Resource, level: int, miner: int) -> String:
	var plate: String = CraftedMiner.plate_of(miner) if miner > 0 else ""
	if item is Upgrade:
		var upgrade := item as Upgrade
		var owner: String = plate
		var weapon_type: WeaponType = _weapon(upgrade)
		if owner.is_empty() and weapon_type:
			owner = weapon_type.display_name
		var named: String = tr(upgrade.display_name)
		if not owner.is_empty():
			named = "%s · %s" % [owner, named]
		return "%s MK%d" % [named, level]
	if item is Skill:
		var skill := item as Skill
		var named_skill: String = tr(skill.display_name)
		return "%s %d" % [named_skill, level] if skill.max_rank() > 1 else named_skill
	if item is AlloyType:
		return "%s ×%d" % [(item as AlloyType).get_display_name(), level]
	return tr("Miner %s") % plate


## What a job under way says it does, e.g. "MK3 under way".
func _running_status(item: Resource, level: int) -> String:
	if item is Skill:
		return tr("Rank %d under way") % level
	if item is Upgrade:
		return tr("MK%d under way") % level
	return tr("Being built")


## What a finished job says, e.g. "MK3 done".
func _done_status(item: Resource, level: int) -> String:
	if item is Skill:
		return tr("Rank %d done") % level
	if item is Upgrade:
		return tr("MK%d done") % level
	if item is AlloyType:
		return tr("%d bars done") % level
	return tr("Built")


## The weapon `upgrade` is a part of, or null (the suit's armor).
func _weapon(upgrade: Upgrade) -> WeaponType:
	if _weapon_of.is_empty():
		for weapon_type: WeaponType in ARSENAL.weapons + ARSENAL.blueprints:
			for part: Upgrade in weapon_type.get_upgrades():
				_weapon_of[part] = weapon_type
	return _weapon_of.get(upgrade)
