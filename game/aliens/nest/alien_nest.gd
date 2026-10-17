class_name AlienNest
extends Node3D
## Alien nest: an organic mound in the outside world that aliens hatch from. When it
## appears, `settings.guards` aliens hatch and wait around it. While a mission runs it sends out
## hunters, aliens that go for the nearest player outside the ship however far away. The hive
## escalates with the mission's progress (0 at the start, 1 when the storm hits): hunters hatch
## more often and more of them are out at once. After a hunter dies, the next one hatches a full
## interval later. Raiders go for miners and escalate the same way with their own values; they
## only hatch while a miner works, the first one a full interval after that. The glow in the nest's
## mouth pulses faster as the hive escalates. Aliens hatch stronger on bodies farther in (see
## `MissionSettings.alien_health_at`).

## Emitted when an alien hatches.
signal hatched(alien: Alien)

const GROUP: StringName = &"alien_nests"

const COLOR_GLOW := Color(0.9, 1.0, 0.2)
## Glow pulses per second at escalation 0 and 1.
const PULSE_RATE_CALM: float = 0.4
const PULSE_RATE_FRENZY: float = 2.0
## Glow energy at the low and the high point of a pulse.
const GLOW_ENERGY_MIN: float = 0.5
const GLOW_ENERGY_MAX: float = 4.0

@export var settings: AlienNestSettings
@export var alien_scene: PackedScene

## Seconds until the next hunter hatches; only counts down while fewer hunters than allowed are out.
var hunter_cooldown: float
## Seconds until the next raider hatches; only counts down while a miner works and fewer raiders
## than allowed are out.
var raider_cooldown: float

var _hunters: Array[Alien] = []
var _raiders: Array[Alien] = []
var _mission: Mission
## Pulse phase in turns.
var _pulse: float = 0.0
var _glow := StandardMaterial3D.new()

## The look lives in the `Model` child; its `Mouth` and `Glands` meshes pulse with the glow.
@onready var _model: Node3D = $Model


func _ready() -> void:
	add_to_group(GROUP)
	_glow.albedo_color = COLOR_GLOW
	_glow.emission_enabled = true
	_glow.emission = COLOR_GLOW
	for part: String in ["Mouth", "Glands"]:
		var glowing := _model.find_child(part, true, false) as GeometryInstance3D
		if glowing:
			glowing.material_override = _glow
	# The slime lies flat on the ground and the mouth is a light: neither casts a shadow.
	for part: String in ["Slime", "Mouth"]:
		var flat := _model.find_child(part, true, false) as GeometryInstance3D
		if flat:
			flat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hunter_cooldown = settings.hunter_interval_start
	raider_cooldown = settings.raider_interval_start
	for i: int in settings.guards:
		hatch(Alien.Role.GUARD)


func _physics_process(delta: float) -> void:
	var level: float = escalation()
	_pulse = fmod(_pulse + delta * lerpf(PULSE_RATE_CALM, PULSE_RATE_FRENZY, level), 1.0)
	if not (_find_mission() and _mission.is_running()):
		return
	hunter_cooldown = _count_down(
		Alien.Role.HUNTER, hunter_cooldown, hunter_interval(level), max_hunters(level), delta
	)
	var raider_limit: int = max_raiders(level) if Miner.any_working(get_tree()) else 0
	raider_cooldown = _count_down(
		Alien.Role.RAIDER, raider_cooldown, raider_interval(level), raider_limit, delta
	)


func _process(_delta: float) -> void:
	var wave: float = 0.5 - 0.5 * cos(TAU * _pulse)
	_glow.emission_energy_multiplier = lerpf(GLOW_ENERGY_MIN, GLOW_ENERGY_MAX, wave)


## Hatches an alien with `role` at a random spot around the nest, facing away from it.
func hatch(role: Alien.Role) -> Alien:
	var alien := alien_scene.instantiate() as Alien
	alien.role = role
	if _find_mission():
		alien.health_factor = _mission.settings.alien_health_at(_mission.tier())
		alien.damage_factor = _mission.settings.alien_damage_at(_mission.tier())
	var angle: float = randf() * TAU
	var direction := Vector3(sin(angle), 0.0, cos(angle))
	alien.position = direction * settings.hatch_radius
	alien.basis = Basis(Vector3.UP, atan2(-direction.x, -direction.z))
	add_child(alien)
	if role != Alien.Role.GUARD:
		var sent_out: Array[Alien] = _hunters if role == Alien.Role.HUNTER else _raiders
		sent_out.append(alien)
		alien.died.connect(func() -> void: sent_out.erase(alien))
	hatched.emit(alien)
	return alien


## How far the hive has escalated, from 0 to 1 (the mission's progress; 0 without a mission).
func escalation() -> float:
	return _mission.progress() if _find_mission() else 0.0


## Seconds between hunters at escalation `level`.
func hunter_interval(level: float) -> float:
	return lerpf(settings.hunter_interval_start, settings.hunter_interval_end, level)


## How many hunters from this nest may be out at once at escalation `level`.
func max_hunters(level: float) -> int:
	return roundi(lerpf(settings.max_hunters_start, settings.max_hunters_end, level))


## Seconds between raiders at escalation `level`.
func raider_interval(level: float) -> float:
	return lerpf(settings.raider_interval_start, settings.raider_interval_end, level)


## How many raiders from this nest may be out at once at escalation `level`.
func max_raiders(level: float) -> int:
	return roundi(lerpf(settings.max_raiders_start, settings.max_raiders_end, level))


## Hunters from this nest that are still alive.
func get_hunters() -> Array[Alien]:
	return _hunters.duplicate()


## Raiders from this nest that are still alive.
func get_raiders() -> Array[Alien]:
	return _raiders.duplicate()


## Counts `cooldown` down while fewer than `limit` aliens with `role` are out, hatches one at zero
## and returns the new cooldown. At the limit it holds a full `interval`.
func _count_down(
	role: Alien.Role, cooldown: float, interval: float, limit: int, delta: float
) -> float:
	var out: int = (_hunters if role == Alien.Role.HUNTER else _raiders).size()
	if out >= limit:
		return interval
	cooldown = maxf(cooldown - delta, 0.0)
	if cooldown > 0.0:
		return cooldown
	hatch(role)
	return interval


## Looks the mission up until it's found (it may be set up after the nest).
func _find_mission() -> bool:
	if not is_instance_valid(_mission):
		_mission = get_tree().get_first_node_in_group(Mission.GROUP) as Mission
	return _mission != null
