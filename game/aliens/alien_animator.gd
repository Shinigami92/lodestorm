class_name AlienAnimator
extends AnimationTree
## Plays a four-legged alien model's clips (e.g. assets/aliens/swarmer/swarmer.glb): the body
## blends from "Idle" to "Run" with the speed (the legs come from `AlienLegs`), "Attack" plays
## once over it per attack, and "Die" plays once on death and holds. Loops are set here, so the
## import settings stay default.

## The slowest the run clip plays (a share of its speed).
const MIN_TIME_SCALE: float = 0.5

## Speed at which the body moves like in the "Run" clip, in m/s.
@export var run_speed: float = 4.5

## Horizontal speed of the alien, in m/s.
var speed: float = 0.0
## Plays "Die" (from its start) and holds its last frame.
var dead: bool = false:
	set(value):
		if value != dead:
			dead = value
			set(&"parameters/life/transition_request", &"dead" if dead else &"alive")


## Builds the blend tree for `model` (an instance of the alien's .glb with its AnimationPlayer).
func setup(model: Node3D) -> void:
	var player: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	root_node = get_path_to(model)
	anim_player = get_path_to(player)

	var life := AnimationNodeTransition.new()
	life.xfade_time = 0.1
	life.input_count = 2
	life.set_input_name(0, "alive")
	life.set_input_name(1, "dead")
	life.set_input_reset(1, true)

	var strike := AnimationNodeOneShot.new()
	strike.fadein_time = 0.05
	strike.fadeout_time = 0.15

	var blend := AnimationNodeBlendTree.new()
	blend.add_node(&"idle", _clip(player, &"Idle"))
	blend.add_node(&"run", _clip(player, &"Run"))
	blend.add_node(&"run_speed", AnimationNodeTimeScale.new())
	blend.add_node(&"move", AnimationNodeBlend2.new())
	blend.add_node(&"attack_clip", _clip(player, &"Attack", false))
	blend.add_node(&"attack", strike)
	blend.add_node(&"die", _clip(player, &"Die", false))
	blend.add_node(&"life", life)
	blend.connect_node(&"run_speed", 0, &"run")
	blend.connect_node(&"move", 0, &"idle")
	blend.connect_node(&"move", 1, &"run_speed")
	blend.connect_node(&"attack", 0, &"move")
	blend.connect_node(&"attack", 1, &"attack_clip")
	blend.connect_node(&"life", 0, &"attack")
	blend.connect_node(&"life", 1, &"die")
	blend.connect_node(&"output", 0, &"life")
	tree_root = blend
	active = true


## Plays the attack once (from its start).
func attack() -> void:
	if tree_root:
		set(&"parameters/attack/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Breaks off the attack clip (a stagger).
func stop_attack() -> void:
	if tree_root:
		set(&"parameters/attack/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)


func _process(_delta: float) -> void:
	if not tree_root:
		return
	var amount: float = clampf(speed / run_speed, 0.0, 1.0)
	set(&"parameters/move/blend_amount", amount)
	set(&"parameters/run_speed/scale", maxf(speed / run_speed, MIN_TIME_SCALE))


func _clip(player: AnimationPlayer, clip: StringName, loop: bool = true) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = clip
	node.use_custom_timeline = true
	node.timeline_length = player.get_animation(clip).length
	node.stretch_time_scale = false
	node.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	return node
