extends GutTest
## An NPC's own model (`NpcBody`, `NpcAnimator`): Nell's model with her head height and her props,
## her work at the bar now and then while nobody is close, stopping when a player comes close; the
## suit sitting down and getting up.

const BODY := preload("res://game/npcs/npc_body.tscn")
const NELL: NpcProfile = preload("res://game/npcs/ostra/bartender.tres")
const KADE: NpcProfile = preload("res://game/npcs/ostra/depot_master.tres")
const SELIN: NpcProfile = preload("res://game/npcs/ostra/councillor.tres")
const ROOK: NpcProfile = preload("res://game/npcs/ostra/rival_captain.tres")
const COLONIST: NpcProfile = preload("res://game/npcs/ostra/colonists/hauler_pilot.tres")

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


## Kade, Selin and Rook wear their generated heads (no MakeHuman face): the name plate goes
## above their hair.
func test_own_head_models() -> void:
	for case: Array in [[KADE, 1.79], [SELIN, 1.66], [ROOK, 1.88]]:
		var body := BODY.instantiate() as NpcBody
		add_child_autofree(body)
		body.profile = case[0] as NpcProfile
		await wait_process_frames(2)
		assert_almost_eq(
			body.head_height, case[1] as float, 0.05, (case[0] as NpcProfile).display_name
		)


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


## The suit (the colonists) sits down and gets up over the blend time, its head lower while it sits;
## an own model without the clip stays standing.
func test_the_suit_sits_down_and_gets_up() -> void:
	assert_false(_animator.can_sit(), "Nell's model has no sitting clip")
	var body := BODY.instantiate() as NpcBody
	add_child_autofree(body)
	body.profile = COLONIST
	var animator := body.get_node("Animator") as NpcAnimator
	await wait_process_frames(2)
	assert_true(animator.can_sit())
	var standing: float = body.get_head_position().y
	body.sitting = true
	await wait_seconds(animator.sit_blend_time * 0.5)
	assert_between(body.get_sit_amount(), 0.1, 0.9, "sitting down")
	await wait_seconds(animator.sit_blend_time * 0.5 + 0.2)
	assert_eq(body.get_sit_amount(), 1.0)
	assert_between(standing - body.get_head_position().y, 0.3, 0.5, "the head as low as it sits")
	body.sitting = false
	await wait_seconds(animator.sit_blend_time + 0.2)
	assert_eq(body.get_sit_amount(), 0.0, "up again")
	assert_almost_eq(body.get_head_position().y, standing, 0.001)
