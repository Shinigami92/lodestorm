class_name SuitRing
extends MeshInstance3D
## The ring the suit projects on the ground around the player (a child of it; see GAME_DESIGN.md,
## UI): everything a player reads in a fight. Its halves stay fixed to the screen: the health arc
## on the left (green, amber below half, red and blinking below a quarter, flashing white on
## damage, a red mark on the outer edge towards where a hit came from), the equipped ammo
## weapon's ammo arc on the right in its ammo color (reloads and a drained battery recharging with
## their timing window, a charge filling it and turning white when full, a red flash when a reload
## can't start, a white one when a timed press finishes it; a vent like a reload), the heat of a
## heat-fed weapon as a thin band outside the ammo arc (amber, red when nearly full, blinking
## while it vents), the spare magazines as ticks inside the ammo arc, the dash as a thin inner
## ring while it recharges, a green outer band while the player hands a teammate ammo, and the
## pointers as arrows on its edge (the way back to the ship from `ShipPointer`, the nearest ore
## from `OreScanner`), and the run's six miners as ticks just outside its bottom (crafted ones
## bright, standard-issue ones dimmer, placed ones as outlines). Both arcs fill from the bottom up.
## Quiet when nothing goes on: an arc dims to a faint outline `lit_time` after its last change,
## unless its value is low (health below half, a nearly empty magazine) or the player set "Always
## show"; the spare ticks show on a reload and when a spare is used. Aboard (weapon holstered) the
## outline hides too. The miners' ticks show for `lit_time` when one is placed or picked up,
## while the player places or picks one up, while it stands next to one, and always with "Always
## show". Its size is a setting (`GameSettings.ring_scale`); while the player's pause panel is open
## it stays shown and lit (also while the world is paused), so a change of size shows right away.
## A teammate's ring (a player that isn't `local`) shows only the health arc inside an outline in
## their player color.
## Tilts with the ground under the player; drawn over the ground and low plants, hidden by cliffs
## and props.

## Seconds it takes an arc to dim or light up.
const FADE_TIME: float = 0.4
## Seconds a hit's mark and a flash last.
const HIT_TIME: float = 1.0
const FLASH_TIME: float = 0.35
## Seconds the dash ring stays after it's ready again.
const DASH_READY_TIME: float = 0.3
## A magazine is nearly empty at this share or less (like the last of the weapon's six segments).
const NEARLY_EMPTY: float = 1.0 / 6.0
## Rounds shown as segments up to this many, as one bar beyond.
const MAX_SEGMENTS: int = 16
## Brightness of a blinking arc between its blinks (it never goes dark: its length still reads).
const BLINK_DIM: float = 0.55
const FILL_ALPHA: float = 0.9
const DASH_COLOR := Color(1.0, 0.93, 0.8, FILL_ALPHA)
const GIVE_COLOR := Color(0.35, 1.0, 0.45, FILL_ALPHA)
const FUMBLE_COLOR := Color(1.0, 0.12, 0.08, FILL_ALPHA)
const HEAT_COLOR := Color(1.0, 0.6, 0.15, FILL_ALPHA)
## Heat from which the heat band turns red.
const HEAT_HIGH: float = 0.7
const HIT_MARKS: int = 4
## Pointers on the edge at most (the ship, the ore scanner, later the tracked quest).
const POINTERS: int = 3
## Where the pointers' arrows start beyond `radius` (m), and per kind how far beyond it their tip
## reaches and half their width at the base (m). TBD (playtest).
const POINTER_BASE: float = 0.32
const SHIP_ARROW := Vector2(1.04, 0.38)
const SCANNER_ARROW := Vector2(0.84, 0.26)
## Distance from the ship arrow's tip to the countdown's center (m).
const COUNTDOWN_GAP: float = 0.25
## The miners' ticks: a standard-issue miner's tick, and a crafted one's, aboard (negative:
## placed); and how bright a standard-issue one is.
const STANDARD_TICK: float = 1.0
const CRAFTED_TICK: float = 2.0
const STANDARD_DIM: float = 0.55

## Outer radius of the arcs (m); the plane reaches a little farther for the marks. TBD (playtest).
@export var radius: float = 1.36
## Seconds an arc stays lit after a change. TBD (playtest).
@export var lit_time: float = 3.0

## The health arc's and the ammo arc's light (0: dimmed to the outline, 1: lit).
var health_glow: float = 1.0
var ammo_glow: float = 1.0
## How much the spare ticks and the dash ring show (0: hidden).
var spares_alpha: float = 0.0
var dash_alpha: float = 0.0
## How much the miners' ticks show (0: hidden), and what each tick shows (see `CRAFTED_TICK`).
var miners_alpha: float = 0.0
var miner_ticks := PackedFloat32Array()
## Where the hits' marks point (shares of the circle clockwise from the screen's top) and how
## strong they still are.
var hits: PackedVector2Array = []
## The pointers shown: where each points (share of the circle), its alpha, its tip's radius and
## half its width, in the ring's own meters (before its size setting).
var pointers: PackedVector4Array = []

var _material := ShaderMaterial.new()
var _health_lit: float = 0.0
var _ammo_lit: float = 0.0
var _spares_lit: float = 0.0
var _dash_lit: float = 0.0
var _miners_lit: float = 0.0
var _last_health: float = -1.0
var _last_ammo: WeaponAmmo
var _last_rounds: int = -1
var _last_spares: int = -1
var _was_reloading: bool = false
var _flash_color := Color.WHITE
var _flash_left: float = 0.0
var _damage_flash_left: float = 0.0
var _next_damage_flash: float = 0.0
## World directions the hits came from, with the seconds each mark has left.
var _hit_directions: Array[Vector3] = []
var _hit_left: PackedFloat32Array = []
var _up := Vector3.UP

@onready var _player: Player = get_parent() as Player


func _ready() -> void:
	top_level = true
	# Runs while the pause panel stops the world, so the panel previews the ring's settings.
	process_mode = Node.PROCESS_MODE_ALWAYS
	var outer: float = radius + SHIP_ARROW.x + 0.04
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * outer * 2.0
	mesh = plane
	_material.shader = preload("res://assets/shaders/suit_ring.gdshader")
	_material.set_shader_parameter(&"radius", outer)
	_material.set_shader_parameter(&"arc_band", Vector2(radius - 0.2, radius))
	_material.set_shader_parameter(&"spare_band", Vector2(radius - 0.35, radius - 0.24))
	_material.set_shader_parameter(&"dash_band", Vector2(radius - 0.44, radius - 0.4))
	_material.set_shader_parameter(&"give_band", Vector2(radius + 0.06, radius + 0.14))
	_material.set_shader_parameter(&"hit_band", Vector2(radius + 0.06, radius + 0.24))
	_material.set_shader_parameter(&"team_band", Vector2(radius + 0.03, radius + 0.1))
	_material.set_shader_parameter(&"heat_band", Vector2(radius + 0.025, radius + 0.075))
	_material.set_shader_parameter(&"miner_band", Vector2(radius + 0.06, radius + 0.24))
	_material.set_shader_parameter(&"miner_color", Color(OccludedSilhouette.MINER_COLOR, 1.0))
	_material.set_shader_parameter(&"standard_dim", STANDARD_DIM)
	_material.set_shader_parameter(&"pointer_base", radius + POINTER_BASE)
	_material.set_shader_parameter(&"dash_color", DASH_COLOR)
	_material.set_shader_parameter(&"give_color", GIVE_COLOR)
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_player.vitals.hurt.connect(_on_hurt)
	visible = false


## Flashes the ammo arc in `color` for a moment (a reload that can't start, a timed finish).
func flash(color: Color) -> void:
	_flash_color = color
	_flash_left = FLASH_TIME
	_ammo_lit = lit_time


## The value of one of its shader's parameters (what it shows, for tests and probes).
func shown(parameter: StringName) -> Variant:
	return _material.get_shader_parameter(parameter)


## Whether the ammo arc shows (a fed weapon is drawn, on the local player's ring).
func shows_ammo() -> bool:
	var ammo: WeaponAmmo = _player.get_ammo()
	return ammo != null and _player.weapon.visible and _player.local


## How far the ship arrow's tip reaches from the player (m, with the size setting).
func pointer_reach() -> float:
	return (radius + SHIP_ARROW.x) * GameSettings.ring_scale()


func _process(delta: float) -> void:
	visible = not _player.dead and (not _player.menu or previewing())
	if not visible:
		_flash_left = 0.0
		_hit_directions.clear()
		_hit_left.clear()
		return
	_flash_left = maxf(_flash_left - delta, 0.0)
	_damage_flash_left = maxf(_damage_flash_left - delta, 0.0)
	_next_damage_flash = maxf(_next_damage_flash - delta, 0.0)
	var blink_on: bool = fmod(Time.get_ticks_msec() * 0.001 * SuitLight.BLINK_RATE, 1.0) < 0.5
	_update_health(delta, blink_on)
	_update_ammo(delta, blink_on)
	_update_dash(delta)
	_update_miners(delta)
	_update_give()
	_update_hits(delta)
	_update_pointers()
	var outside: float = 1.0 if _player.weapon_allowed or previewing() else 0.0
	_material.set_shader_parameter(&"outline_alpha", outside)
	_material.set_shader_parameter(&"team_alpha", 0.0 if _player.local else outside)
	_material.set_shader_parameter(&"team_color", Color(_player.color(), FILL_ALPHA))
	_place(delta)


func _update_health(delta: float, blink_on: bool) -> void:
	var share: float = _player.health / _player.max_health()
	if not is_equal_approx(_player.health, _last_health):
		_last_health = _player.health
		_health_lit = lit_time
	_health_lit = maxf(_health_lit - delta, 0.0)
	var color: Color = SuitLight.COLOR_HEALTHY
	if share < 0.25:
		color = SuitLight.COLOR_CRITICAL
		if not blink_on:
			color = color.darkened(1.0 - BLINK_DIM)
	elif share < 0.5:
		color = SuitLight.COLOR_HURT
	if _damage_flash_left > 0.0:
		color = SuitLight.COLOR_FLASH
	color.a = FILL_ALPHA
	health_glow = _fade(health_glow, _health_lit > 0.0 or share < 0.5 or _always(), delta)
	_material.set_shader_parameter(&"health_fill", share)
	_material.set_shader_parameter(&"health_color", color)
	_material.set_shader_parameter(&"health_glow", health_glow)


func _update_ammo(delta: float, blink_on: bool) -> void:
	var ammo: WeaponAmmo = _player.get_ammo()
	var drawn: bool = shows_ammo()
	_material.set_shader_parameter(&"ammo_alpha", 1.0 if drawn else 0.0)
	if not drawn:
		_last_ammo = null
		ammo_glow = 0.0
		spares_alpha = 0.0
		_material.set_shader_parameter(&"spare_alpha", 0.0)
		_material.set_shader_parameter(&"heat_alpha", 0.0)
		return
	var capacity: int = ammo.capacity()
	var refilling: bool = ammo.refilling()
	var charge: float = _player.weapon.charge()
	if ammo != _last_ammo or ammo.rounds != _last_rounds or refilling or charge > 0.0:
		_ammo_lit = lit_time
	var started: bool = refilling and not _was_reloading
	if ammo != _last_ammo or ammo.spare_rounds != _last_spares or started:
		_spares_lit = lit_time
	if refilling:
		_spares_lit = maxf(_spares_lit, FADE_TIME)
	_last_ammo = ammo
	_last_rounds = ammo.rounds
	_last_spares = ammo.spare_rounds
	_was_reloading = refilling
	_ammo_lit = maxf(_ammo_lit - delta, 0.0)
	_spares_lit = maxf(_spares_lit - delta, 0.0)

	var share: float = float(ammo.rounds) / capacity
	var low: bool = share <= NEARLY_EMPTY
	var gauge: AmmoGauge = _player.weapon.get_gauge()
	var color: Color = gauge.color if gauge else Color.WHITE
	color.a = FILL_ALPHA
	var single: bool = ammo.is_single()
	var segments: int = capacity if capacity <= MAX_SEGMENTS else 0
	var fill: float = share
	var window := Vector2(1.0, 0.0)
	var loading: int = -1
	var loading_color := color
	if refilling and not single:
		fill = ammo.refill_share()
		segments = 0
		if ammo.fumbled:
			color = FUMBLE_COLOR
		else:
			window = ammo.timing_window()
	elif refilling and ammo.rounds < capacity:
		var reload_share: float = ammo.refill_share()
		var in_window: bool = ammo.in_window(reload_share)
		loading = ammo.rounds
		loading_color = (
			FUMBLE_COLOR if ammo.fumbled else (AmmoGauge.TIMING if in_window else color)
		)
		loading_color.a = FILL_ALPHA * clampf(reload_share, 0.15, 1.0)
		if segments == 0:
			# One bar: the round being loaded grows it.
			fill = (ammo.rounds + clampf(reload_share, 0.0, 1.0)) / capacity
			color = color.lerp(loading_color, 0.5)
	elif ammo.rounds == 0 and not ammo.can_reload():
		fill = 1.0
		color = AmmoGauge.EMPTY if blink_on else AmmoGauge.EMPTY.darkened(1.0 - BLINK_DIM)
		color.a = FILL_ALPHA * 0.6
	elif charge > 0.0:
		# The charge fills the arc like a reload, white once it's full.
		fill = charge
		segments = 0
		if charge >= 1.0:
			color = AmmoGauge.TIMING
			color.a = FILL_ALPHA
	elif low and ammo.rounds > 0:
		color = AmmoGauge.WARNING if blink_on else AmmoGauge.WARNING.darkened(1.0 - BLINK_DIM)
		color.a = FILL_ALPHA
	if _flash_left > 0.0:
		fill = 1.0
		segments = 0
		window = Vector2(1.0, 0.0)
		color = _flash_color
		color.a = FILL_ALPHA * _flash_left / FLASH_TIME
	ammo_glow = _fade(ammo_glow, _ammo_lit > 0.0 or low or _always(), delta)
	spares_alpha = _fade(spares_alpha, _spares_lit > 0.0 or _always(), delta)
	var spare_color: Color = gauge.color if gauge else Color.WHITE
	spare_color.a = FILL_ALPHA
	_material.set_shader_parameter(&"ammo_fill", fill)
	_material.set_shader_parameter(&"ammo_color", color)
	_material.set_shader_parameter(&"ammo_glow", ammo_glow)
	_material.set_shader_parameter(&"ammo_segments", segments)
	_material.set_shader_parameter(&"ammo_window", window)
	_material.set_shader_parameter(&"loading_segment", loading)
	_material.set_shader_parameter(&"loading_color", loading_color)
	_material.set_shader_parameter(&"spare_alpha", spares_alpha)
	_material.set_shader_parameter(
		&"spare_slots", _player.spare_magazines if ammo.uses_spares() else 0
	)
	_material.set_shader_parameter(&"spare_fill", float(ammo.spare_rounds) / capacity)
	_material.set_shader_parameter(&"spare_color", spare_color)
	_update_heat(ammo, blink_on)


## The heat band: amber, turning red as it nears full, blinking while it vents.
func _update_heat(ammo: WeaponAmmo, blink_on: bool) -> void:
	var heat: float = ammo.heat_share()
	var color: Color = HEAT_COLOR.lerp(FUMBLE_COLOR, smoothstep(HEAT_HIGH, 1.0, heat))
	if ammo.refilling() and not blink_on:
		color = color.darkened(1.0 - BLINK_DIM)
	_material.set_shader_parameter(&"heat_alpha", ammo_glow if heat > 0.0 else 0.0)
	_material.set_shader_parameter(&"heat_fill", heat)
	_material.set_shader_parameter(&"heat_color", color)


func _update_dash(delta: float) -> void:
	var ratio: float = _player.suit_dash.ready_ratio()
	var learned: bool = _player.skills.has(Skill.Effect.DASH) and _player.local
	if learned and ratio < 1.0:
		_dash_lit = DASH_READY_TIME
	else:
		_dash_lit = maxf(_dash_lit - delta, 0.0)
	dash_alpha = 1.0 if _dash_lit > 0.0 else 0.0
	_material.set_shader_parameter(&"dash_alpha", dash_alpha)
	_material.set_shader_parameter(&"dash_fill", ratio)


## The run's miners: crafted ones going along first (by number), then standard-issue ones.
func _update_miners(delta: float) -> void:
	var fleet: MinerFleet = _player.fleet
	var ticks := PackedFloat32Array()
	for miner: CraftedMiner in fleet.along():
		ticks.append(-CRAFTED_TICK if miner.out else CRAFTED_TICK)
	for index: int in fleet.standard_count():
		ticks.append(-STANDARD_TICK if index < fleet.standard_out else STANDARD_TICK)
	ticks.resize(MinerFleet.PER_RUN)
	if ticks != miner_ticks:
		if not miner_ticks.is_empty():
			_miners_lit = lit_time
		miner_ticks = ticks
	_miners_lit = maxf(_miners_lit - delta, 0.0)
	var showing: bool = (
		_player.local
		and (_player.weapon_allowed or previewing())
		and (_miners_lit > 0.0 or _player.handling.busy() or _next_to_miner() or _always())
	)
	miners_alpha = _fade(miners_alpha, showing, delta)
	_material.set_shader_parameter(&"miner_alpha", miners_alpha)
	_material.set_shader_parameter(&"miner_ticks", miner_ticks)


## Whether a miner stands within its repair range of the player.
func _next_to_miner() -> bool:
	for node: Node in get_tree().get_nodes_in_group(Miner.GROUP):
		var miner := node as Miner
		var offset: Vector3 = miner.global_position - _player.global_position
		if Vector2(offset.x, offset.z).length() <= miner.settings.repair_range:
			return true
	return false


func _update_give() -> void:
	var giving: bool = _player.give_ammo_target != null and _player.local
	_material.set_shader_parameter(&"give_alpha", 1.0 if giving else 0.0)
	if giving:
		_material.set_shader_parameter(
			&"give_fill", _player.give_ammo_time / _player.settings.give_ammo_time
		)


func _update_hits(delta: float) -> void:
	var marks := PackedVector2Array()
	marks.resize(HIT_MARKS)
	hits.clear()
	var i: int = _hit_left.size() - 1
	while i >= 0:
		_hit_left[i] -= delta
		if _hit_left[i] <= 0.0:
			_hit_left.remove_at(i)
			_hit_directions.remove_at(i)
		i -= 1
	for index: int in _hit_left.size():
		var mark := Vector2(_share_towards(_hit_directions[index]), _hit_left[index] / HIT_TIME)
		marks[index] = mark
		hits.append(mark)
	_material.set_shader_parameter(&"hits", marks)


## The arrows on the edge: the way back to the ship, then the ore scanner's.
func _update_pointers() -> void:
	pointers.clear()
	var colors := PackedColorArray()
	colors.resize(POINTERS)
	var slots := PackedVector4Array()
	slots.resize(POINTERS)
	if _player.local:
		var ship := _player.get_node_or_null(^"ShipPointer") as ShipPointer
		if ship and ship.is_visible_in_tree():
			colors[pointers.size()] = ship.color
			pointers.append(_pointer(-ship.global_basis.z, SHIP_ARROW))
		var scanner := _player.get_node_or_null(^"OreScanner") as OreScanner
		if scanner and scanner.is_visible_in_tree():
			colors[pointers.size()] = scanner.color
			pointers.append(_pointer(-scanner.global_basis.z, SCANNER_ARROW))
	for index: int in pointers.size():
		slots[index] = pointers[index]
	_material.set_shader_parameter(&"pointers", slots)
	_material.set_shader_parameter(&"pointer_colors", colors)


## A pointer towards `direction` with the shape `arrow` (see `SHIP_ARROW`).
func _pointer(direction: Vector3, arrow: Vector2) -> Vector4:
	return Vector4(_share_towards(direction), 1.0, radius + arrow.x, arrow.y)


## Follows the player's feet, tilted with the ground; its top stays at the top of the screen.
func _place(delta: float) -> void:
	if _player.is_on_floor():
		_up = tilt_towards(_up, _player.get_floor_normal(), 1.0 - exp(-10.0 * delta))
	global_position = _player.global_position + _up * 0.05
	var forward: Vector3 = _screen_up()
	forward = (forward - _up * forward.dot(_up)).normalized()
	if forward.length() > 0.001:
		global_basis = (
			Basis.looking_at(forward, _up)
			* Basis.from_scale(Vector3.ONE * GameSettings.ring_scale())
		)


## The ground direction towards the screen's top (away from the camera).
func _screen_up() -> Vector3:
	var camera: Camera3D = get_viewport().get_camera_3d()
	var forward := Vector3.FORWARD
	if camera:
		forward = -camera.global_basis.z
		forward.y = 0.0
	return forward.normalized() if forward.length() > 0.001 else Vector3.FORWARD


## The share of the circle (clockwise from the screen's top, seen from above) towards `direction`.
func _share_towards(direction: Vector3) -> float:
	var up: Vector3 = _screen_up()
	var right: Vector3 = up.cross(Vector3.UP)
	return fposmod(atan2(direction.dot(right), direction.dot(up)) / TAU, 1.0)


## A hit (damage) lights up the health arc and flashes it white (under steady damage, like the
## storm's, a pulse every `SuitLight.FLASH_INTERVAL`); one from `from` marks where it came from.
func _on_hurt(_amount: float, from: Vector3) -> void:
	_health_lit = lit_time
	if _next_damage_flash <= 0.0:
		_damage_flash_left = SuitLight.FLASH_DURATION
		_next_damage_flash = SuitLight.FLASH_INTERVAL
	if not from.is_finite() or not _player.local:
		return
	var direction: Vector3 = from - _player.global_position
	direction.y = 0.0
	if direction.length() < 0.01:
		return
	if _hit_left.size() >= HIT_MARKS:
		_hit_left.remove_at(0)
		_hit_directions.remove_at(0)
	_hit_directions.append(direction.normalized())
	_hit_left.append(HIT_TIME)


## The ring's up direction `up` turned by `weight` towards the ground's `normal`. A lerp, not a
## slerp: slerp errors on vectors a hair apart (the floor normal settling on flat ground).
static func tilt_towards(up: Vector3, normal: Vector3, weight: float) -> Vector3:
	return up.lerp(normal, weight).normalized()


## Whether its player's pause panel is open: the ring stays shown and lit meanwhile.
func previewing() -> bool:
	return _player.menu != null and _player.menu == _player.pause_panel


## Whether the arcs, the spare ticks and the miners' ticks stay lit (the "Always show" setting,
## or the pause panel's preview).
func _always() -> bool:
	return GameSettings.ring_always_show or previewing()


## Moves `glow` towards 1 while `lit`, else towards 0, over `FADE_TIME`.
static func _fade(glow: float, lit: bool, delta: float) -> float:
	return move_toward(glow, 1.0 if lit else 0.0, delta / FADE_TIME)
