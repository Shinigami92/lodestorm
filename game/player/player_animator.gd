class_name PlayerAnimator
extends AnimationTree
## Plays the suit model's clips (assets/player/player.glb): the legs blend between "Idle" and
## the four run directions by the velocity relative to where the player faces, the upper body
## holds the weapon while it's out, as the weapon's `hold` says (`WeaponType.Hold`: the "Aim" pose,
## a blade, a hammer, a braced tool, a gauntlet, a shield), and "Die" plays once on death and
## holds. A melee attack plays its motion over the hold (`play_motion`: a slash, an overhead blow, a
## thrust, a punch, a bash), its stroke fitted to the attack's time. A braced tool leans in and
## shakes with its motor (`shake`), and stays out at the thrust's end while it drills
## (`drilling`); a gauntlet draws back as its punch charges (`shake`). All clips but "Die" and the
## motions loop (set here, so the import settings stay default).

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
## The upper body's pose per `WeaponType.Hold`.
const HOLD_CLIPS: Array[StringName] = [
	&"Aim", &"ReadyBlade", &"ReadyHammer", &"Brace", &"ReadyFist", &"ReadyShield"
]
## The clip per `Weapon.Motion`.
const MOTION_CLIPS: Array[StringName] = [
	&"Slash", &"SlashBack", &"Overhead", &"Thrust", &"Punch", &"Bash"
]
## The layers over the hold, blended in by the weapon's state: a braced tool cutting and drilling,
## a gauntlet drawn back for a punch.
const LAYER_CLIPS: Array[StringName] = [&"Cut", &"Drill", &"Cock"]
## Seconds the motions' strokes are authored at (ATTACK_STROKE in player_build.py).
const MOTION_STROKE: float = 0.2
## Seconds a motion blends in over the hold, and back out at its end.
const MOTION_FADE_IN: float = 0.05
const MOTION_FADE_OUT: float = 0.2

## Speed the run clips are authored at (RUN_SPEED in assets/player/source/player_build.py), in m/s.
@export var run_speed: float = 6.0
## Seconds to blend the aim pose in and out, and between holds.
@export var aim_blend_time: float = 0.15
## Seconds to go out to drilling and back.
@export var drill_blend_time: float = 0.12

## Velocity relative to the body, in m/s: x to the right, y forward.
var local_velocity: Vector2 = Vector2.ZERO
## Whether the upper body holds the weapon.
var aiming: bool = true
## How it holds the weapon.
var hold: WeaponType.Hold = WeaponType.Hold.AIM:
	set(value):
		if value != hold:
			hold = value
			set(&"parameters/hold/transition_request", HOLD_CLIPS[hold])
## How hard a braced tool's motor runs, 0 to 1: the body leans in and the arms shake; for a
## gauntlet, how far its punch has charged: the arm draws back.
var shake: float = 0.0
## Whether a braced tool drills into a target: the arms stay out.
var drilling: bool = false
## Plays "Die" (from its start) and holds its last frame until set back to false.
var dead: bool = false:
	set(value):
		if value != dead:
			dead = value
			set(&"parameters/life/transition_request", &"dead" if dead else &"alive")

var _aim_amount: float = 1.0
var _drill_amount: float = 0.0


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

	var holds := AnimationNodeTransition.new()
	holds.xfade_time = aim_blend_time
	holds.input_count = HOLD_CLIPS.size()
	for i: int in HOLD_CLIPS.size():
		holds.set_input_name(i, HOLD_CLIPS[i])

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
	blend.add_node(&"hold", holds)
	for i: int in HOLD_CLIPS.size():
		blend.add_node(HOLD_CLIPS[i], _clip(player, HOLD_CLIPS[i]))
		blend.connect_node(&"hold", i, HOLD_CLIPS[i])
	var upper: StringName = &"hold"
	for layer: StringName in LAYER_CLIPS:
		var mix := StringName(layer.to_lower())
		blend.add_node(mix, AnimationNodeBlend2.new())
		blend.add_node(layer, _clip(player, layer))
		blend.connect_node(mix, 0, upper)
		blend.connect_node(mix, 1, layer)
		upper = mix
	for clip: StringName in MOTION_CLIPS:
		var shot := AnimationNodeOneShot.new()
		shot.fadein_time = MOTION_FADE_IN
		shot.fadeout_time = MOTION_FADE_OUT
		var speed := StringName("%s_speed" % clip)
		var motion := StringName(clip.to_lower())
		blend.add_node(motion, shot)
		blend.add_node(speed, AnimationNodeTimeScale.new())
		blend.add_node(clip, _clip(player, clip, false))
		blend.connect_node(speed, 0, clip)
		blend.connect_node(motion, 0, upper)
		blend.connect_node(motion, 1, speed)
		upper = motion
	blend.add_node(&"aim", aim)
	blend.add_node(&"die", _clip(player, &"Die", false))
	blend.add_node(&"life", life)
	blend.connect_node(&"move_speed", 0, &"move")
	blend.connect_node(&"aim", 0, &"move_speed")
	blend.connect_node(&"aim", 1, upper)
	blend.connect_node(&"life", 0, &"aim")
	blend.connect_node(&"life", 1, &"die")
	blend.connect_node(&"output", 0, &"life")
	tree_root = blend
	active = true
	set(&"parameters/hold/transition_request", HOLD_CLIPS[hold])


## Plays `motion` over the hold, its stroke taking `duration` seconds; ends the one under way.
func play_motion(motion: Weapon.Motion, duration: float) -> void:
	if not tree_root:
		return
	for i: int in MOTION_CLIPS.size():
		var path := "parameters/%s/request" % MOTION_CLIPS[i].to_lower()
		if i != motion and get("parameters/%s/active" % MOTION_CLIPS[i].to_lower()):
			set(path, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
	var clip: StringName = MOTION_CLIPS[motion]
	set("parameters/%s_speed/scale" % clip, MOTION_STROKE / maxf(duration, 0.01))
	set("parameters/%s/request" % clip.to_lower(), AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func _process(delta: float) -> void:
	if not tree_root:
		return
	set(&"parameters/move/blend_position", local_velocity / run_speed)
	var speed: float = local_velocity.length()
	set(&"parameters/move_speed/scale", maxf(speed / run_speed, MIN_TIME_SCALE))
	_aim_amount = move_toward(_aim_amount, 1.0 if aiming else 0.0, delta / aim_blend_time)
	set(&"parameters/aim/blend_amount", _aim_amount)
	var braced: bool = hold == WeaponType.Hold.BRACE
	set(&"parameters/cut/blend_amount", clampf(shake, 0.0, 1.0) if braced else 0.0)
	var out: float = 1.0 if drilling and braced else 0.0
	_drill_amount = move_toward(_drill_amount, out, delta / drill_blend_time)
	set(&"parameters/drill/blend_amount", _drill_amount)
	var fist: bool = hold == WeaponType.Hold.FIST
	set(&"parameters/cock/blend_amount", clampf(shake, 0.0, 1.0) if fist else 0.0)


func _clip(player: AnimationPlayer, clip: StringName, loop: bool = true) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = clip
	node.use_custom_timeline = true
	node.timeline_length = player.get_animation(clip).length
	node.stretch_time_scale = false
	node.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	return node
