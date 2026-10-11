class_name AlienNest
extends Node3D
## Greybox alien nest: an organic mound in the outside world that aliens hatch from. When it
## appears, `settings.guards` aliens hatch and wait around it. While a mission runs it sends out
## hunters, aliens that go for the nearest player outside the ship however far away. The hive
## escalates with the mission's progress (0 at the start, 1 when the storm hits): hunters hatch
## more often and more of them are out at once. After a hunter dies, the next one hatches a full
## interval later. The glow in the nest's mouth pulses faster as the hive escalates.

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

var _hunters: Array[Alien] = []
var _mission: Mission
## Pulse phase in turns.
var _pulse: float = 0.0
var _glow := StandardMaterial3D.new()

@onready var _mouth: MeshInstance3D = $Mouth


func _ready() -> void:
	add_to_group(GROUP)
	_glow.albedo_color = COLOR_GLOW
	_glow.emission_enabled = true
	_glow.emission = COLOR_GLOW
	_mouth.material_override = _glow
	hunter_cooldown = settings.hunter_interval_start
	for i: int in settings.guards:
		hatch(false)


func _physics_process(delta: float) -> void:
	var level: float = escalation()
	_pulse = fmod(_pulse + delta * lerpf(PULSE_RATE_CALM, PULSE_RATE_FRENZY, level), 1.0)
	if not (_find_mission() and _mission.is_running()):
		return
	if _hunters.size() >= max_hunters(level):
		hunter_cooldown = hunter_interval(level)
		return
	hunter_cooldown = maxf(hunter_cooldown - delta, 0.0)
	if hunter_cooldown == 0.0:
		hatch(true)
		hunter_cooldown = hunter_interval(level)


func _process(_delta: float) -> void:
	var wave: float = 0.5 - 0.5 * cos(TAU * _pulse)
	_glow.emission_energy_multiplier = lerpf(GLOW_ENERGY_MIN, GLOW_ENERGY_MAX, wave)


## Hatches an alien at a random spot around the nest, facing away from it.
func hatch(hunter: bool) -> Alien:
	var alien := alien_scene.instantiate() as Alien
	alien.hunter = hunter
	var angle: float = randf() * TAU
	var direction := Vector3(sin(angle), 0.0, cos(angle))
	alien.position = direction * settings.hatch_radius
	alien.basis = Basis(Vector3.UP, atan2(-direction.x, -direction.z))
	add_child(alien)
	if hunter:
		_hunters.append(alien)
		alien.died.connect(func() -> void: _hunters.erase(alien))
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


## Hunters from this nest that are still alive.
func get_hunters() -> Array[Alien]:
	return _hunters.duplicate()


## Looks the mission up until it's found (it may be set up after the nest).
func _find_mission() -> bool:
	if not is_instance_valid(_mission):
		_mission = get_tree().get_first_node_in_group(Mission.GROUP) as Mission
	return _mission != null
