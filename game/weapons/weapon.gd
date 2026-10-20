class_name Weapon
extends Node3D
## A weapon of a `WeaponType` (made by `WeaponType.create`), held by a player or shown on a station.
## While the trigger is held and it's drawn, it attacks at its attack rate, or as its type's trigger
## says (`WeaponTrigger`: per press, after spinning up, a charge let go): a fed weapon uses a round
## of its `ammo` (see `WeaponAmmo`), then its type's delivery reaches the targets (`WeaponDelivery`:
## projectiles, lobbed shells and charges, a swing) and its effects make the hits (`make_hit`). The
## holder sets `trigger_held`, `aim_direction`, `aim_target` and `aim_point`; weapons don't read
## input. The MK levels of its parts (`apply_upgrades`) scale its values (`multiplier`) and light
## their pips. After a switch it's drawn (`draw`): the model swings up from the hip for the type's
## draw time. Each attack plays the type's `attack_sound` at the weapon.

## Emitted after every swing (a melee delivery) with the aliens it hit.
@warning_ignore("unused_signal")
signal swung(hits: Array[Alien])

## How the model starts when drawn: tipped down and lower, as from the hip (radians around X, m).
const DRAW_TILT: float = -1.1
const DRAW_DROP := Vector3(0.0, -0.15, 0.1)

## What it is; set by `WeaponType.create`.
var type: WeaponType
## Its rounds and reloads; null for a melee weapon. Set by `WeaponType.create`.
var ammo: WeaponAmmo
## The body carrying the weapon, set when it's equipped.
var holder: CollisionObject3D
var trigger_held: bool = false
## Horizontal unit vector the weapon attacks along.
var aim_direction: Vector3 = Vector3.FORWARD
## The alien or `Destructible` the holder locked on, or null: attacks go straight at it, up or
## down slopes too (see `PlayerAim`).
var aim_target: Node3D
## The spot on the ground the holder points at (the mouse cursor), or `Vector3.INF` when it aims by
## a direction only: a lobbed shot lands there (see `LobDelivery`).
var aim_point: Vector3 = Vector3.INF
## How far its trigger has wound up, 0 to 1: barrels spinning, a charge (see `WeaponTrigger`).
var wind: float = 0.0
## Share of a full attack's power of the attack being made (a partial charge), scaling its hits.
var power: float = 1.0
## Seconds since the trigger was let go; 0 while it's held.
var released_for: float = INF

## How much the MK level of each part scales its value; missing ones are 1.
var _multipliers: Dictionary[WeaponPart.Stat, float] = {}
## Seconds until the next attack. Keeps the remainder after an attack, so the average attack
## rate doesn't depend on the physics tick rate.
var _cooldown: float = 0.0
## Seconds until it's drawn.
var _draw_left: float = 0.0
var _draw_tween: Tween
var _sweep: Tween
var _was_held: bool = false
## The trigger's loop playing (a spin, a charge), or null.
var _loop: AudioStreamPlayer3D


func _physics_process(delta: float) -> void:
	if ammo:
		ammo.process(delta)
	_draw_left = maxf(_draw_left - delta, 0.0)
	_cooldown -= delta
	var pressed: bool = trigger_held and not _was_held
	_was_held = trigger_held
	released_for = 0.0 if trigger_held else released_for + delta
	var able: bool = _cooldown <= 0.0 and is_drawn() and (not ammo or ammo.can_attack())
	var attacks: bool = trigger_held
	if type.trigger:
		attacks = type.trigger.update(self, delta, able, pressed)
	if attacks and able:
		if ammo:
			ammo.use()
		type.delivery.attack(self)
		play(type.attack_sound)
		_cooldown += 1.0 / attack_rate()
	else:
		_cooldown = maxf(_cooldown, 0.0)
	power = 1.0


func _process(_delta: float) -> void:
	var gauge: AmmoGauge = get_gauge()
	if ammo and gauge:
		gauge.show_state(ammo)


## Applies the MK levels in `upgrades` of its parts: the values they scale and their pips. Works
## before the weapon enters the tree.
func apply_upgrades(upgrades: Upgrades) -> void:
	_multipliers.clear()
	for part: WeaponPart in type.parts:
		_multipliers[part.stat] = upgrades.multiplier(part)
		var pips := get_node_or_null(NodePath(part.pips_name())) as MkPips
		if pips:
			pips.show_level(upgrades.mk(part), part.max_mk())
	if ammo:
		ammo.upgraded()


## How much the MK level of its part improving `stat` scales that value (1 without such a part).
func multiplier(stat: WeaponPart.Stat) -> float:
	return _multipliers.get(stat, 1.0)


## Attacks per second, with the MK level of its rate.
func attack_rate() -> float:
	return type.attack_rate * multiplier(WeaponPart.Stat.RATE)


## Starts drawing it: it can't attack for the type's draw time while the model swings up. Cancels
## a reload and a charge.
func draw() -> void:
	_draw_left = type.draw_time
	stop()
	if ammo:
		ammo.cancel_reload()
	if _draw_tween:
		_draw_tween.kill()
	if _draw_left <= 0.0:
		return
	rotation.x = DRAW_TILT
	position = DRAW_DROP
	_draw_tween = create_tween().set_parallel().set_ease(Tween.EASE_OUT)
	_draw_tween.set_trans(Tween.TRANS_CUBIC)
	_draw_tween.tween_property(self, ^"rotation:x", 0.0, _draw_left)
	_draw_tween.tween_property(self, ^"position", Vector3.ZERO, _draw_left)


func is_drawn() -> bool:
	return _draw_left <= 0.0


## Lets go of the trigger without attacking (holstered, the holder down): a charge is lost and
## spinning barrels stop.
func stop() -> void:
	trigger_held = false
	_was_held = false
	wind = 0.0
	stop_loop()


## Share of the holder's top speed while it's used (spinning barrels slow them).
func move_share() -> float:
	return type.trigger.move_share(self) if type.trigger else 1.0


## How far the attack being charged is, 0 to 1 (0 when it doesn't charge).
func charge() -> float:
	return type.trigger.charge(self) if type.trigger else 0.0


## The direction an attack leaves the muzzle in: along the aim, or straight at the locked target
## (up or down a slope too).
func shot_direction() -> Vector3:
	var muzzle: Marker3D = get_muzzle()
	if muzzle and PlayerAim.is_lockable(aim_target):
		return muzzle.global_position.direction_to(PlayerAim.aim_point(aim_target))
	return aim_direction


## A hit along `direction` landing at `point`, made by the type's effects.
func make_hit(direction: Vector3, point: Vector3) -> Hit:
	var hit := Hit.new(0.0, 0.0, 0.0, direction, point, holder)
	for effect: WeaponEffect in type.effects:
		effect.add_to(hit, self)
	return hit


## Where projectiles leave it.
func get_muzzle() -> Marker3D:
	return get_node_or_null(^"Muzzle") as Marker3D


## The display of its ammo on the weapon (a child named `AmmoGauge`), or null.
func get_gauge() -> AmmoGauge:
	return get_node_or_null(^"AmmoGauge") as AmmoGauge


## Sweeps the model (`Model`) through `arc` radians around the grip within `duration` seconds and
## back, a stand-in for a swing animation.
func sweep(arc: float, duration: float) -> void:
	var model := get_node_or_null(^"Model") as Node3D
	if not model:
		return
	if _sweep:
		_sweep.kill()
	model.rotation.y = arc * 0.5
	_sweep = create_tween()
	_sweep.tween_property(model, ^"rotation:y", -arc * 0.5, duration * 0.4)
	_sweep.tween_property(model, ^"rotation:y", 0.0, duration * 0.6)


## Plays `sound` at the weapon. A `cue` (the reload's timing) is only for the local player
## holding it, and a `critical` one always plays and ducks the rest (see `Sfx`).
func play(sound: Sound, cue: bool = false, critical: bool = false) -> void:
	var local: bool = holder is Player and (holder as Player).local
	if cue and not local:
		return
	Sfx.play_at(sound, global_position, critical and local)


## Keeps `sound` looping at the weapon at `pitch` times its pitch (barrels spinning, a charge),
## starting it when it isn't playing yet. One loop at a time.
func hold_loop(sound: Sound, pitch: float) -> void:
	if not sound:
		return
	if not is_instance_valid(_loop):
		_loop = Sfx.play_loop_at(sound, self)
	_loop.pitch_scale = pitch


## Stops the loop of `hold_loop`.
func stop_loop() -> void:
	Sfx.stop_loop(_loop)
	_loop = null
