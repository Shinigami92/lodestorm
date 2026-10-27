class_name AlienSounds
extends Node
## The `alien`'s sounds (see docs/design/sound.md): it chitters when it notices a target and now
## and then while it chases (not under the ground or while hiding), its heavy attacks' wind-ups and
## acts sound (`AlienAttack.wind_up_sound`, `act_sound`), and its strikes, the hits it takes (flesh
## or armor) and its death. All of them in its strain's voice (`AlienStrain.voice_pitch`: bigger
## strains lower); a strain without its own sound uses the hive's (the swarmer's).

## Seconds between two chitters while it chases (at random within). TBD (playtest).
const CHITTER_INTERVAL := Vector2(3.0, 7.0)

const CHITTER_SOUND: Sound = preload("res://assets/audio/sfx/aliens/chitter.tres")
const STRIKE_SOUND: Sound = preload("res://assets/audio/sfx/aliens/strike.tres")
const HIT_SOUND: Sound = preload("res://assets/audio/sfx/aliens/hit.tres")
const ARMOR_HIT_SOUND: Sound = preload("res://assets/audio/sfx/aliens/hit_armor.tres")
const DEATH_SOUND: Sound = preload("res://assets/audio/sfx/aliens/death.tres")

## The alien whose sounds they are.
var alien: Alien

## Seconds until it chitters again while it chases.
var _until_chitter: float = 0.0
var _had_target: bool = false


func _ready() -> void:
	alien.winding_up.connect(_on_winding_up)
	alien.acting.connect(_on_acting)
	alien.struck.connect(_on_struck)
	alien.hit_taken.connect(_on_hit_taken)
	alien.died.connect(_on_died)


func _physics_process(delta: float) -> void:
	var chasing: bool = is_instance_valid(alien.target) and not alien.dead
	var quiet: bool = alien.underground or (alien.cloaking and alien.cloaking.is_hidden())
	if chasing and not _had_target:
		_until_chitter = 0.0
	_had_target = chasing
	if not chasing:
		return
	_until_chitter -= delta
	if _until_chitter <= 0.0:
		_until_chitter = randf_range(CHITTER_INTERVAL.x, CHITTER_INTERVAL.y)
		if not quiet:
			_play(_own(alien.strain.chitter_sound, CHITTER_SOUND))


func _on_winding_up(attack: AlienAttack) -> void:
	_play(attack.wind_up_sound)


func _on_acting(attack: AlienAttack) -> void:
	_play(attack.act_sound)


func _on_struck(_victim: Node3D) -> void:
	_play(_own(alien.strain.strike_sound, STRIKE_SOUND))


func _on_hit_taken(_hit: Hit, _dealt: float, armored: bool) -> void:
	if armored:
		_play(_own(alien.strain.armor_hit_sound, ARMOR_HIT_SOUND))
	else:
		_play(_own(alien.strain.hit_sound, HIT_SOUND))


func _on_died() -> void:
	_play(_own(alien.strain.death_sound, DEATH_SOUND))


func _own(sound: Sound, hive: Sound) -> Sound:
	return sound if sound else hive


func _play(sound: Sound) -> void:
	if sound and alien.is_inside_tree():
		Sfx.play_at(sound, alien.global_position, false, alien.strain.voice_pitch)
