class_name NpcAnimator
extends AnimationTree
## Plays an NPC model's clips: "Idle" while standing, "Walk" while walking, sped up or slowed down
## to the walking speed (every person's model has both, the suit's too, see
## docs/technical/characters.md, People); both loop (set here, so the import settings stay default).
## While `sitting`, it blends into "Sit" (the suit's: the colonists; a model without it stays
## standing). While it `may_work` (and stands), it plays one of its `activities` now and then (once,
## over the standing: e.g. wiping the counter; never the same twice in a row; only the `allowed`
## ones where it stands), with a pause of `work_pause` seconds between them; when it may not any
## more (a player came close), the one under way fades out.

## Speed the walk clip is authored at (WALK_SPEED in tools/blender/humanoid.py), in m/s.
@export var walk_speed: float = 1.3
## Seconds to blend between standing and walking.
@export var walk_blend_time: float = 0.2
## The slowest the walk plays (a share of its speed).
@export var min_time_scale: float = 0.4
## Seconds of standing between two activities (at random within this range; values TBD
## (playtest)).
@export var work_pause: Vector2 = Vector2(3.0, 8.0)
## Seconds an activity fades in, and out at its end or when stopped.
@export var work_fade: float = 0.5
## Seconds to blend between standing and sitting (sitting down, getting up).
@export var sit_blend_time: float = 0.8

## How fast it walks forward, in m/s (0: standing).
var speed: float = 0.0
## Whether it may play its activities (no player close, not walking).
var may_work: bool = true
## Whether it sits (on a seat behind where it stands, see `can_sit`).
var sitting: bool = false
## The activities it may play where it stands now (e.g. tapping only at a console); empty: all.
var allowed: Array[StringName] = []

var _walk_amount: float = 0.0
## How far it sits: 0 standing, 1 sitting.
var _sit_amount: float = 0.0
## Whether the model has the "Sit" clip.
var _can_sit: bool = false
## The activity clips the model has.
var _activities: Array[StringName] = []
## Seconds left until the next activity may start.
var _pause_left: float = 0.0
## The activity played last (the next is another one).
var _last: StringName = &""


## Builds the blend tree for `model` (an imported person or the suit, with its AnimationPlayer) and
## its `activities` (the ones the model has clips for).
func setup(model: Node3D, activities: Array[StringName] = []) -> void:
	var player: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	root_node = get_path_to(model)
	anim_player = get_path_to(player)
	var blend := AnimationNodeBlendTree.new()
	blend.add_node(&"Idle", _clip(player, &"Idle"))
	blend.add_node(&"Walk", _clip(player, &"Walk"))
	blend.add_node(&"walk_speed", AnimationNodeTimeScale.new())
	blend.add_node(&"walk", AnimationNodeBlend2.new())
	blend.connect_node(&"walk_speed", 0, &"Walk")
	blend.connect_node(&"walk", 0, &"Idle")
	blend.connect_node(&"walk", 1, &"walk_speed")
	var below: StringName = &"walk"
	_can_sit = player.has_animation(&"Sit")
	if _can_sit:
		blend.add_node(&"Sit", _clip(player, &"Sit"))
		blend.add_node(&"sit", AnimationNodeBlend2.new())
		blend.connect_node(&"sit", 0, below)
		blend.connect_node(&"sit", 1, &"Sit")
		below = &"sit"
	_activities.clear()
	for activity: StringName in activities:
		if not player.has_animation(activity):
			push_warning('NpcAnimator: the model has no clip "%s"' % activity)
			continue
		_activities.append(activity)
		var shot := AnimationNodeOneShot.new()
		shot.fadein_time = work_fade
		shot.fadeout_time = work_fade
		var shot_node := _shot_name(activity)
		blend.add_node(activity, _clip(player, activity, false))
		blend.add_node(shot_node, shot)
		blend.connect_node(shot_node, 0, below)
		blend.connect_node(shot_node, 1, activity)
		below = shot_node
	blend.connect_node(&"output", 0, below)
	tree_root = blend
	active = true
	settle()
	_pause_left = randf_range(work_pause.x, work_pause.y)


## Whether the model can sit (has the "Sit" clip).
func can_sit() -> bool:
	return _can_sit


## Sits or stands at once, without blending (e.g. someone already sitting when the place loads).
func settle() -> void:
	_sit_amount = 1.0 if sitting and _can_sit else 0.0
	if _can_sit:
		set(&"parameters/sit/blend_amount", _sit_amount)


## How far it sits right now: 0 standing, 1 sitting (in between while sitting down or getting up).
func sit_amount() -> float:
	return _sit_amount


## The activity playing right now (empty: none).
func working() -> StringName:
	for activity: StringName in _activities:
		if get("parameters/%s/active" % _shot_name(activity)):
			return activity
	return &""


func _process(delta: float) -> void:
	if not tree_root:
		return
	var walking: bool = speed > 0.05
	_walk_amount = move_toward(_walk_amount, 1.0 if walking else 0.0, delta / walk_blend_time)
	set(&"parameters/walk/blend_amount", _walk_amount)
	set(&"parameters/walk_speed/scale", maxf(speed / walk_speed, min_time_scale))
	if _can_sit:
		var goal: float = 1.0 if sitting else 0.0
		_sit_amount = move_toward(_sit_amount, goal, delta / sit_blend_time)
		set(&"parameters/sit/blend_amount", _sit_amount)
	_work(delta)


## Starts an activity after the pause, stops the one under way when it may not work any more.
func _work(delta: float) -> void:
	if _activities.is_empty():
		return
	var current: StringName = working()
	if (
		not may_work
		or speed > 0.05
		or sitting
		or (not current.is_empty() and not _may_play(current))
	):
		if not current.is_empty():
			set(
				"parameters/%s/request" % _shot_name(current),
				AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT
			)
		_pause_left = maxf(_pause_left, work_pause.x)
		return
	if not current.is_empty():
		return
	_pause_left -= delta
	if _pause_left <= 0.0:
		var playable: Array[StringName] = _activities.filter(_may_play)
		var choices: Array[StringName] = playable.filter(
			func(a: StringName) -> bool: return a != _last or playable.size() == 1
		)
		_pause_left = randf_range(work_pause.x, work_pause.y)
		if choices.is_empty():
			return
		var next: StringName = choices.pick_random()
		_last = next
		set("parameters/%s/request" % _shot_name(next), AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Whether `activity` may play where it stands (see `allowed`).
func _may_play(activity: StringName) -> bool:
	return allowed.is_empty() or activity in allowed


func _shot_name(activity: StringName) -> StringName:
	return StringName("work_" + String(activity))


func _clip(player: AnimationPlayer, clip: StringName, loop: bool = true) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = clip
	node.use_custom_timeline = true
	node.timeline_length = player.get_animation(clip).length
	node.stretch_time_scale = false
	node.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	return node
