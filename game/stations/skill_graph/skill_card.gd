class_name SkillCard
extends StationCard
## The holo card of the `SkillStation`: the selected skill's name and what it does, its ranks as
## pips (like the MK pips), the next rank's cost per ore next to what the hold has of it (red where
## it's short), and "Learn". A rank under way fills its pip, says the time left and offers "Stop"
## (pressed twice, the whole cost back). A skill whose required skill isn't learned yet says which
## one to learn first, and while a mission is underway it says why nothing can be learned.

## The skill shown, or null.
var skill: Skill

@onready var _title: Label = %Title
@onready var _description: Label = %Description
@onready var _state: Label = %State
@onready var _pips: HBoxContainer = %Pips
@onready var _cost_row: HFlowContainer = %CostRow
@onready var _cost: ItemCost = %Cost
@onready var _time: Label = %Time
@onready var _status: Label = %Status
@onready var _learn: Button = %Learn
@onready var _close: Button = %Close


func _ready() -> void:
	_learn.pressed.connect(press_primary)
	_close.pressed.connect(_on_close_pressed)


func show_part(part: StationPart) -> void:
	var skill_station := station as SkillStation
	var shown := part.item as Skill if part else null
	if not shown or not skill_station or not skill_station.user:
		show_skill(null)
		return
	var hold: Dictionary[ItemType, float] = {}
	if skill_station.user:
		hold = skill_station.user.hold.items
	var skills: Skills = skill_station.user.skills
	var job: TimedJob = skills.get_job(shown)
	# The button keeps its state while a rank runs: switching it off and on again every frame
	# would drop a mouse click on it.
	show_skill(
		shown,
		skills.rank(shown),
		hold,
		skills.is_open(shown),
		skill_station.is_locked(),
		skill_station.can_stop(shown) if job else skill_station.can_learn(shown)
	)
	if job:
		show_job(
			job,
			Time.get_unix_time_from_system(),
			skill_station.can_stop(shown),
			skill_station.stop_press.is_armed(shown),
			skill_station.is_locked()
		)


## Shows `shown` at `rank` (null: nothing). `hold`: what the hold has; `open`: whether the skill it
## requires is learned; `locked`: whether a mission is underway; `can_learn`: whether its next rank
## can be learned right now.
func show_skill(
	shown: Skill,
	rank: int = 0,
	hold: Dictionary[ItemType, float] = {},
	open: bool = true,
	locked: bool = false,
	can_learn: bool = false
) -> void:
	skill = shown
	visible = shown != null
	if not shown:
		return
	_title.text = tr(shown.display_name)
	_description.text = tr(shown.description)
	var next: SkillRank = shown.rank_after(rank)
	if not open:
		_state.text = tr("Learn %s first") % tr(shown.requires.display_name)
	elif not next:
		_state.text = tr("Learned")
	elif shown.max_rank() > 1:
		_state.text = tr("Rank %d of %d") % [rank, shown.max_rank()]
	else:
		_state.text = tr("Not learned yet")
	_pips.visible = shown.max_rank() > 1
	UpgradeCard.show_pips(_pips, rank, shown.max_rank())
	var cost: Dictionary[ItemType, int] = {}
	if next:
		cost = next.cost
	_cost_row.visible = next != null
	_cost.show_cost(cost, hold)
	# Only what can be started says how long it takes (the card keeps its height).
	_time.visible = next != null and open and not locked
	if next:
		_time.text = tr("Takes %s") % FurnaceCard.duration_text(next.seconds)
	_status.visible = locked
	_status.text = tr("Locked until everyone is back aboard.")
	_learn.text = tr("Learn") if next else tr("Learned")
	_learn.disabled = not can_learn
	for dimmed: CanvasItem in [_title, _description, _pips, _cost_row]:
		dimmed.modulate = Color.WHITE if open else CardPalette.DIMMED


## Shows the rank `job` under way (after `show_skill`) at `now` (Unix seconds): its pip filling,
## the time left and "Stop" (`can_stop`: whether it can be stopped now; `armed`: whether "Stop" was
## pressed once; `locked`: whether a mission is underway).
func show_job(
	job: TimedJob, now: float, can_stop: bool = true, armed: bool = false, locked: bool = false
) -> void:
	if skill and skill.max_rank() > 1:
		_state.text = tr("Rank %d under way") % job.level
		UpgradeCard.show_pips(_pips, job.level - 1, skill.max_rank(), 99, job.progress(now))
	else:
		_state.text = tr("Learning")
	_cost_row.visible = false
	_time.visible = true
	_time.text = tr("Time left: %s") % FurnaceCard.duration_text(job.time_left(now))
	_status.visible = locked or armed
	if locked:
		_status.text = tr("Locked until everyone is back aboard.")
	elif armed:
		_status.text = tr("Stop? The whole cost goes back to the hold.")
	_learn.text = tr("Stop for sure") if armed else tr("Stop")
	_learn.disabled = not can_stop


func press_primary() -> bool:
	var skill_station := station as SkillStation
	if not skill_station:
		return false
	if skill_station.user and skill_station.user.skills.is_running(skill):
		return skill_station.stop(skill)
	return skill_station.learn(skill)


## The line saying how long the next rank takes, or the time left of one under way (for tests).
func get_time() -> Label:
	return _time


## The learn button (for tests and probes).
func get_learn_button() -> Button:
	return _learn


func _on_close_pressed() -> void:
	if station:
		station.close()
