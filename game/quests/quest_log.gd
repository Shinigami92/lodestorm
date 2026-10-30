class_name QuestLog
extends Resource
## The ship's quests (the host's, saved with the ship, see docs/planned/quests.md): which ones are
## accepted (in that order), how far the active step's goals are, and the reputation with each
## NPC. Which step is active follows from the story's flags: the first one not handed in yet
## (`Quest.step_flag`). Hauls brought aboard pay into active deliveries after the heat shield's
## plate (`take_from`), what a run brought aboard counts for mining (`count_hauled`), and what's
## built counts once a player has it (`check_built`). A step is handed in at its NPC (`hand_in`):
## what's still missing of its deliveries comes from the hold of whoever hands it in, its rewards
## go to everyone there. One quest is tracked (`tracked`, the session's: its markers come later):
## accepting one tracks it while none is, and once the tracked one is done the main quest is.

## The most reputation with one NPC (five pips on their name plate).
const REPUTATION_MAX: int = 5
const CATALOG: QuestCatalog = preload("res://game/quests/quests.tres")

## Every quest there is.
var catalog: QuestCatalog = CATALOG
## The story the steps' flags go into (the ship's).
var story := Story.new()
## The quests accepted, by id, in the order they were (deliveries fill in this order); done ones
## stay.
var accepted: Array[StringName] = []
## Per accepted quest not done yet (its id): its active step's progress, one number per goal.
var progress: Dictionary[StringName, PackedFloat64Array] = {}
## Reputation per NPC (their `NpcProfile.id`), 0–`REPUTATION_MAX`.
var reputation: Dictionary[StringName, int] = {}
## The quest the session follows (its id), an accepted one not done yet; empty: none.
var tracked: StringName = &""

## What this run brought aboard so far (units per ore), for mining goals.
var _run: Dictionary[OreType, float] = {}


## Whether `quest` is accepted (done or not).
func is_accepted(quest: Quest) -> bool:
	return quest.id in accepted


## The quest tracked (`tracked`), or null.
func get_tracked() -> Quest:
	return catalog.find(tracked) if not tracked.is_empty() else null


## Tracks `quest` (accepted, not done). Returns whether it does.
func track(quest: Quest) -> bool:
	if not quest or not current_step(quest):
		return false
	if tracked != quest.id:
		tracked = quest.id
		emit_changed()
	return true


## Whether `quest`'s last step is handed in.
func is_done(quest: Quest) -> bool:
	return story.is_set(quest.flag())


## The step of `quest` being done now, or null (not accepted, or done).
func current_step(quest: Quest) -> QuestStep:
	if not is_accepted(quest):
		return null
	for step: QuestStep in quest.steps:
		if not story.is_set(quest.step_flag(step)):
			return step
	return null


## The quests `npc` (an `NpcProfile.id`) offers now: open (`Quest.is_open`, the ship reaching
## `reaches`) and not accepted yet.
func offered_by(npc: StringName, reaches: Array[StringName]) -> Array[Quest]:
	var offered: Array[Quest] = []
	for quest: Quest in catalog.quests:
		if quest.giver != npc or is_accepted(quest):
			continue
		var trust: int = reputation.get(npc, 0)
		if quest.is_open(story, reaches, trust):
			offered.append(quest)
	return offered


## The quests whose active step is handed in at `npc` (an `NpcProfile.id`), in the order they were
## accepted.
func steps_at(npc: StringName) -> Array[Quest]:
	var waiting: Array[Quest] = []
	for quest: Quest in _active():
		if quest.hand_in_npc(current_step(quest)) == npc:
			waiting.append(quest)
	return waiting


## The quest `topic` belongs to: offered (its `offer`) or active (its step's `hand_in`); else null.
func quest_for(topic: Topic) -> Quest:
	for quest: Quest in catalog.quests:
		if quest.offer == topic and not is_accepted(quest):
			return quest
		var step: QuestStep = current_step(quest)
		if step and step.hand_in == topic:
			return quest
	return null


## How far goal `index` of `quest`'s active step is (0 without one).
func goal_progress(quest: Quest, index: int) -> float:
	var goals: PackedFloat64Array = progress.get(quest.id, PackedFloat64Array())
	return goals[index] if index < goals.size() else 0.0


## What's still missing of the active step's deliveries of `quest` (units per item): paid from the
## hold at the hand-in.
func missing(quest: Quest) -> Dictionary[ItemType, int]:
	var still: Dictionary[ItemType, int] = {}
	var step: QuestStep = current_step(quest)
	if not step:
		return still
	for i: int in step.goals.size():
		var left: Dictionary[ItemType, int] = step.goals[i].missing(goal_progress(quest, i))
		for item: ItemType in left:
			still[item] = still.get(item, 0) + left[item]
	return still


## Whether `quest`'s active step can be handed in by a player with `hold`: every goal done, the
## deliveries' rest in the hold.
func can_hand_in(quest: Quest, hold: PlayerHold) -> bool:
	var step: QuestStep = current_step(quest)
	if not step:
		return false
	for i: int in step.goals.size():
		var goal: QuestGoal = step.goals[i]
		var so_far: float = goal_progress(quest, i)
		# A delivery's rest can come from the hold; nothing else can.
		if so_far < goal.target() and goal.missing(so_far).is_empty():
			return false
	var still: Dictionary[ItemType, int] = missing(quest)
	return still.keys().all(func(item: ItemType) -> bool: return hold.amount(item) >= still[item])


## Accepts `quest` while it's offered, starting its first step (what `players` built before
## counts). Returns whether it did.
func accept(quest: Quest, players: Array[Player]) -> bool:
	if is_accepted(quest) or quest.steps.is_empty():
		return false
	accepted.append(quest.id)
	_start_step(quest, players)
	if tracked.is_empty():
		tracked = quest.id
	emit_changed()
	return true


## Hands in `quest`'s active step: what's missing comes from `payer`'s hold, the step's flag is set,
## its ores, alloys and blueprint go to every one of `players` (the session) and its reputation to
## the giver; then the next step starts, or the quest is done (its flag). Returns whether it did.
func hand_in(quest: Quest, payer: Player, players: Array[Player]) -> bool:
	var step: QuestStep = current_step(quest)
	if not step or not can_hand_in(quest, payer.hold):
		return false
	var still: Dictionary[ItemType, int] = missing(quest)
	for item: ItemType in still:
		payer.hold.take(item, still[item])
	for player: Player in players:
		for item: ItemType in step.items:
			player.hold.add(item, step.items[item])
		if step.blueprint:
			player.arsenal.learn(step.blueprint)
	if step.reputation > 0:
		var trust: int = reputation.get(quest.giver, 0)
		reputation[quest.giver] = mini(trust + step.reputation, REPUTATION_MAX)
	progress.erase(quest.id)
	story.set_flag(quest.step_flag(step))
	if current_step(quest):
		_start_step(quest, players)
	else:
		story.set_flag(quest.flag())
		if tracked == quest.id:
			tracked = _main_quest()
	emit_changed()
	return true


## Takes what the active deliveries still need of `haul` (units per ore, brought aboard, after the
## heat shield's plate), in the order the quests were accepted. Returns what they took.
func take_from(haul: Dictionary[OreType, float]) -> Dictionary[OreType, float]:
	var left: Dictionary[OreType, float] = haul.duplicate()
	var taken: Dictionary[OreType, float] = {}
	for quest: Quest in _active():
		var goals: Array[QuestGoal] = current_step(quest).goals
		for i: int in goals.size():
			var took: Dictionary[OreType, float] = goals[i].take_from(left, goal_progress(quest, i))
			for ore: OreType in took:
				left[ore] -= took[ore]
				taken[ore] = taken.get(ore, 0.0) + took[ore]
				_set_progress(quest, i, goal_progress(quest, i) + took[ore])
	if not taken.is_empty():
		emit_changed()
	return taken


## Starts counting a new run for the mining goals.
func start_run() -> void:
	_run.clear()


## Counts `amount` of `ore` brought aboard this run towards the active mining goals.
func count_hauled(ore: OreType, amount: float) -> void:
	_run[ore] = _run.get(ore, 0.0) + amount
	_update_goals(
		func(goal: QuestGoal, so_far: float) -> float: return goal.count_run(_run, so_far)
	)


## Counts what `players` (the session) have built towards the active build goals.
func check_built(players: Array[Player]) -> void:
	_update_goals(
		func(goal: QuestGoal, so_far: float) -> float:
			return goal.target() if goal.is_built(players) else so_far
	)


## What's saved: the quests accepted, the active steps' progress, the reputation and the quest
## tracked.
func save_data() -> Dictionary:
	var saved_progress: Dictionary = {}
	for id: StringName in progress:
		saved_progress[String(id)] = Array(progress[id])
	var saved_reputation: Dictionary = {}
	for npc: StringName in reputation:
		saved_reputation[String(npc)] = reputation[npc]
	return {
		"accepted": accepted.map(func(id: StringName) -> String: return String(id)),
		"progress": saved_progress,
		"reputation": saved_reputation,
		"tracked": String(tracked),
	}


## Reads what a save has (`save_data`), without quests that aren't in the `catalog` any more.
## Returns whether all of it read.
func load_data(saved: Variant) -> bool:
	if saved == null:
		return true
	if not saved is Dictionary:
		return SaveData.skipped("quests", saved)
	var data: Dictionary = saved
	var complete: bool = true
	var saved_accepted: Variant = data.get("accepted", [])
	for id: Variant in saved_accepted if saved_accepted is Array else []:
		if id is String and catalog.find(StringName(id as String)):
			accepted.append(StringName(id as String))
		else:
			complete = SaveData.skipped("quest", id)
	var saved_progress: Variant = data.get("progress", {})
	for id: Variant in saved_progress if saved_progress is Dictionary else {}:
		var goals: Variant = (saved_progress as Dictionary)[id]
		if id is String and StringName(id as String) in accepted and goals is Array:
			progress[StringName(id as String)] = _numbers(goals as Array)
		else:
			complete = SaveData.skipped("quest progress", id)
	var saved_reputation: Variant = data.get("reputation", {})
	for npc: Variant in saved_reputation if saved_reputation is Dictionary else {}:
		var trust: float = SaveData.number((saved_reputation as Dictionary)[npc], -1.0)
		if npc is String and trust >= 0.0:
			reputation[StringName(npc as String)] = mini(int(trust), REPUTATION_MAX)
		else:
			complete = SaveData.skipped("reputation", npc)
	var saved_tracked: Variant = data.get("tracked", "")
	var tracking: String = saved_tracked if saved_tracked is String else "?"
	if not tracking.is_empty() and not track(catalog.find(StringName(tracking))):
		complete = SaveData.skipped("tracked quest", saved_tracked)
	emit_changed()
	return complete


## The accepted quests with an active step, in the order they were accepted; their progress has
## a number per goal.
func _active() -> Array[Quest]:
	var active: Array[Quest] = []
	for id: StringName in accepted:
		var quest: Quest = catalog.find(id)
		var step: QuestStep = current_step(quest) if quest else null
		if not step:
			continue
		var goals: PackedFloat64Array = progress.get(id, PackedFloat64Array())
		if goals.size() != step.goals.size():
			goals.resize(step.goals.size())
			progress[id] = goals
		active.append(quest)
	return active


## The first main quest accepted with a step to do (its id), else empty.
func _main_quest() -> StringName:
	for quest: Quest in _active():
		if quest.kind == Quest.Kind.MAIN:
			return quest.id
	return &""


## Starts `quest`'s active step: nothing done yet, besides what `players` built before.
func _start_step(quest: Quest, players: Array[Player]) -> void:
	var goals := PackedFloat64Array()
	goals.resize(current_step(quest).goals.size())
	progress[quest.id] = goals
	check_built(players)


## Sets every active goal's progress to what `counted` (goal, progress so far) says.
func _update_goals(counted: Callable) -> void:
	var changes: bool = false
	for quest: Quest in _active():
		var goals: Array[QuestGoal] = current_step(quest).goals
		for i: int in goals.size():
			var so_far: float = goal_progress(quest, i)
			var now: float = counted.call(goals[i], so_far)
			if not is_equal_approx(now, so_far):
				_set_progress(quest, i, now)
				changes = true
	if changes:
		emit_changed()


## Sets goal `index` of `quest`'s active step to `value`.
func _set_progress(quest: Quest, index: int, value: float) -> void:
	var goals: PackedFloat64Array = progress[quest.id]
	goals[index] = value
	progress[quest.id] = goals


## The numbers of a saved list (others as 0).
static func _numbers(saved: Array) -> PackedFloat64Array:
	var numbers := PackedFloat64Array()
	for value: Variant in saved:
		numbers.append(maxf(SaveData.number(value, 0.0), 0.0))
	return numbers
