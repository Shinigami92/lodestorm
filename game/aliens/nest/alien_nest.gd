class_name AlienNest
extends Node3D
## Alien nest: an organic mound in the outside world that aliens hatch from, by its `table` (which
## strains, and the packs hunters come in: see `HatchTable`). When it appears, `settings.guards`
## guards (of the guards' strains, the warden) hatch and wait around it. While a mission runs it
## sends out hunters, packs that go for the nearest player outside the ship however far away. The
## hive escalates with the mission's progress (0 at the start, 1 when the storm hits): packs hatch
## more often, more hunters are out at once, and a tier's new strains join late in a run. After the
## hunters are down below the limit, the next pack hatches a full interval later. Raiders (of the
## raiders' strains, the gnawer) go for miners and escalate the same way with their own values, one
## by one; they only hatch while a miner works, the first one a full interval after that. The glow
## in the nest's mouth pulses faster as the hive escalates. Each working miner draws raiders: its
## nearest nest sends them more often (`AlienNestSettings.raider_draw`). From the storm's warning on
## the hive frenzies: its aliens are faster and hunters hatch at their highest rate. A scream
## (`Alien.called_for_help`) makes the nest nearest to the shrieker send its next pack right away,
## boosted like the shrieker's pack: its mouth flares and a ring sweeps out from it.
## Aliens hatch stronger on bodies farther in (see `AlienHive.health_at`). Nests wait
## while the living aliens reach the cap (`AlienNestSettings.alien_cap`), looking again every
## `CAP_RETRY`. A pack hatches one alien after another (`AlienNestSettings.hatch_gap` apart), and
## the whole hive hatches at most one per physics frame: setting one up takes a moment, a pack at
## once made the game stutter. Aliens waiting to hatch count towards the cap.
## Weapons wear it down (its `body`, a `Destructible`: health and armor, scaled like the aliens'
## and per player). A hit calls its guards to go for the attacker. On the way down it bursts
## (`AlienNestSettings.bursts`): its mouth swells and glows white for a warning, then it spews
## hunters, and cracks open in its plates (the model's `Cracks1`, `Cracks2`, ...) while its glow
## flickers lower. When it's destroyed it collapses inwards, the glow goes dark and its slime dries
## grey: the husk stays, hatches nothing more and is no nest any more (it leaves `GROUP`); its
## aliens stay, and every other nest sends its next pack right away (the hive's surge).
## Its sounds: a deep, wet throb with each pulse of its glow (louder as the hive escalates), a wet
## pop for each alien hatching (not the guards it starts with), hits in its flesh, a groaning
## swell for a burst's warning and the collapse.

## Emitted when an alien hatches.
signal hatched(alien: Alien)
## Emitted when it's destroyed (the quests' "clear nests" goal counts these).
signal destroyed

const GROUP: StringName = &"alien_nests"

const COLOR_GLOW := Alien.COLOR_GLOW
## Glow pulses per second at escalation 0 and 1.
const PULSE_RATE_CALM: float = 0.4
const PULSE_RATE_FRENZY: float = 2.0
## Glow energy at the low and the high point of a pulse.
const GLOW_ENERGY_MIN: float = 0.5
const GLOW_ENERGY_MAX: float = 4.0
## Seconds between looks at which miners draw raiders to it.
const DRAW_INTERVAL: float = 1.0
## While the cap is reached (or no pack fits), it looks again this often (s).
const CAP_RETRY: float = 0.25
## When it answers a scream: how much brighter its mouth flares, for how long (s), and how far its
## ring reaches (m).
const ANSWER_FLARE: float = 3.0
const ANSWER_FLARE_TIME: float = 1.5
const ANSWER_RING: float = 8.0
## The glow's strength per crack stage (0: unhurt); past the list, its last value.
const STAGE_GLOW: Array[float] = [1.0, 0.55, 0.3]
## Cracked, the glow dips this low for `FLICKER_TIME` (s), on average every `FLICKER_INTERVAL` (s)
## divided by the stage.
const FLICKER_DIP: float = 0.25
const FLICKER_TIME: float = 0.07
const FLICKER_INTERVAL: float = 1.2
## A burst's warning: the mouth swells this much bigger around `MOUTH_CENTER` (the bowl's middle,
## in the model) and glows white, this much brighter.
const WARNING_SWELL: float = 0.3
const WARNING_GLOW: float = 6.0
const MOUTH_CENTER := Vector3(0.0, 0.96, 0.0)
## The husk: how far the mound sinks (its height's share) and draws in, its tint, and the dried
## slime's.
const HUSK_HEIGHT: float = 0.45
const HUSK_SPREAD: float = 0.94
const HUSK_TINT := Color(0.32, 0.3, 0.3)
const HUSK_GLOW := Color(0.05, 0.05, 0.04)
const DRY_SLIME := Color(0.2, 0.19, 0.18)
const DRY_ROUGHNESS: float = 0.95
## The pulse's throb at escalation 0 and 1 (dB on its sound's volume). TBD (playtest).
const PULSE_VOLUME_CALM: float = -8.0
const PULSE_VOLUME_FRENZY: float = 0.0
## Its sounds play this much lower than a swarmer's (a big body).
const VOICE_PITCH: float = 0.7

const PULSE_SOUND: Sound = preload("res://assets/audio/sfx/aliens/nest_pulse.tres")
const HATCH_SOUND: Sound = preload("res://assets/audio/sfx/aliens/nest_hatch.tres")
const SWELL_SOUND: Sound = preload("res://assets/audio/sfx/aliens/nest_swell.tres")
const DESTROYED_SOUND: Sound = preload("res://assets/audio/sfx/aliens/nest_destroyed.tres")

## The physics frame in which a nest last hatched an alien that waited: the hive hatches one per
## frame.
static var _hatch_frame: int = -1

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
## than allowed are out, faster with the miners it draws (`raider_draw_factor`).
var raider_cooldown: float
## How much faster raiders hatch for the working miners nearest to it (1: none).
var raider_draw_factor: float = 1.0
## How many times it burst (0 to `settings.bursts`): its cracks and its dimmer glow show it.
var stage: int = 0

var _hunters: Array[Alien] = []
## The aliens waiting to hatch, in turn, and the seconds until the next one may.
var _waiting: Array[Hatching] = []
var _until_hatch: float = 0.0
var _raiders: Array[Alien] = []
var _mission: Mission
var _rng := RandomNumberGenerator.new()
## Pulse phase in turns.
var _pulse: float = 0.0
var _until_draw: float = 0.0
## Seconds until it answers a scream again, and of its mouth's flare left.
var _call_cooldown: float = 0.0
var _flare_left: float = 0.0
## Bursts its health went past, and seconds left of the warning before the next one (0: none).
var _bursts_due: int = 0
var _warning_left: float = 0.0
## Seconds until the cracked glow dips next, and of the dip left.
var _until_flicker: float = 0.0
var _flicker_left: float = 0.0
## Whether it's destroyed, and how far its glow went dark (0 to 1).
var _destroyed: bool = false
var _dark: float = 0.0
var _glow := StandardMaterial3D.new()

## What weapons hit and wear down.
@onready var body: Destructible = $Body
## The look lives in the `Model` child; its `Mouth`, `Glands` and `Cracks<stage>` meshes pulse
## with the glow.
@onready var _model: Node3D = $Model
@onready var _mouth: Node3D = _model.find_child("Mouth", true, false) as Node3D


## An alien waiting to hatch: of `strain`, in `role`, `boost` times faster for `seconds` (an
## answered scream).
class Hatching:
	var strain: AlienStrain
	var role: Alien.Role
	var boost: float = 1.0
	var seconds: float = 0.0


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
	for crack: GeometryInstance3D in _cracks():
		crack.material_override = _glow
		crack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		crack.visible = false
	body.max_health = max_health()
	body.armor = settings.armor
	body.health = body.max_health
	body.damaged.connect(_on_damaged)
	body.destroyed.connect(_on_destroyed)
	# The slime lies flat on the ground and the mouth is a light: neither casts a shadow.
	for part: String in ["Slime", "Mouth"]:
		var flat := _model.find_child(part, true, false) as GeometryInstance3D
		if flat:
			flat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hunter_cooldown = settings.hunter_interval_start
	raider_cooldown = settings.raider_interval_start
	for i: int in settings.guards:
		_hatch_single(Alien.Role.GUARD)


func _physics_process(delta: float) -> void:
	var level: float = escalation()
	var frenzied: bool = is_frenzied()
	var pulse_level: float = 1.0 if frenzied else level
	var pulsed: float = _pulse + delta * lerpf(PULSE_RATE_CALM, PULSE_RATE_FRENZY, pulse_level)
	_pulse = fmod(pulsed, 1.0)
	if pulsed >= 1.0 and not _destroyed:
		var throb: AudioStreamPlayer3D = Sfx.play_at(PULSE_SOUND, _mouth_position())
		if throb:
			throb.volume_db += lerpf(PULSE_VOLUME_CALM, PULSE_VOLUME_FRENZY, pulse_level)
	_call_cooldown = maxf(_call_cooldown - delta, 0.0)
	var speed: float = settings.frenzy_speed if frenzied else 1.0
	for child: Node in get_children():
		if child is Alien:
			(child as Alien).status.hive_speed = speed
	if _warning_left > 0.0:
		_warning_left = maxf(_warning_left - delta, 0.0)
		if _warning_left == 0.0:
			_burst()
	_until_hatch = maxf(_until_hatch - delta, 0.0)
	_hatch_next()
	if _destroyed or not (_find_mission() and _mission.is_running()):
		return
	# The frenzy sends hunters at their highest rate, from its start on.
	var hunting: float = 1.0 if frenzied else level
	if frenzied:
		hunter_cooldown = minf(hunter_cooldown, hunter_interval(1.0))
	hunter_cooldown = _count_down(
		Alien.Role.HUNTER, hunter_cooldown, hunter_interval(hunting), max_hunters(hunting), delta
	)
	_until_draw -= delta
	if _until_draw <= 0.0:
		_until_draw = DRAW_INTERVAL
		raider_draw_factor = _draw_factor()
	var raider_limit: float = max_raiders(level) if Miner.any_working(get_tree()) else 0.0
	raider_cooldown = _count_down(
		Alien.Role.RAIDER,
		raider_cooldown,
		raider_interval(level),
		raider_limit,
		delta * raider_draw_factor
	)


func _process(delta: float) -> void:
	var wave: float = 0.5 - 0.5 * cos(TAU * _pulse)
	_flare_left = maxf(_flare_left - delta, 0.0)
	var flare: float = 1.0 + ANSWER_FLARE * _flare_left / ANSWER_FLARE_TIME
	var energy: float = lerpf(GLOW_ENERGY_MIN, GLOW_ENERGY_MAX, wave) * flare
	energy *= STAGE_GLOW[mini(stage, STAGE_GLOW.size() - 1)] * _flicker(delta)
	var warning: float = 0.0
	if _warning_left > 0.0:
		warning = 1.0 - _warning_left / settings.burst_warning
	energy += WARNING_GLOW * warning
	var color: Color = COLOR_GLOW.lerp(Color.WHITE, warning).lerp(HUSK_GLOW, _dark)
	_glow.albedo_color = color
	_glow.emission = color
	_glow.emission_energy_multiplier = energy * (1.0 - _dark)
	if _mouth:
		var swell: float = 1.0 + WARNING_SWELL * warning
		_mouth.scale = Vector3.ONE * swell
		_mouth.position = MOUTH_CENTER * (1.0 - swell)


## Lets a pack of hunters (see `HatchTable.pick_pack`) hatch around the nest, one after another
## (the first right away if it may), unless the cap is reached; `boost` times faster for `seconds`
## (an answered scream). Returns its strains (none without a pack that fits).
func hatch_pack(boost: float = 1.0, seconds: float = 0.0) -> Array[AlienStrain]:
	var strains: Array[AlienStrain] = []
	var pack: AlienPack = table.pick_pack(_rng, escalation())
	if not pack or is_full(pack.cap_load()):
		return strains
	strains = pack.aliens()
	for strain: AlienStrain in strains:
		_wait_to_hatch(strain, Alien.Role.HUNTER, boost, seconds)
	_hatch_next()
	return strains


## Hatches an alien of `strain` with `role` at a random spot around the nest, facing away from it.
## Without a strain: one of that role's (see `HatchTable.pick_single`), for hunters one of a pack's.
func hatch(role: Alien.Role, strain: AlienStrain = null) -> Alien:
	if not strain:
		strain = _any_strain(role)
	var alien: Alien = strain.spawn(role)
	alien.health_factor = table.health_factor
	alien.damage_factor = table.damage_factor
	var angle: float = _rng.randf() * TAU
	var direction := Vector3(sin(angle), 0.0, cos(angle))
	alien.position = direction * settings.hatch_radius
	alien.basis = Basis(Vector3.UP, atan2(-direction.x, -direction.z))
	add_child(alien)
	if role != Alien.Role.GUARD:
		var sent_out: Array[Alien] = _hunters if role == Alien.Role.HUNTER else _raiders
		sent_out.append(alien)
		alien.died.connect(func() -> void: sent_out.erase(alien))
	alien.called_for_help.connect(_on_called_for_help)
	if role != Alien.Role.GUARD:
		Sfx.play_at(HATCH_SOUND, _mouth_position(), false, VOICE_PITCH)
	hatched.emit(alien)
	return alien


## Answers a scream: sends its next pack of hunters right away (unless the cap is reached), at most
## every `settings.call_cooldown`, each of them `boost` times faster for `seconds`; its mouth flares
## and a ring sweeps out. Returns the pack's strains (none while it waits).
func answer_call(boost: float = 1.0, seconds: float = 0.0) -> Array[AlienStrain]:
	var pack: Array[AlienStrain] = []
	if _call_cooldown > 0.0:
		return pack
	pack = hatch_pack(boost, seconds)
	if pack.is_empty():
		return pack
	_call_cooldown = settings.call_cooldown
	hunter_cooldown = hunter_interval(escalation())
	_flare_left = ANSWER_FLARE_TIME
	ScreamWave.spawn(get_parent(), global_position, ANSWER_RING)
	return pack


## Whether the hive frenzies: from the mission's storm warning on, and during the storm (never
## without a mission).
func is_frenzied() -> bool:
	if not _find_mission():
		return false
	return _mission.state == Mission.State.STORM or _mission.is_warning()


## How far the hive has escalated, from 0 to 1 (the mission's progress; 0 without a mission).
func escalation() -> float:
	return _mission.progress() if _find_mission() else 0.0


## Whether `share` more (in cap shares) would go over the cap on living aliens and those waiting to
## hatch: nests wait. For `guards`, the guards' own share of it (`AlienNestSettings.guard_share`).
func is_full(share: float = 1.0, guards: bool = false) -> bool:
	if guards:
		var waiting: float = 0.0
		for alien: Alien in get_tree().get_nodes_in_group(Alien.GROUP):
			if alien.role == Alien.Role.GUARD:
				waiting += alien.strain.cap_share
		return waiting + share > settings.alien_cap() * settings.guard_share
	var taken: float = Alien.living_load(get_tree()) + waiting_load(get_tree())
	return taken + share > settings.alien_cap()


## How much the aliens waiting to hatch in every nest count towards the cap.
static func waiting_load(tree: SceneTree) -> float:
	var total: float = 0.0
	for nest: AlienNest in tree.get_nodes_in_group(GROUP):
		total += nest._waiting_load()
	return total


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


## Its health when unhurt: `settings.health`, scaled like the aliens' by the body's tier (its
## `table`) and by the players beyond the first (`settings.health_per_player`).
func max_health() -> float:
	var health: float = settings.health * table.health_factor
	var players: int = get_tree().get_nodes_in_group(Player.GROUP).size()
	return health * (1.0 + settings.health_per_player * maxi(players - 1, 0))


## Whether weapons destroyed it: a husk that hatches nothing more.
func is_destroyed() -> bool:
	return _destroyed


## Whether it's about to burst (its mouth swells and glows white).
func is_warning() -> bool:
	return _warning_left > 0.0


## The hive's surge after another nest was destroyed: sends its next pack of hunters right away
## (while a mission runs, unless the cap is reached). Returns the pack's strains.
func surge() -> Array[AlienStrain]:
	var pack: Array[AlienStrain] = []
	if _destroyed or not (_find_mission() and _mission.is_running()):
		return pack
	pack = hatch_pack()
	if not pack.is_empty():
		hunter_cooldown = hunter_interval(escalation())
	return pack


## How much `aliens` count towards the cap.
static func load_of(aliens: Array[Alien]) -> float:
	var total: float = 0.0
	for alien: Alien in aliens:
		total += alien.strain.cap_share
	return total


## Counts `cooldown` down while the aliens with `role` out (and waiting to hatch) count less than
## `limit`, hatches (a pack of hunters, a raider) at zero and returns the new cooldown. At the
## limit it holds a full `interval`; at the cap it looks again after `CAP_RETRY`.
func _count_down(
	role: Alien.Role, cooldown: float, interval: float, limit: float, delta: float
) -> float:
	var out: Array[Alien] = _hunters if role == Alien.Role.HUNTER else _raiders
	if load_of(out) + _waiting_load(role) >= limit:
		return interval
	cooldown = maxf(cooldown - delta, 0.0)
	if cooldown > 0.0:
		return cooldown
	var hatching: bool = (
		not hatch_pack().is_empty() if role == Alien.Role.HUNTER else _hatch_single(role)
	)
	return interval if hatching else minf(interval, CAP_RETRY)


## Lets one guard or raider (see `HatchTable.pick_single`) hatch unless the cap (for guards, their
## share of it) is reached: guards right away, raiders in turn. Returns whether one does.
func _hatch_single(role: Alien.Role) -> bool:
	var strain: AlienStrain = table.pick_single(_rng, escalation(), role)
	if not strain or is_full(strain.cap_share, role == Alien.Role.GUARD):
		return false
	if role == Alien.Role.GUARD:
		hatch(role, strain)
	else:
		_wait_to_hatch(strain, role)
		_hatch_next()
	return true


## Puts an alien of `strain` in `role` in line to hatch, `boost` times faster for `seconds`.
func _wait_to_hatch(
	strain: AlienStrain, role: Alien.Role, boost: float = 1.0, seconds: float = 0.0
) -> void:
	var waiting := Hatching.new()
	waiting.strain = strain
	waiting.role = role
	waiting.boost = boost
	waiting.seconds = seconds
	_waiting.append(waiting)


## Hatches the next alien waiting, once `settings.hatch_gap` passed since the last one and no
## nest hatched one this physics frame yet.
func _hatch_next() -> void:
	if _waiting.is_empty() or _until_hatch > 0.0 or _hatch_frame == Engine.get_physics_frames():
		return
	_hatch_frame = Engine.get_physics_frames()
	_until_hatch = settings.hatch_gap
	var next: Hatching = _waiting.pop_front()
	var alien: Alien = hatch(next.role, next.strain)
	if next.seconds > 0.0:
		alien.status.boost(next.boost, next.seconds)


## How much the aliens waiting to hatch here count towards the cap; with `role`, only theirs.
func _waiting_load(role: int = -1) -> float:
	var total: float = 0.0
	for waiting: Hatching in _waiting:
		if role < 0 or waiting.role == role:
			total += waiting.strain.cap_share
	return total


## A strain for a single alien with `role`: one of that role's, or one from a pack.
func _any_strain(role: Alien.Role) -> AlienStrain:
	var level: float = escalation()
	if role != Alien.Role.HUNTER:
		var single: AlienStrain = table.pick_single(_rng, level, role)
		if single:
			return single
	var pack: AlienPack = table.pick_pack(_rng, level)
	if pack:
		var members: Array[AlienStrain] = pack.aliens()
		return members[_rng.randi() % members.size()]
	return hive.strains[0]


## How much faster raiders hatch for the working miners whose nearest nest it is: each adds
## `settings.raider_draw`, one on a signature ore `settings.raider_draw_signature`.
func _draw_factor() -> float:
	var factor: float = 1.0
	var nests: Array[Node] = get_tree().get_nodes_in_group(GROUP)
	for miner: Miner in get_tree().get_nodes_in_group(Miner.GROUP):
		if miner.broken or _nearest_nest(nests, miner.global_position) != self:
			continue
		var signature: bool = miner.ore_type and miner.ore_type.band == OreType.Band.SIGNATURE
		factor += settings.raider_draw_signature if signature else settings.raider_draw
	return factor


## The nest of `nests` nearest to `point` (horizontally), or null.
static func _nearest_nest(nests: Array[Node], point: Vector3) -> AlienNest:
	var nearest: AlienNest
	var nearest_distance: float = INF
	for nest: AlienNest in nests:
		var offset: Vector3 = nest.global_position - point
		var distance: float = Vector2(offset.x, offset.z).length()
		if distance < nearest_distance:
			nearest = nest
			nearest_distance = distance
	return nearest


## The nest nearest to a scream answers it.
func _on_called_for_help(at: Vector3, boost: float, seconds: float) -> void:
	var nearest: AlienNest = _nearest_nest(get_tree().get_nodes_in_group(GROUP), at)
	if nearest:
		nearest.answer_call(boost, seconds)


## A hit (or other damage) on its body: its guards go for the attacker, and passing a burst's
## share of its health starts that burst's warning.
func _on_damaged(amount: float, by: Node) -> void:
	var attacker := by as Player
	GameEvents.bus.nest_damaged.emit(body.last_by, body.last_weapon, self, amount)
	if attacker:
		for child: Node in get_children():
			var guard := child as Alien
			if guard and guard.role == Alien.Role.GUARD and not guard.dead:
				guard.status.defending = attacker
	while (
		_bursts_due < settings.bursts
		and body.health <= body.max_health * (1.0 - (_bursts_due + 1.0) / (settings.bursts + 1.0))
	):
		_bursts_due += 1
	if _bursts_due > stage and _warning_left == 0.0 and not body.dead:
		_warn()
	if not body.dead:
		Sfx.play_at(AlienSounds.HIT_SOUND, _mouth_position(), false, VOICE_PITCH)


## Spews `settings.burst_aliens` hunters of its packs' strains, one after another (unless the cap
## is reached), and opens its next crack stage; another burst due starts its warning.
func _burst() -> void:
	for i: int in settings.burst_aliens:
		var strain: AlienStrain = _any_strain(Alien.Role.HUNTER)
		if not is_full(strain.cap_share):
			_wait_to_hatch(strain, Alien.Role.HUNTER)
	_hatch_next()
	stage += 1
	var cracks: Array[GeometryInstance3D] = _cracks()
	for i: int in cracks.size():
		cracks[i].visible = i < stage
	_flare_left = ANSWER_FLARE_TIME
	if _bursts_due > stage:
		_warn()


## Starts a burst's warning: the mouth swells and glows white, groaning.
func _warn() -> void:
	_warning_left = settings.burst_warning
	Sfx.play_at(SWELL_SOUND, _mouth_position())


## Destroyed: no more hatching, no more a nest; its guards stop defending it, the other nests
## surge, and it collapses into a husk.
func _on_destroyed() -> void:
	_destroyed = true
	_warning_left = 0.0
	_waiting.clear()
	remove_from_group(GROUP)
	for child: Node in get_children():
		if child is Alien:
			(child as Alien).status.defending = null
	destroyed.emit()
	GameEvents.bus.nest_destroyed.emit(body.last_by, body.last_weapon, self)
	for nest: AlienNest in get_tree().get_nodes_in_group(GROUP):
		nest.surge()
	Sfx.play_at(DESTROYED_SOUND, _mouth_position())
	_collapse()


## Where its sounds come from: its mouth.
func _mouth_position() -> Vector3:
	return global_transform * MOUTH_CENTER


## The mound sinks in and draws together, the glow goes dark, the body darkens and the slime dries
## grey; its collision sinks with it.
func _collapse() -> void:
	var tween: Tween = create_tween().set_parallel()
	var husk := Vector3(HUSK_SPREAD, HUSK_HEIGHT, HUSK_SPREAD)
	var sinking: PropertyTweener = tween.tween_property(
		_model, ^"scale", husk, settings.collapse_time
	)
	sinking.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, ^"_dark", 1.0, settings.collapse_time)
	for part: String in ["Mound", "Tendrils"]:
		var tint: BaseMaterial3D = _own_material(part)
		if tint:
			tween.tween_property(tint, ^"albedo_color", HUSK_TINT, settings.collapse_time)
	var slime: BaseMaterial3D = _own_material("Slime")
	if slime:
		tween.tween_property(slime, ^"albedo_color", DRY_SLIME, settings.dry_time)
		tween.tween_property(slime, ^"roughness", DRY_ROUGHNESS, settings.dry_time)
	var collision := body.get_node(^"CollisionShape3D") as CollisionShape3D
	var shape := collision.shape.duplicate() as CylinderShape3D
	if shape:
		shape.height *= HUSK_HEIGHT
		collision.shape = shape


## A copy of the `part` mesh's material laid over it, to change for this nest only; or null.
func _own_material(part: String) -> BaseMaterial3D:
	var mesh := _model.find_child(part, true, false) as MeshInstance3D
	if not mesh or not mesh.mesh or mesh.mesh.get_surface_count() == 0:
		return null
	var material := mesh.mesh.surface_get_material(0) as BaseMaterial3D
	if not material:
		return null
	material = material.duplicate() as BaseMaterial3D
	mesh.material_override = material
	return material


## The model's crack meshes in stage order (`Cracks1`, `Cracks2`, ...; none before they're modeled).
func _cracks() -> Array[GeometryInstance3D]:
	var cracks: Array[GeometryInstance3D] = []
	var crack := _model.find_child("Cracks1", true, false) as GeometryInstance3D
	while crack:
		cracks.append(crack)
		var next: String = "Cracks%d" % (cracks.size() + 1)
		crack = _model.find_child(next, true, false) as GeometryInstance3D
	return cracks


## How strong the glow is this frame for the cracked nest's flicker (1 unhurt or between dips).
func _flicker(delta: float) -> float:
	if stage == 0 or _destroyed:
		return 1.0
	_flicker_left = maxf(_flicker_left - delta, 0.0)
	_until_flicker -= delta
	if _until_flicker <= 0.0:
		_until_flicker = _rng.randf_range(0.3, 1.7) * FLICKER_INTERVAL / stage
		_flicker_left = FLICKER_TIME
	return FLICKER_DIP if _flicker_left > 0.0 else 1.0


## Looks the mission up until it's found (it may be set up after the nest).
func _find_mission() -> bool:
	if not is_instance_valid(_mission):
		_mission = get_tree().get_first_node_in_group(Mission.GROUP) as Mission
	return _mission != null
