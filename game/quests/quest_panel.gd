class_name QuestPanel
extends VBoxContainer
## A quest on a holo card (the talk card's offer and hand-in): what its step asks, its goals (with
## how far they are, once accepted), what the hold pays of the rest at a hand-in (red where it's
## short), and what it pays: ores and alloys as badges, a blueprint and reputation as lines below.

var _text: Label
var _goals: VBoxContainer
var _cost_title: Label
var _cost: ItemCost
var _rewards_title: Label
var _rewards: BadgeRow
var _extras: Label


func _init() -> void:
	add_theme_constant_override(&"separation", 8)
	_text = _label(&"CardText", self)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_goals = VBoxContainer.new()
	_goals.name = "Goals"
	add_child(_goals)
	_cost_title = _label(&"CardNote", self)
	_cost = ItemCost.new()
	add_child(_cost)
	_rewards_title = _label(&"CardNote", self)
	_rewards = BadgeRow.new()
	add_child(_rewards)
	_extras = _label(&"CardText", self)


## Shows `quest`: `offering` it (its first step and everything it pays), else its active step in
## `quests` (how far its goals are, what `hold` pays of the rest, what the step pays).
func show_quest(quest: Quest, quests: QuestLog, hold: PlayerHold, offering: bool) -> void:
	var step: QuestStep = (
		quest.steps[0] if offering and not quest.steps.is_empty() else quests.current_step(quest)
	)
	_text.text = tr(step.text) if step else ""
	_cost_title.text = tr("From your hold")
	_rewards_title.text = tr("Rewards")
	_show_goals(step, quest, quests, offering)
	var missing: Dictionary[ItemType, int] = (
		{} as Dictionary[ItemType, int] if offering else quests.missing(quest)
	)
	_cost_title.visible = not missing.is_empty()
	_cost.visible = not missing.is_empty()
	var stored: Dictionary[ItemType, float] = {}
	for item: ItemType in missing:
		stored[item] = hold.amount(item) if hold else 0.0
	_cost.show_cost(missing, stored)
	var paid: Array[QuestStep] = quest.steps if offering else ([step] as Array[QuestStep])
	_show_rewards(paid.filter(func(paying: QuestStep) -> bool: return paying != null))


## The goal rows shown (for tests and probes): "<goal>  <progress>".
func get_goal_texts() -> Array[String]:
	var texts: Array[String] = []
	for row: Node in _goals.get_children():
		texts.append((row as Label).text)
	return texts


## The lines below the reward badges (for tests and probes).
func get_extras() -> String:
	return _extras.text if _extras.visible else ""


func _show_goals(step: QuestStep, quest: Quest, quests: QuestLog, offering: bool) -> void:
	for row: Node in _goals.get_children():
		row.free()
	if not step:
		return
	for i: int in step.goals.size():
		var goal: QuestGoal = step.goals[i]
		var row: Label = _label(&"CardText", _goals)
		var done: float = quests.goal_progress(quest, i)
		row.text = "•  " + goal.describe()
		if goal.target() > 1.0:
			var amount: int = roundi(goal.target())
			row.text += "  " + ("%d" % amount if offering else "%d / %d" % [floori(done), amount])
		if not offering and done >= goal.target():
			row.text += "  " + tr("Done")
			row.add_theme_color_override(&"font_color", CardPalette.GOOD)


## What `paying` (its steps) pays together.
func _show_rewards(paying: Array) -> void:
	var items: Dictionary[ItemType, int] = {}
	var extras: Array[String] = []
	var trust: int = 0
	for step: QuestStep in paying:
		for item: ItemType in step.items:
			items[item] = items.get(item, 0) + step.items[item]
		if step.blueprint:
			extras.append(tr("Blueprint: %s") % step.blueprint.display_name)
		trust += step.reputation
	if trust > 0:
		extras.append(tr("Reputation +%d") % trust)
	_rewards.show_items(items.keys(), items)
	_rewards.visible = not items.is_empty()
	_extras.text = "\n".join(extras)
	_extras.visible = not extras.is_empty()
	_rewards_title.visible = _rewards.visible or _extras.visible


## A label of the card's `variation`, added last to `parent` (its texts are translated already).
func _label(variation: StringName, parent: Node) -> Label:
	var label := Label.new()
	label.theme_type_variation = variation
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	parent.add_child(label)
	return label
