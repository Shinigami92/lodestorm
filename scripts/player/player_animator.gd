class_name PlayerAnimator
extends AnimationTree
## Plays the suit model's clips (assets/player/player.glb): the legs blend between "Idle" and
## the four run directions by the velocity relative to where the player faces, the upper body
## holds the "Aim" pose while the weapon is out, and "Die" plays once on death and holds. All
## clips but "Die" loop (set here, so the import settings stay default).

const UPPER_BODY: Array[StringName] = [
	&"Spine",
	&"Chest",
	&"UpperChest",
	&"Neck",
	&"Head",
	&"LeftShoulder",
	&"LeftUpperArm",
	&"LeftLowerArm",
	&"LeftHand",
	&"RightShoulder",
	&"RightUpperArm",
	&"RightLowerArm",
	&"RightHand",
]
## The slowest the clips play (a share of their speed), so standing still still breathes.
const MIN_TIME_SCALE: float = 0.4

## Speed the run clips are authored at (RUN_SPEED in assets/player/source/player_build.py), in m/s.
@export var run_speed: float = 6.0
## Seconds to blend the aim pose in and out.
@export var aim_blend_time: float = 0.15

## Velocity relative to the body, in m/s: x to the right, y forward.
var local_velocity: Vector2 = Vector2.ZERO
## Whether the upper body holds the weapon.
var aiming: bool = true
## Plays "Die" (from its start) and holds its last frame until set back to false.
var dead: bool = false:
	set(value):
		if value != dead:
			dead = value
			set(&"parameters/life/transition_request", &"dead" if dead else &"alive")

var _aim_amount: float = 1.0


## Builds the blend tree for `model` (an instance of player.glb with its AnimationPlayer).
func setup(model: Node3D) -> void:
	var player: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	root_node = get_path_to(model)
	anim_player = get_path_to(player)

	var move := AnimationNodeBlendSpace2D.new()
	for point: Array in [
		[&"Idle", Vector2.ZERO],
		[&"Run", Vector2(0, 1)],
		[&"RunBack", Vector2(0, -1)],
		[&"StrafeLeft", Vector2(-1, 0)],
		[&"StrafeRight", Vector2(1, 0)],
	]:
		var clip: StringName = point[0]
		move.add_blend_point(_clip(player, clip), point[1] as Vector2, -1, clip)

	var aim := AnimationNodeBlend2.new()
	aim.filter_enabled = true
	var skeleton: Skeleton3D = model.find_child("Skeleton3D", true, false)
	var skeleton_path: String = str(model.get_path_to(skeleton))
	for bone: StringName in UPPER_BODY:
		aim.set_filter_path(NodePath("%s:%s" % [skeleton_path, bone]), true)

	var life := AnimationNodeTransition.new()
	life.xfade_time = 0.1
	life.input_count = 2
	life.set_input_name(0, "alive")
	life.set_input_name(1, "dead")
	life.set_input_reset(1, true)

	var blend := AnimationNodeBlendTree.new()
	blend.add_node(&"move", move)
	blend.add_node(&"move_speed", AnimationNodeTimeScale.new())
	blend.add_node(&"aim_pose", _clip(player, &"Aim"))
	blend.add_node(&"aim", aim)
	blend.add_node(&"die", _clip(player, &"Die", false))
	blend.add_node(&"life", life)
	blend.connect_node(&"move_speed", 0, &"move")
	blend.connect_node(&"aim", 0, &"move_speed")
	blend.connect_node(&"aim", 1, &"aim_pose")
	blend.connect_node(&"life", 0, &"aim")
	blend.connect_node(&"life", 1, &"die")
	blend.connect_node(&"output", 0, &"life")
	tree_root = blend
	active = true


func _process(delta: float) -> void:
	if not tree_root:
		return
	set(&"parameters/move/blend_position", local_velocity / run_speed)
	var scale: float = maxf(local_velocity.length() / run_speed, MIN_TIME_SCALE)
	set(&"parameters/move_speed/scale", scale)
	_aim_amount = move_toward(_aim_amount, 1.0 if aiming else 0.0, delta / aim_blend_time)
	set(&"parameters/aim/blend_amount", _aim_amount)


func _clip(player: AnimationPlayer, clip: StringName, loop: bool = true) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = clip
	node.use_custom_timeline = true
	node.timeline_length = player.get_animation(clip).length
	node.stretch_time_scale = false
	node.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	return node
