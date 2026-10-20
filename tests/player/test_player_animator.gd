extends GutTest
## The player's arms with melee weapons: every weapon's hold and every attack motion has its clip,
## the hold follows the equipped weapon, attacks play their motions (Riven's chain one way, then
## back), Jag's motor shakes the arms and Auger's drill keeps them out, Clout's charge draws the
## arm back and it punches, Mantle hangs on the left forearm and bashes.

const PLAYER_SCENE: PackedScene = preload("res://game/player/player.tscn")
const SWARMER: AlienStrain = preload("res://game/aliens/strains/swarmer/swarmer.tres")
const HARL: WeaponType = preload("res://game/weapons/types/harl/harl.tres")
const RIVEN: WeaponType = preload("res://game/weapons/types/riven/riven.tres")
const DRAY: WeaponType = preload("res://game/weapons/types/dray/dray.tres")
const AUGER: WeaponType = preload("res://game/weapons/types/auger/auger.tres")
const JAG: WeaponType = preload("res://game/weapons/types/jag/jag.tres")
const CLOUT: WeaponType = preload("res://game/weapons/types/clout/clout.tres")
const MANTLE: WeaponType = preload("res://game/weapons/types/mantle/mantle.tres")

var _arena: Node3D
var _player: Player
var _animator: PlayerAnimator


func before_each() -> void:
	_arena = Node3D.new()
	add_child_autofree(_arena)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100.0, 1.0, 100.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	_arena.add_child(floor_body)
	_player = PLAYER_SCENE.instantiate() as Player
	_arena.add_child(_player)
	for weapon_type: WeaponType in [RIVEN, DRAY, AUGER, JAG, CLOUT, MANTLE]:
		_player.arsenal.unlock(weapon_type)
	_animator = _player.get_node("Animator") as PlayerAnimator
	await wait_physics_frames(1)


func after_each() -> void:
	Input.action_release(&"attack")


func test_every_hold_and_motion_has_its_clip() -> void:
	assert_eq(PlayerAnimator.HOLD_CLIPS.size(), WeaponType.Hold.size())
	assert_eq(PlayerAnimator.MOTION_CLIPS.size(), Weapon.Motion.size())
	var clips: Array[StringName] = []
	clips.append_array(PlayerAnimator.HOLD_CLIPS)
	clips.append_array(PlayerAnimator.MOTION_CLIPS)
	clips.append_array(PlayerAnimator.LAYER_CLIPS)
	var player := _player.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for clip: StringName in clips:
		assert_true(player.has_animation(clip), "clip %s" % clip)


func test_the_hold_follows_the_weapon() -> void:
	var cases: Array = [
		[HARL, &"Aim"],
		[RIVEN, &"ReadyBlade"],
		[DRAY, &"ReadyHammer"],
		[JAG, &"Brace"],
		[CLOUT, &"ReadyFist"],
		[MANTLE, &"ReadyShield"],
	]
	for case: Array in cases:
		await _drawn(case[0] as WeaponType)
		await wait_process_frames(2)
		var state: StringName = _animator.get(&"parameters/hold/current_state")
		assert_eq(state, case[1] as StringName)


func test_riven_slashes_one_way_then_back() -> void:
	var riven: Weapon = await _drawn(RIVEN)
	riven.type.delivery.attack(riven)
	riven.since_attack = 0.0
	await wait_process_frames(2)
	assert_true(_active(&"slash"), "the first slash")
	riven.type.delivery.attack(riven)
	await wait_process_frames(2)
	assert_true(_active(&"slashback"), "the second one back")


func test_dray_strikes_overhead() -> void:
	var dray: Weapon = await _drawn(DRAY)
	dray.type.delivery.attack(dray)
	await wait_process_frames(2)
	assert_true(_active(&"overhead"))
	await wait_seconds(1.5)
	assert_false(_active(&"overhead"), "back to the hold")


func test_jag_shakes_while_it_cuts() -> void:
	await _drawn(JAG)
	assert_eq(_animator.shake, 0.0)
	Input.action_press(&"attack")
	await wait_seconds(0.5)
	assert_gt(_animator.shake, 0.5, "the motor runs")
	assert_gt(_amount(&"cut"), 0.5)


func test_auger_thrusts_and_stays_out_while_drilling() -> void:
	var alien := SWARMER.spawn()
	alien.strain = alien.strain.duplicate() as AlienStrain
	alien.strain.max_health = 10000.0
	alien.strain.detection_range = 0.0
	alien.position = Vector3(0.0, 0.0, -1.5)
	_arena.add_child(alien)
	await _drawn(AUGER)
	Input.action_press(&"attack")
	await wait_process_frames(3)
	assert_true(_active(&"thrust"), "the thrust")
	await wait_seconds(0.5)
	assert_true(_animator.drilling, "drilling into the alien")
	assert_almost_eq(_amount(&"drill"), 1.0, 0.01, "arms out")
	Input.action_release(&"attack")
	await wait_seconds(0.5)
	assert_false(_animator.drilling)
	assert_almost_eq(_amount(&"drill"), 0.0, 0.01)


func test_clout_draws_back_while_charging_then_punches() -> void:
	var clout: Weapon = await _drawn(CLOUT)
	Input.action_press(&"attack")
	await wait_seconds(0.5)
	assert_gt(_amount(&"cock"), 0.3, "drawn back")
	Input.action_release(&"attack")
	await wait_process_frames(3)
	assert_true(_active(&"punch"), "the punch")
	assert_eq(clout.wind, 0.0)
	await wait_process_frames(2)
	assert_eq(_amount(&"cock"), 0.0)


func test_mantle_hangs_on_the_left_forearm_and_bashes() -> void:
	var mantle: Weapon = await _drawn(MANTLE)
	assert_eq(mantle.get_parent().name, &"ShieldMount")
	Input.action_press(&"attack")
	await wait_process_frames(3)
	Input.action_release(&"attack")
	assert_true(_active(&"bash"))
	await _drawn(RIVEN)
	assert_eq(_player.weapon.get_parent().name, &"WeaponMount", "back in the right hand")


func _active(motion: StringName) -> bool:
	var active: bool = _animator.get("parameters/%s/active" % motion)
	return active


func _amount(blend: StringName) -> float:
	var amount: float = _animator.get("parameters/%s/blend_amount" % blend)
	return amount


func _drawn(weapon_type: WeaponType) -> Weapon:
	_player.loadout.assign(0, weapon_type)
	await wait_seconds(weapon_type.draw_time + 0.05)
	return _player.weapon
