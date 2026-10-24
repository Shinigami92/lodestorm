class_name NpcAnimator
extends AnimationTree
## Plays an NPC model's clips: "Idle" while standing, "Walk" while walking, sped up or slowed down
## to the walking speed (every person's model has both, the suit's too, see docs/TECHNICAL.md,
## People). Both loop (set here, so the import settings stay default).

## Speed the walk clip is authored at (WALK_SPEED in tools/blender/humanoid.py), in m/s.
@export var walk_speed: float = 1.3
## Seconds to blend between standing and walking.
@export var walk_blend_time: float = 0.2
## The slowest the walk plays (a share of its speed).
@export var min_time_scale: float = 0.4

## How fast it walks forward, in m/s (0: standing).
var speed: float = 0.0

var _walk_amount: float = 0.0


## Builds the blend tree for `model` (an imported person or the suit, with its AnimationPlayer).
func setup(model: Node3D) -> void:
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
	blend.connect_node(&"output", 0, &"walk")
	tree_root = blend
	active = true


func _process(delta: float) -> void:
	if not tree_root:
		return
	var walking: bool = speed > 0.05
	_walk_amount = move_toward(_walk_amount, 1.0 if walking else 0.0, delta / walk_blend_time)
	set(&"parameters/walk/blend_amount", _walk_amount)
	set(&"parameters/walk_speed/scale", maxf(speed / walk_speed, min_time_scale))


func _clip(player: AnimationPlayer, clip: StringName) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = clip
	node.use_custom_timeline = true
	node.timeline_length = player.get_animation(clip).length
	node.stretch_time_scale = false
	node.loop_mode = Animation.LOOP_LINEAR
	return node
