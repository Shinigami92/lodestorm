extends GutTest
## An NPC's own model (`NpcBody`, `NpcAnimator`): Nell's model with her head height and her props,
## her work at the bar now and then while nobody is close, stopping when a player comes close.

const BODY := preload("res://game/npcs/npc_body.tscn")
const NELL: NpcProfile = preload("res://game/npcs/ostra/bartender.tres")

var _body: NpcBody
var _animator: NpcAnimator


func before_each() -> void:
	_body = BODY.instantiate() as NpcBody
	add_child_autofree(_body)
	_animator = _body.get_node("Animator") as NpcAnimator
	_animator.work_pause = Vector2(0.05, 0.1)
	_body.profile = NELL
	await wait_process_frames(2)


func test_own_model_with_its_head_and_props() -> void:
	assert_almost_eq(_body.head_height, 1.73, 0.05, "the top of her hair, not the suit's helmet")
	for prop: StringName in NELL.props:
		var grip := _body.find_child(String(prop) + "Grip", true, false) as Node3D
		assert_not_null(grip, String(prop))
		assert_eq(grip.get_child_count(), 1, "the prop's model on " + String(prop))


func test_works_while_nobody_is_close() -> void:
	await wait_seconds(0.4)
	assert_true(NELL.activities.has(_animator.working()), "an activity plays")
	var first: StringName = _animator.working()
	var someone := Node3D.new()
	add_child_autofree(someone)
	someone.position = Vector3(0.0, 0.0, 1.5)
	_body.faces = someone  # someone talks to her
	await wait_seconds(_animator.work_fade + 0.3)
	assert_false(_animator.may_work)
	assert_eq(_animator.working(), &"", "stopped while someone is close")
	_body.faces = null
	await wait_seconds(0.4)
	assert_ne(_animator.working(), first, "the next is another one")
