extends GutTest
## The world's sounds (see GAME_DESIGN.md, Sound): the aliens', the nests', the miners', the
## ship's ramp, the mission's and the vents'.

const TEST_MAP := preload("res://tests/support/test_map.gd")
const NEST_SCENE: PackedScene = preload("res://game/aliens/nest/alien_nest.tscn")
const SWARMER: AlienStrain = preload("res://game/aliens/strains/swarmer/swarmer.tres")
const BRUTE: AlienStrain = preload("res://game/aliens/strains/brute/brute.tres")
const SHRIEKER: AlienStrain = preload("res://game/aliens/strains/shrieker/shrieker.tres")
const SFX_DIR: String = "res://assets/audio/sfx/"

var _map: Node3D
var _mission: Mission
var _player: Player
var _ship: Ship
var _played: Array[Sound] = []
var _critical: Array[Sound] = []


func before_each() -> void:
	Sfx.stop_all()
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_mission = _map.get_node("Mission") as Mission
	_player = _map.get_node("Player") as Player
	_ship = _map.get_node("Ship") as Ship
	# The location's own nests would hatch and pulse in between.
	for nest: AlienNest in get_tree().get_nodes_in_group(AlienNest.GROUP):
		nest.queue_free()
	# Outside, or a running mission would end right away with everyone aboard.
	_player.global_position = _ship.to_global(Vector3(22.0, 0.0, 0.0))
	_player.reset_physics_interpolation()
	await wait_physics_frames(3)
	_played.clear()
	_critical.clear()
	Sfx.played.connect(_on_played)


func after_each() -> void:
	Sfx.played.disconnect(_on_played)
	Sfx.stop_all()


func test_every_strain_has_a_voice_and_heavy_attacks_a_telegraph() -> void:
	for path: String in _strain_paths():
		var strain := load(path) as AlienStrain
		assert_between(strain.voice_pitch, 0.3, 2.0, path)
		for attack: AlienAttack in strain.attacks:
			if attack.wind_up > 0.0:
				assert_not_null(attack.wind_up_sound, "%s: a wind-up sounds" % path)
	assert_lt(BRUTE.voice_pitch, SWARMER.voice_pitch, "bigger strains lower")


func test_an_alien_chitters_strikes_and_sounds_its_hits_and_death() -> void:
	var alien := _add_alien(SWARMER, 6.0)
	await wait_physics_frames(3)
	assert_eq(alien.target, _player)
	assert_has(_played, _sound("aliens/chitter"), "noticing the player")
	alien.strike(_player, 1.0)
	assert_has(_played, _sound("aliens/strike"))
	alien.take_hit(Hit.new(1.0, 0.0, 0.0, Vector3.LEFT, alien.get_aim_point()))
	assert_has(_played, _sound("aliens/hit"))
	assert_does_not_have(_played, _sound("aliens/hit_armor"), "the swarmer has no armor")
	alien.take_damage(alien.health)
	assert_has(_played, _sound("aliens/death"))


func test_armor_knocks() -> void:
	var alien := _add_alien(BRUTE, 30.0)
	await wait_physics_frames(1)
	alien.strain = BRUTE.duplicate() as AlienStrain
	alien.strain.armor = 8.0
	alien.strain.armor_arc = 360.0
	alien.take_hit(Hit.new(5.0, 0.0, 0.0, Vector3.LEFT, alien.get_aim_point()))
	assert_has(_played, _sound("aliens/hit_armor"))


func test_a_wind_up_and_a_scream_sound() -> void:
	var alien := _add_alien(SHRIEKER, 30.0)
	await wait_physics_frames(1)
	var scream: AlienAttack = null
	for attack: AlienAttack in SHRIEKER.attacks:
		if attack is AlienScream:
			scream = attack
	alien.winding_up.emit(scream)
	assert_has(_played, _sound("aliens/windup_scream"))
	alien.acting.emit(scream)
	assert_has(_played, _sound("aliens/scream"))


func test_a_nest_pulses_hatches_and_collapses() -> void:
	var nest := _add_nest()
	await wait_physics_frames(1)
	nest.set(&"_pulse", 0.999)
	await wait_physics_frames(2)
	assert_has(_played, _sound("aliens/nest_pulse"))
	assert_does_not_have(_played, _sound("aliens/nest_hatch"), "the guards come quietly")
	nest.hatch_pack()
	await wait_physics_frames(3)
	assert_has(_played, _sound("aliens/nest_hatch"))
	nest.body.take_damage(nest.body.health)
	assert_has(_played, _sound("aliens/nest_destroyed"))


func test_a_miner_drills_breaks_and_is_mended() -> void:
	var node := _map.get_node("Location/OreNodes/KyriteA") as OreNode
	var miner: Miner = node.place_miner(_player.miner_scene)
	assert_has(_played, _sound("mining/miner_place"))
	await wait_physics_frames(2)
	assert_eq(_loops(miner), [_sound("mining/drill")] as Array[Sound], "far from the player")
	miner.take_damage(miner.health)
	assert_has(_played, _sound("mining/breakdown"))
	await wait_physics_frames(2)
	assert_eq(_loops(miner), [] as Array[Sound], "broken: silent")
	_player.global_position = miner.global_position + Vector3(1.5, 0.0, 0.0)
	_player.reset_physics_interpolation()
	await wait_physics_frames(2)
	assert_eq(_loops(miner), [_sound("mining/repair")] as Array[Sound])


func test_a_full_miner_chimes_and_its_hose_flows() -> void:
	var node := _map.get_node("Location/OreNodes/KyriteA") as OreNode
	var miner: Miner = node.place_miner(_player.miner_scene)
	miner.amount = miner.capacity() - 0.001
	await wait_physics_frames(2)
	assert_has(_played, _sound("mining/miner_full"))
	assert_eq(_loops(miner), [] as Array[Sound], "full: the drill stops")
	_player.global_position = miner.global_position + Vector3(2.0, 0.0, 0.0)
	_player.reset_physics_interpolation()
	await wait_physics_frames(2)
	assert_has(_loops(miner), _sound("mining/hose"))


func test_the_ramp_sounds_when_it_moves() -> void:
	_ship.ramp_open = not _ship.ramp_open
	await wait_physics_frames(2)
	assert_eq(_played.count(_sound("mission/ramp")), 1)


func test_the_warning_the_countdown_and_the_storm() -> void:
	_mission.state = Mission.State.RUNNING
	_mission.time_left = _mission.warning_time() + 30.0
	await wait_process_frames(2)
	_mission.time_left = _mission.warning_time() - 0.1
	await wait_process_frames(2)
	assert_has(_critical, _sound("mission/storm_warning"), "a critical cue")
	_mission.time_left = 60.01
	await wait_seconds(0.1)
	assert_has(_played, _sound("mission/countdown_beep"))
	_mission.time_left = 0.01
	await wait_physics_frames(3)
	assert_eq(_mission.state, Mission.State.STORM)
	assert_has(_played, _sound("mission/storm_hit"))
	await wait_process_frames(3)
	var storm: Node = _map.get_node("Weather/Sounds")
	assert_eq(storm.get_child_count(), 1, "the storm all around")
	var loop := storm.get_child(0) as AudioStreamPlayer
	assert_eq(loop.bus, &"Ambience")


func test_a_vent_rumbles_then_bursts() -> void:
	var vent := GroundVent.new()
	vent.rest = Vector2(0.05, 0.05)
	vent.warning = 0.3
	_map.add_child(vent)
	vent.global_position = _ship.to_global(Vector3(40.0, 0.0, 0.0))
	await wait_physics_frames(10)
	assert_has(_played, _sound("biomes/vent_rumble"))
	assert_does_not_have(_played, _sound("biomes/vent_burst"))
	await wait_physics_frames(20)
	assert_has(_played, _sound("biomes/vent_burst"))


func _add_alien(strain: AlienStrain, distance: float) -> Alien:
	var alien := strain.spawn(Alien.Role.HUNTER)
	_map.add_child(alien)
	alien.global_position = _player.global_position + Vector3(distance, 0.0, 0.0)
	alien.reset_physics_interpolation()
	return alien


func _add_nest() -> AlienNest:
	var nest := NEST_SCENE.instantiate() as AlienNest
	var pack := AlienPack.new()
	pack.members = {SWARMER: 1}
	var hive := AlienHive.new()
	hive.strains = [SWARMER]
	hive.packs = [pack]
	nest.table = hive.table(1)
	nest.position = _ship.to_global(Vector3(55.0, 0.0, 0.0))
	_map.add_child(nest)
	return nest


## The loops playing on `holder` (its sound players' sounds).
func _loops(holder: Node) -> Array[Sound]:
	var sounds: Array[Sound] = []
	for child: Node in holder.get_children():
		var player := child as AudioStreamPlayer3D
		if player and not player.is_queued_for_deletion():
			sounds.append(_sound_of(player.stream))
	return sounds


func _sound_of(stream: AudioStream) -> Sound:
	for path: String in ["mining/drill", "mining/hose", "mining/repair"]:
		if _sound(path).stream == stream:
			return _sound(path)
	return null


func _strain_paths() -> Array[String]:
	var paths: Array[String] = []
	var root: String = "res://game/aliens/strains/"
	for folder: String in DirAccess.get_directories_at(root):
		paths.append("%s%s/%s.tres" % [root, folder, folder])
	return paths


func _sound(path: String) -> Sound:
	return load(SFX_DIR + path + ".tres") as Sound


func _on_played(sound: Sound, critical: bool) -> void:
	_played.append(sound)
	if critical:
		_critical.append(sound)
