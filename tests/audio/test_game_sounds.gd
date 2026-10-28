extends GutTest

const PLAYER_SCENE: PackedScene = preload("res://game/player/player.tscn")
const HARL: WeaponType = preload("res://game/weapons/types/harl/harl.tres")
const DRAY: WeaponType = preload("res://game/weapons/types/dray/dray.tres")
const DASH: Skill = preload("res://game/progression/skills/tree/dash.tres")
const SFX_DIR: String = "res://assets/audio/sfx/"

var _arena: Node3D
var _player: Player
var _played: Array[Sound] = []
var _critical: Array[Sound] = []


func before_each() -> void:
	Sfx.stop_all()
	_arena = Node3D.new()
	add_child_autofree(_arena)
	_add_floor()
	_player = _add_player(Vector3.ZERO)
	_played.clear()
	_critical.clear()
	await wait_physics_frames(2)
	Sfx.played.connect(_on_played)


func after_each() -> void:
	Sfx.played.disconnect(_on_played)
	Sfx.stop_all()
	Input.action_release(&"attack")
	Input.action_release(&"move_right")


func test_the_local_player_is_where_the_game_is_heard_from() -> void:
	var teammate := _add_player(Vector3(5.0, 0.0, 0.0))
	teammate.local = false
	await wait_process_frames(2)
	var ears: AudioListener3D = get_viewport().get_audio_listener_3d()
	assert_eq(ears, _player.sounds.get_node(^"Ears"))
	assert_almost_eq(
		ears.global_position,
		_player.global_position + Vector3.UP * PlayerSounds.EAR_HEIGHT,
		Vector3.ONE * 0.01
	)


func test_shots_and_a_reload_sound() -> void:
	var harl := _player.arms.get_ammo() as MagazineAmmo
	Input.action_press(&"attack")
	await wait_physics_frames(1)
	Input.action_release(&"attack")
	assert_has(_played, _sound("weapons/harl_shot"))
	harl.rounds = 1
	_played.clear()
	assert_true(_player.arms.reload())
	assert_eq(_played, [_sound("weapons/reload_start")] as Array[Sound])
	harl.reload_elapsed = harl.reload_duration
	await wait_physics_frames(1)
	assert_has(_played, _sound("weapons/magazine_in"))


func test_the_window_ticks_for_the_local_player_as_a_critical_cue() -> void:
	var harl := _player.arms.get_ammo() as MagazineAmmo
	harl.rounds = 1
	assert_true(_player.arms.reload())
	harl.reload_elapsed = harl.reload_duration * (harl.feed.sweet_spot_start - 0.01)
	await wait_physics_frames(2)
	assert_has(_critical, _sound("weapons/window_tick"))
	assert_true(_player.arms.reload(), "the timing press")
	assert_has(_played, _sound("weapons/timed_hit"))


func test_a_reload_that_cant_start_clicks() -> void:
	var harl := _player.arms.get_ammo() as MagazineAmmo
	harl.rounds = 0
	harl.spare_rounds = 0
	_player.arms.ammo_free = false
	assert_false(_player.arms.reload())
	assert_eq(_played, [_sound("weapons/empty_click")] as Array[Sound])


func test_a_swing_at_nothing_only_whooshes() -> void:
	_player.arsenal.unlock(DRAY)
	_player.loadout.assign(0, DRAY)
	Input.action_press(&"attack")
	await wait_physics_frames(1)
	Input.action_release(&"attack")
	assert_has(_played, _sound("weapons/dray_swing"))
	assert_does_not_have(_played, _sound("weapons/dray_hit"))


func test_hits_low_health_and_the_dash() -> void:
	_player.skills.raise(DASH)
	assert_true(_player.suit_dash.dash(Vector3.RIGHT))
	assert_has(_played, _sound("player/dash"))
	_player.take_damage(_player.max_health() * 0.8)
	assert_has(_critical, _sound("player/hit_taken"), "the local player's hits are cues")
	await wait_process_frames(2)
	assert_has(_critical, _sound("player/low_health"))


func test_walking_on_the_ground_steps_every_two_meters() -> void:
	Input.action_press(&"move_right")
	await wait_physics_frames(60)
	Input.action_release(&"move_right")
	var steps: int = _played.count(_sound("player/step_ground"))
	# 1 s at 6 m/s (less while speeding up): 2-3 steps, none on the deck.
	assert_between(steps, 2, 3)
	assert_does_not_have(_played, _sound("player/step_deck"))


func test_steps_in_a_hazard_sound_like_it() -> void:
	var mud := GroundHazard.new()
	mud.step_sound = _sound("player/step_mud")
	_player.ground_contact.enter(mud)
	Input.action_press(&"move_right")
	await wait_physics_frames(60)
	Input.action_release(&"move_right")
	_player.ground_contact.leave(mud)
	mud.free()
	assert_has(_played, _sound("player/step_mud"))
	assert_does_not_have(_played, _sound("player/step_ground"))


func _sound(path: String) -> Sound:
	return load(SFX_DIR + path + ".tres") as Sound


func _on_played(sound: Sound, critical: bool) -> void:
	_played.append(sound)
	if critical:
		_critical.append(sound)


func _add_player(at: Vector3) -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	player.position = at
	_arena.add_child(player)
	return player


func _add_floor() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100.0, 1.0, 100.0)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0.0, -0.5, 0.0)
	_arena.add_child(body)
