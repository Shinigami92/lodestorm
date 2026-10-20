extends Node
## Plays the sound effects (`Sound`s), as the autoload `Sfx` (see GAME_DESIGN.md, Sound):
## - in the world at a place (`play_at`, 3D: heard from the local player's ears, see
##   `PlayerSounds`), or flat (`play_ui`: e.g. a volume slider's sample, also while paused);
## - loops (the drill, the storm) on a node until it stops them or leaves the tree (`play_loop_at`
##   in the world, following the node; `play_loop` flat), outside the limits;
## - when more of a sound start than its `limit`, the farthest from the ears are dropped first;
## - critical cues for the local player (the timing window, a hit taken, low health) always play
##   and duck the Effects and Ambience buses a little while they do;
## - the buses' volumes come from the settings (`GameSettings.volume`).

## Emitted for every sound that starts, and whether it's a critical cue (tests and tools listen).
signal played(sound: Sound, critical: bool)

## The buses with a volume in the settings, Master first (see `game/audio/bus_layout.tres`).
const BUSES: Array[StringName] = [&"Master", &"Effects", &"Ambience"]
## The buses a critical cue ducks, and by how much (dB). TBD (playtest).
const DUCKED: Array[StringName] = [&"Effects", &"Ambience"]
const DUCK_DB: float = -6.0
## Seconds the duck takes to fade out after the cue. TBD (playtest).
const DUCK_RELEASE: float = 0.3

## The sounds playing, per `Sound`.
var _voices: Dictionary[Sound, Array] = {}
## Seconds a critical cue still ducks the other buses, and the duck right now (dB).
var _duck_left: float = 0.0
var _duck: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_volumes()


func _process(delta: float) -> void:
	for sound: Sound in _voices.keys():
		var voices: Array = _voices[sound]
		for voice: Voice in voices.duplicate():
			if voice.player.can_process():
				voice.left -= delta
			if voice.left <= 0.0:
				_stop(sound, voice)
	_duck_left = maxf(_duck_left - delta, 0.0)
	if _duck_left > 0.0:
		_duck = DUCK_DB
	else:
		_duck = move_toward(_duck, 0.0, absf(DUCK_DB) / DUCK_RELEASE * delta)
	_apply_volumes()


## Plays `sound` at `where` in the world, `pitch` times its pitch (bigger aliens lower). A
## `critical` cue (only for the local player) always plays and ducks the rest. Returns its player,
## or null when it was dropped (its limit).
func play_at(
	sound: Sound, where: Vector3, critical: bool = false, pitch: float = 1.0
) -> AudioStreamPlayer3D:
	if not sound or not _make_room(sound, where, critical):
		return null
	var player: AudioStreamPlayer3D = _world_player(sound)
	player.pitch_scale = pitch
	# World sounds stop with the world (pause) and go on after it.
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	player.global_position = where
	player.play()
	_start(sound, player, where, critical, pitch)
	return player


## Starts `sound` looping in the world at `holder`, following it, until the returned player is
## freed (`stop_loop`) or the holder leaves the tree; it pauses with the holder.
func play_loop_at(sound: Sound, holder: Node3D) -> AudioStreamPlayer3D:
	var player: AudioStreamPlayer3D = _world_player(sound)
	holder.add_child(player)
	player.play()
	played.emit(sound, false)
	return player


## Starts `sound` looping flat (the storm all around) under `holder`, until the returned player is
## freed (`stop_loop`) or the holder leaves the tree; it pauses with the holder.
func play_loop(sound: Sound, holder: Node) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = sound.stream
	player.bus = sound.bus
	player.volume_db = sound.volume_db
	holder.add_child(player)
	player.play()
	played.emit(sound, false)
	return player


## Stops a loop started by `play_loop_at` or `play_loop` (null or freed: nothing to stop).
func stop_loop(player: Node) -> void:
	if is_instance_valid(player):
		player.queue_free()


## Plays `sound` flat, on `bus` (default: its own), also while paused. Returns its player, or
## null when it was dropped (its limit).
func play_ui(sound: Sound, bus: StringName = &"") -> AudioStreamPlayer:
	if not sound:
		return null
	var ears: Vector3 = _ears()
	if not _make_room(sound, ears, false):
		return null
	var player := AudioStreamPlayer.new()
	player.stream = sound.stream
	player.bus = bus if bus else StringName(sound.bus)
	player.volume_db = sound.volume_db
	add_child(player)
	player.play()
	_start(sound, player, ears, false)
	return player


## How many of `sound` are playing right now.
func playing(sound: Sound) -> int:
	return (_voices.get(sound, []) as Array).size()


## Stops every sound and the duck.
func stop_all() -> void:
	for sound: Sound in _voices.keys():
		for voice: Voice in (_voices[sound] as Array).duplicate():
			_stop(sound, voice)
	_duck_left = 0.0
	_duck = 0.0
	_apply_volumes()


## Whether there's room for one more of `sound` at `where`: a critical cue always finds it, else
## the farthest one playing stops for it, unless this one is farther still.
func _make_room(sound: Sound, where: Vector3, critical: bool) -> bool:
	var voices: Array = _voices.get(sound, [])
	if critical or sound.limit <= 0 or voices.size() < sound.limit:
		return true
	var ears: Vector3 = _ears()
	var farthest: Voice = null
	for voice: Voice in voices:
		if voice.critical:
			continue
		if not farthest or voice.distance(ears) > farthest.distance(ears):
			farthest = voice
	if not farthest or where.distance_to(ears) >= farthest.distance(ears):
		return false
	_stop(sound, farthest)
	return true


func _world_player(sound: Sound) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.stream = sound.stream
	player.bus = sound.bus
	player.volume_db = sound.volume_db
	player.unit_size = sound.unit_size
	player.max_distance = sound.max_distance
	return player


func _start(sound: Sound, player: Node, where: Vector3, critical: bool, pitch: float = 1.0) -> void:
	var voice := Voice.new(player, where, sound.length() / maxf(pitch, 0.01), critical)
	if sound not in _voices:
		_voices[sound] = []
	(_voices[sound] as Array).append(voice)
	if critical:
		_duck_left = maxf(_duck_left, voice.left)
	played.emit(sound, critical)


func _stop(sound: Sound, voice: Voice) -> void:
	var voices: Array = _voices[sound]
	voices.erase(voice)
	if voices.is_empty():
		_voices.erase(sound)
	if is_instance_valid(voice.player):
		voice.player.queue_free()


## Where the ears are: the current listener (the local player's), else the camera.
func _ears() -> Vector3:
	var listener: AudioListener3D = get_viewport().get_audio_listener_3d()
	if listener:
		return listener.global_position
	var camera: Camera3D = get_viewport().get_camera_3d()
	return camera.global_position if camera else Vector3.ZERO


func _apply_volumes() -> void:
	for bus: StringName in BUSES:
		var index: int = AudioServer.get_bus_index(bus)
		if index < 0:
			continue
		var volume: float = GameSettings.volume(bus)
		AudioServer.set_bus_mute(index, volume <= 0.0)
		var duck: float = _duck if bus in DUCKED else 0.0
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume, 0.0001)) + duck)


## A sound playing.
class Voice:
	var player: Node
	## Where it plays (the ears' place for flat sounds).
	var where: Vector3
	## Seconds until it's done.
	var left: float
	var critical: bool

	func _init(voice_player: Node, at: Vector3, length: float, is_critical: bool) -> void:
		player = voice_player
		where = at
		left = length
		critical = is_critical

	func distance(ears: Vector3) -> float:
		return where.distance_to(ears)
