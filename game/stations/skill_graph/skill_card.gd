class_name SkillCard
extends StationCard
## The holo card of the `SkillStation`: the selected skill's name and what it does, its ranks as
## pips (like the MK pips), the next rank's cost per ore next to what the hold has of it (red where
## it's short), and "Learn". A skill whose required skill isn't learned yet says which one to learn
## first, and while a mission is underway it says why nothing can be learned.

## The skill shown, or null.
var skill: Skill

@onready var _title: Label = %Title
@onready var _description: Label = %Description
@onready var _state: Label = %State
@onready var _pips: HBoxContainer = %Pips
@onready var _cost_row: HFlowContainer = %CostRow
@onready var _cost: OreCost = %Cost
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
	var hold: Dictionary[OreType, float] = {}
	if skill_station.ship:
		hold = skill_station.ship.hold
	var skills: Skills = skill_station.user.skills
	show_skill(
		shown,
		skills.rank(shown),
		hold,
		skills.is_open(shown),
		skill_station.is_locked(),
		skill_station.can_learn(shown)
	)


## Shows `shown` at `rank` (null: nothing). `hold`: what the hold has; `open`: whether the skill it
## requires is learned; `locked`: whether a mission is underway; `can_learn`: whether its next rank
## can be learned right now.
func show_skill(
	shown: Skill,
	rank: int = 0,
	hold: Dictionary[OreType, float] = {},
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
	var cost: Dictionary[OreType, int] = {}
	if next:
		cost = next.cost
	_cost_row.visible = next != null
	_cost.show_cost(cost, hold)
	_status.visible = locked
	_status.text = tr("Locked until everyone is back aboard.")
	_learn.text = tr("Learn") if next else tr("Learned")
	_learn.disabled = not can_learn
	for dimmed: CanvasItem in [_title, _description, _pips, _cost_row]:
		dimmed.modulate = Color.WHITE if open else UpgradeCard.LOCKED_COLOR


func press_primary() -> bool:
	var skill_station := station as SkillStation
	return skill_station != null and skill_station.learn(skill)


## The learn button (for tests and probes).
func get_learn_button() -> Button:
	return _learn


func _on_close_pressed() -> void:
	if station:
		station.close()
