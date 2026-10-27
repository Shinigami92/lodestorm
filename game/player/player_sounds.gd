class_name PlayerSounds
extends Node
## The `holder`'s own sounds, and the ears of the local player: an `AudioListener3D` at the player
## (not at the camera far above), turned like the camera, so left and right match the screen and
## the falloff fits what's on screen (see docs/design/sound.md). Plays the hits it takes, the dash
## and its steps (subtle, every `STEP_LENGTH` walked on the ground: on the ship's metal deck, on
## the ground outside, or as the hazard it stands in sounds: shards, mud); for the local player,
## the hits are critical cues and below a quarter of the health a slow pulse beats.

## Below this share of the maximum health the pulse beats. TBD (playtest).
const LOW_HEALTH: float = 0.25
## Seconds between two beats of the pulse. TBD (playtest).
const PULSE_INTERVAL: float = 1.1
## Height of the ears above the player's feet, in m.
const EAR_HEIGHT: float = 1.5
## Distance walked per step, in m: the run clips take two steps per 4 m stride (their speed
## follows the walking speed, so this keeps in time with the legs).
const STEP_LENGTH: float = 2.0
## Slower than this (m/s) the player stands: the next step comes after half a step's walk.
const STANDING_SPEED: float = 0.5

const HIT_SOUND: Sound = preload("res://assets/audio/sfx/player/hit_taken.tres")
const PULSE_SOUND: Sound = preload("res://assets/audio/sfx/player/low_health.tres")
const DASH_SOUND: Sound = preload("res://assets/audio/sfx/player/dash.tres")
const STEP_GROUND_SOUND: Sound = preload("res://assets/audio/sfx/player/step_ground.tres")
const STEP_DECK_SOUND: Sound = preload("res://assets/audio/sfx/player/step_deck.tres")

## The player whose sounds they are.
var holder: Player

## Seconds until the pulse's next beat.
var _pulse: float = 0.0
## Distance walked since the last step, in m.
var _walked: float = STEP_LENGTH * 0.5
var _listener := AudioListener3D.new()


func _ready() -> void:
	_listener.name = "Ears"
	add_child(_listener)
	holder.vitals.hurt.connect(_on_hurt)
	holder.suit_dash.dashed.connect(_play.bind(DASH_SOUND))


func _process(delta: float) -> void:
	if not holder.local:
		if _listener.is_current():
			_listener.clear_current()
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	var turn: Basis = camera.global_basis if camera else Basis.IDENTITY
	_listener.global_transform = Transform3D(turn, holder.global_position + Vector3.UP * EAR_HEIGHT)
	if not _listener.is_current():
		_listener.make_current()
	_beat(delta)


func _physics_process(delta: float) -> void:
	var speed: float = Vector2(holder.velocity.x, holder.velocity.z).length()
	if holder.dead or not holder.is_on_floor() or holder.suit_dash.is_dashing():
		return
	if speed < STANDING_SPEED:
		_walked = STEP_LENGTH * 0.5
		return
	_walked += speed * delta
	if _walked >= STEP_LENGTH:
		_walked -= STEP_LENGTH
		_play(_step_sound())


## The slow pulse below `LOW_HEALTH` (alive only).
func _beat(delta: float) -> void:
	if holder.dead or holder.health >= holder.max_health() * LOW_HEALTH:
		_pulse = 0.0
		return
	_pulse -= delta
	if _pulse <= 0.0:
		_pulse += PULSE_INTERVAL
		Sfx.play_at(PULSE_SOUND, holder.global_position, true)


## How the next step sounds: like the hazard it stands in, the deck or the ground.
func _step_sound() -> Sound:
	var hazard: Sound = holder.ground_contact.step_sound()
	if hazard:
		return hazard
	return STEP_DECK_SOUND if _on_deck() else STEP_GROUND_SOUND


## Whether the player stands on the ship (its deck, the ramp) or a station rather than the ground.
func _on_deck() -> bool:
	var from: Vector3 = holder.global_position + Vector3.UP * 0.3
	var query := PhysicsRayQueryParameters3D.create(
		from, from + Vector3.DOWN * 0.8, PhysicsLayers.WORLD, [holder.get_rid()]
	)
	var hit: Dictionary = holder.get_world_3d().direct_space_state.intersect_ray(query)
	var node: Node = hit.get("collider") as Node
	while node:
		if node is Ship or node is SpaceStation:
			return true
		node = node.get_parent()
	return false


func _on_hurt(_amount: float, _from: Vector3) -> void:
	Sfx.play_at(HIT_SOUND, holder.global_position, holder.local)


func _play(sound: Sound) -> void:
	Sfx.play_at(sound, holder.global_position)
