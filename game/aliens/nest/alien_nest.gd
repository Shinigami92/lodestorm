class_name AlienNest
extends Node3D
## Alien nest: an organic mound in the outside world that aliens hatch from, by its `table` (which
## strains, and the packs they come in: see `HatchTable`). When it appears, `settings.guard_packs`
## packs hatch and wait around it. While a mission runs it sends out hunters, packs that go for the
## nearest player outside the ship however far away. The hive escalates with the mission's
## progress (0 at the start, 1 when the storm hits): packs hatch more often, more hunters are out at
## once, and a tier's new strains join late in a run. After the hunters are down below the limit,
## the next pack hatches a full interval later. Raiders go for miners and escalate the same way with
## their own values, one by one; they only hatch while a miner works, the first one a full interval
## after that. The glow in the nest's mouth pulses faster as the hive escalates. Aliens hatch
## stronger on bodies farther in (see `MissionSettings.alien_health_at`). Nests wait while the
## living aliens reach the cap (`AlienNestSettings.alien_cap`).

## Emitted when an alien hatches.
signal hatched(alien: Alien)

const GROUP: StringName = &"alien_nests"

const COLOR_GLOW := Alien.COLOR_GLOW
## Glow pulses per second at escalation 0 and 1.
const PULSE_RATE_CALM: float = 0.4
const PULSE_RATE_FRENZY: float = 2.0
## Glow energy at the low and the high point of a pulse.
const GLOW_ENERGY_MIN: float = 0.5
const GLOW_ENERGY_MAX: float = 4.0

@export var settings: AlienNestSettings
## The strains and packs it hatches from (see `table`).
@export var hive: AlienHive

## What it hatches: set by the location before the nest enters the tree (its body's tier, biome
## and danger); otherwise the hive's for the mission's tier.
var table: HatchTable
## Seconds until the next pack of hunters hatches; only counts down while fewer hunters than
## allowed are out.
var hunter_cooldown: float
## Seconds until the next raider hatches; only counts down while a miner works and fewer raiders
## than allowed are out.
var raider_cooldown: float

var _hunters: Array[Alien] = []
var _raiders: Array[Alien] = []
var _mission: Mission
var _rng := RandomNumberGenerator.new()
## Pulse phase in turns.
var _pulse: float = 0.0
var _glow := StandardMaterial3D.new()

## The look lives in the `Model` child; its `Mouth` and `Glands` meshes pulse with the glow.
@onready var _model: Node3D = $Model


func _ready() -> void:
	add_to_group(GROUP)
	_rng.randomize()
	if not table:
		table = hive.table(_mission.tier() if _find_mission() else 1)
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
	for i: int in settings.guard_packs:
		hatch_pack(Alien.Role.GUARD)


func _physics_process(delta: float) -> void:
	var level: float = escalation()
	_pulse = fmod(_pulse + delta * lerpf(PULSE_RATE_CALM, PULSE_RATE_FRENZY, level), 1.0)
	if not (_find_mission() and _mission.is_running()):
		return
	hunter_cooldown = _count_down(
		Alien.Role.HUNTER, hunter_cooldown, hunter_interval(level), max_hunters(level), delta
	)
	var raider_limit: float = max_raiders(level) if Miner.any_working(get_tree()) else 0.0
	raider_cooldown = _count_down(
		Alien.Role.RAIDER, raider_cooldown, raider_interval(level), raider_limit, delta
	)


func _process(_delta: float) -> void:
	var wave: float = 0.5 - 0.5 * cos(TAU * _pulse)
	_glow.emission_energy_multiplier = lerpf(GLOW_ENERGY_MIN, GLOW_ENERGY_MAX, wave)


## Hatches a pack (see `HatchTable.pick_pack`) with `role` around the nest, unless the cap is
## reached. Returns its aliens (none without a pack that fits).
func hatch_pack(role: Alien.Role) -> Array[Alien]:
	var hatching: Array[Alien] = []
	var pack: AlienPack = table.pick_pack(_rng, escalation())
	if not pack or is_full(pack.cap_load(), role == Alien.Role.GUARD):
		return hatching
	for strain: AlienStrain in pack.aliens():
		hatching.append(hatch(role, strain))
	return hatching


## Hatches an alien of `strain` with `role` at a random spot around the nest, facing away from it.
## Without a strain: a raider's (see `HatchTable.pick_raider`), or one of a pack's.
func hatch(role: Alien.Role, strain: AlienStrain = null) -> Alien:
	if not strain:
		strain = _any_strain(role)
	var alien: Alien = strain.spawn(role)
	if _find_mission():
		alien.health_factor = _mission.settings.alien_health_at(_mission.tier())
		alien.damage_factor = _mission.settings.alien_damage_at(_mission.tier())
	var angle: float = _rng.randf() * TAU
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


## Whether `share` more (in cap shares) would go over the cap on living aliens: nests wait. For
## `guards`, the guards' own share of it (`AlienNestSettings.guard_share`).
func is_full(share: float = 1.0, guards: bool = false) -> bool:
	if guards:
		var waiting: float = 0.0
		for alien: Alien in get_tree().get_nodes_in_group(Alien.GROUP):
			if alien.role == Alien.Role.GUARD:
				waiting += alien.strain.cap_share
		return waiting + share > settings.alien_cap() * settings.guard_share
	return Alien.living_load(get_tree()) + share > settings.alien_cap()


## Seconds between packs of hunters at escalation `level`.
func hunter_interval(level: float) -> float:
	return lerpf(settings.hunter_interval_start, settings.hunter_interval_end, level)


## How many hunters from this nest may be out at once at escalation `level` (in cap shares, whole
## ones).
func max_hunters(level: float) -> float:
	return roundf(lerpf(settings.max_hunters_start, settings.max_hunters_end, level))


## Seconds between raiders at escalation `level`.
func raider_interval(level: float) -> float:
	return lerpf(settings.raider_interval_start, settings.raider_interval_end, level)


## How many raiders from this nest may be out at once at escalation `level` (in cap shares, whole
## ones).
func max_raiders(level: float) -> float:
	return roundf(lerpf(settings.max_raiders_start, settings.max_raiders_end, level))


## Hunters from this nest that are still alive.
func get_hunters() -> Array[Alien]:
	return _hunters.duplicate()


## Raiders from this nest that are still alive.
func get_raiders() -> Array[Alien]:
	return _raiders.duplicate()


## How much `aliens` count towards the cap.
static func load_of(aliens: Array[Alien]) -> float:
	var total: float = 0.0
	for alien: Alien in aliens:
		total += alien.strain.cap_share
	return total


## Counts `cooldown` down while the aliens with `role` out count less than `limit`, hatches (a pack
## of hunters, a raider) at zero and returns the new cooldown. At the limit it holds a full
## `interval`; at the cap it waits.
func _count_down(
	role: Alien.Role, cooldown: float, interval: float, limit: float, delta: float
) -> float:
	var out: Array[Alien] = _hunters if role == Alien.Role.HUNTER else _raiders
	if load_of(out) >= limit:
		return interval
	cooldown = maxf(cooldown - delta, 0.0)
	if cooldown > 0.0:
		return cooldown
	if role == Alien.Role.HUNTER:
		if hatch_pack(role).is_empty():
			return cooldown
	else:
		var strain: AlienStrain = table.pick_raider(_rng, escalation())
		if not strain or is_full(strain.cap_share):
			return cooldown
		hatch(role, strain)
	return interval


## A strain for a single alien with `role`: a raider's, or one from a pack.
func _any_strain(role: Alien.Role) -> AlienStrain:
	var level: float = escalation()
	if role == Alien.Role.RAIDER:
		var raider: AlienStrain = table.pick_raider(_rng, level)
		if raider:
			return raider
	var pack: AlienPack = table.pick_pack(_rng, level)
	if pack:
		var members: Array[AlienStrain] = pack.aliens()
		return members[_rng.randi() % members.size()]
	return hive.strains[0]


## Looks the mission up until it's found (it may be set up after the nest).
func _find_mission() -> bool:
	if not is_instance_valid(_mission):
		_mission = get_tree().get_first_node_in_group(Mission.GROUP) as Mission
	return _mission != null
