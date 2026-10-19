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
## Aliens hatch stronger on bodies farther in (see `MissionSettings.alien_health_at`). Nests wait
## while the living aliens reach the cap (`AlienNestSettings.alien_cap`).
## Weapons wear it down (its `body`, a `Destructible`: health and armor, scaled like the aliens'
## and per player). A hit calls its guards to go for the attacker. On the way down it bursts
## (`AlienNestSettings.bursts`): its mouth swells and glows white for a warning, then it spews
## hunters, and cracks open in its plates (the model's `Cracks1`, `Cracks2`, ...) while its glow
## flickers lower. When it's destroyed it collapses inwards, the glow goes dark and its slime dries
## grey: the husk stays, hatches nothing more and is no nest any more (it leaves `GROUP`); its
## aliens stay, and every other nest sends its next pack right away (the hive's surge).

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
	_pulse = fmod(_pulse + delta * lerpf(PULSE_RATE_CALM, PULSE_RATE_FRENZY, pulse_level), 1.0)
	_call_cooldown = maxf(_call_cooldown - delta, 0.0)
	var speed: float = settings.frenzy_speed if frenzied else 1.0
	for child: Node in get_children():
		if child is Alien:
			(child as Alien).status.hive_speed = speed
	if _warning_left > 0.0:
		_warning_left = maxf(_warning_left - delta, 0.0)
		if _warning_left == 0.0:
			_burst()
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


## Hatches a pack of hunters (see `HatchTable.pick_pack`) around the nest, unless the cap is
## reached. Returns its aliens (none without a pack that fits).
func hatch_pack() -> Array[Alien]:
	var hatching: Array[Alien] = []
	var pack: AlienPack = table.pick_pack(_rng, escalation())
	if not pack or is_full(pack.cap_load()):
		return hatching
	for strain: AlienStrain in pack.aliens():
		hatching.append(hatch(Alien.Role.HUNTER, strain))
	return hatching


## Hatches an alien of `strain` with `role` at a random spot around the nest, facing away from it.
## Without a strain: one of that role's (see `HatchTable.pick_single`), for hunters one of a pack's.
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
	alien.called_for_help.connect(_on_called_for_help)
	hatched.emit(alien)
	return alien


## Answers a scream: sends its next pack of hunters right away (unless the cap is reached), at most
## every `settings.call_cooldown`, each of them `boost` times faster for `seconds`; its mouth flares
## and a ring sweeps out. Returns the pack (none while it waits).
func answer_call(boost: float = 1.0, seconds: float = 0.0) -> Array[Alien]:
	var pack: Array[Alien] = []
	if _call_cooldown > 0.0:
		return pack
	pack = hatch_pack()
	if pack.is_empty():
		return pack
	_call_cooldown = settings.call_cooldown
	hunter_cooldown = hunter_interval(escalation())
	for alien: Alien in pack:
		alien.status.boost(boost, seconds)
	_flare_left = ANSWER_FLARE_TIME
	ScreamWave.spawn(get_parent(), global_position, ANSWER_RING)
	return pack


## Whether the hive frenzies: from the mission's storm warning on, and during the storm (never
## without a mission).
func is_frenzied() -> bool:
	if not _find_mission():
		return false
	if _mission.state == Mission.State.STORM:
		return true
	return _mission.state == Mission.State.RUNNING and _mission.time_left <= _mission.warning_time()


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


## Its health when unhurt: `settings.health`, scaled like the aliens' by the mission's tier and by
## the players beyond the first (`settings.health_per_player`).
func max_health() -> float:
	var health: float = settings.health
	if _find_mission():
		health *= _mission.settings.alien_health_at(_mission.tier())
	var players: int = get_tree().get_nodes_in_group(Player.GROUP).size()
	return health * (1.0 + settings.health_per_player * maxi(players - 1, 0))


## Whether weapons destroyed it: a husk that hatches nothing more.
func is_destroyed() -> bool:
	return _destroyed


## Whether it's about to burst (its mouth swells and glows white).
func is_warning() -> bool:
	return _warning_left > 0.0


## The hive's surge after another nest was destroyed: sends its next pack of hunters right away
## (while a mission runs, unless the cap is reached). Returns the pack.
func surge() -> Array[Alien]:
	var pack: Array[Alien] = []
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
	var hatching: bool = (
		not hatch_pack().is_empty() if role == Alien.Role.HUNTER else _hatch_single(role) != null
	)
	return interval if hatching else cooldown


## Hatches one guard or raider (see `HatchTable.pick_single`) unless the cap (for guards, their
## share of it) is reached. Returns it, or null.
func _hatch_single(role: Alien.Role) -> Alien:
	var strain: AlienStrain = table.pick_single(_rng, escalation(), role)
	if not strain or is_full(strain.cap_share, role == Alien.Role.GUARD):
		return null
	return hatch(role, strain)


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
func _on_damaged(_amount: float, by: Node) -> void:
	var attacker := by as Player
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
		_warning_left = settings.burst_warning


## Spews `settings.burst_aliens` hunters of its packs' strains (unless the cap is reached) and opens
## its next crack stage; another burst due starts its warning.
func _burst() -> void:
	for i: int in settings.burst_aliens:
		var strain: AlienStrain = _any_strain(Alien.Role.HUNTER)
		if not is_full(strain.cap_share):
			hatch(Alien.Role.HUNTER, strain)
	stage += 1
	var cracks: Array[GeometryInstance3D] = _cracks()
	for i: int in cracks.size():
		cracks[i].visible = i < stage
	_flare_left = ANSWER_FLARE_TIME
	if _bursts_due > stage:
		_warning_left = settings.burst_warning


## Destroyed: no more hatching, no more a nest; its guards stop defending it, the other nests
## surge, and it collapses into a husk.
func _on_destroyed() -> void:
	_destroyed = true
	_warning_left = 0.0
	remove_from_group(GROUP)
	for child: Node in get_children():
		if child is Alien:
			(child as Alien).status.defending = null
	destroyed.emit()
	for nest: AlienNest in get_tree().get_nodes_in_group(GROUP):
		nest.surge()
	_collapse()


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
