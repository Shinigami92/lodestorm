class_name RangedWeapon
extends Weapon
## Fires projectiles from the muzzle per attack: along the aim direction, or straight at the locked
## target. With several pellets per shot (`settings.pellets`) they fly in an even fan
## (`settings.spread`) around that direction.
## Each shot uses one of its `rounds`; a full magazine holds `capacity()` (more with the magazine's
## MK level). `reload` refills it, also automatically once it runs empty: from its spare magazines
## (`spare_rounds`, from the ship's stock) while it has any, then with ammo the holder's suit makes
## from carried ore (`OreAmmo`, paid per round loaded); aboard it's free. A magazine
## reload throws away the rounds left in it and fills the whole magazine (the reload can't fire;
## with `careful`, it keeps them and only tops the magazine up);
## a single-round reload loads one round after another until it's full and stops when it fires.
## Pressing `reload` again during a reload (the round being loaded) is the timing press: within the
## window it finishes right away, outside it the reload takes longer. Single rounds loaded within
## the window in a row get quicker. A display child named `AmmoGauge` shows all this on the weapon.

## Emitted when the loaded rounds change.
signal rounds_changed(rounds: int)
## Emitted when a reload can't start although the magazine isn't full: no spares and no ore to pay
## more rounds than it holds.
signal reload_denied
## Emitted after the timing press of a reload: whether it was within the window.
signal reload_timed(hit: bool)

@export var settings: RangedWeaponSettings
@export var projectile_scene: PackedScene

## Rounds in the spare magazines (with `ReloadMode.SINGLE`, spare rounds); reloads use them
## before ore.
var spare_rounds: int = 0
## Rounds loaded.
var rounds: int = 0:
	set(value):
		if value == rounds:
			return
		rounds = value
		rounds_changed.emit(rounds)
## Scales the magazine from the settings, set from the magazine's MK level.
var magazine_multiplier: float = 1.0
## Pays the reloads with its carried ore (the holder); null: it can't reload.
var supplier: Player
## Whether a magazine reload keeps the rounds left in it and only tops it up (the careful reload
## skill), instead of throwing them away.
var careful: bool = false
var reloading: bool = false
## Seconds into the current reload (with `ReloadMode.SINGLE`, of the round being loaded).
var reload_elapsed: float = 0.0
## How long the current reload (round) takes, longer after a press outside the window.
var reload_duration: float = 0.0
## Whether the current reload (round) had its timing press, and whether that missed the window.
var timing_pressed: bool = false
var fumbled: bool = false
## Rounds in a row loaded within the window (`ReloadMode.SINGLE`).
var chain: int = 0

var _trigger_was_held: bool = false

@onready var _muzzle: Marker3D = $Muzzle


func _physics_process(delta: float) -> void:
	if reloading:
		reload_elapsed += delta
		if reload_elapsed >= reload_duration:
			if not timing_pressed or fumbled:
				chain = 0
			_finish_round()
	# Pulling the trigger on an empty weapon reloads it.
	if trigger_held and not _trigger_was_held and rounds == 0 and not reloading:
		_start_reload()
	_trigger_was_held = trigger_held
	super(delta)


func _process(_delta: float) -> void:
	var gauge := get_node_or_null(^"AmmoGauge") as AmmoGauge
	if gauge:
		gauge.show_state(self)


## Rounds a full magazine holds, with its MK level.
func capacity() -> int:
	return maxi(1, roundi(settings.magazine * magazine_multiplier))


## Fills the magazine and gives it `spare_magazines` full spare magazines, for free (from the
## ship's stock), cancelling a reload.
func fill(spare_magazines: int) -> void:
	cancel_reload()
	rounds = capacity()
	spare_rounds = spare_magazines * capacity()


## The `reload` action: starts a reload, or during one, is its timing press. Returns whether it
## started or timed one.
func reload() -> bool:
	if reloading:
		return _time_press()
	return _start_reload()


## Stops a reload; with a magazine reload, the rounds thrown away are lost.
func cancel_reload() -> void:
	reloading = false


## Whether a reload could start now (not full, and spares or ore give more rounds than it holds).
func can_reload() -> bool:
	if rounds >= capacity():
		return false
	if settings.reload_mode == RangedWeaponSettings.ReloadMode.SINGLE:
		return _available(1) >= 1
	if careful:
		return _available(capacity() - rounds) > 0
	return _available(capacity()) > rounds


## How far the current reload (round) is, as a share of its time without fumbles: compare with
## the window (`settings.sweet_spot_start`, `settings.sweet_spot_width`).
func reload_share() -> float:
	return reload_elapsed / _round_time() if reloading else 0.0


## Fills the magazine with ammo `giver` makes from their carried ore (a teammate handing over a
## magazine), cancelling a reload. Like a reload: a magazine replaces the rounds left in it, single
## rounds top it up. Returns whether it loaded more than it had.
func receive_ammo(giver: Player) -> bool:
	if settings.reload_mode == RangedWeaponSettings.ReloadMode.SINGLE:
		var loaded: int = _affordable(capacity() - rounds, giver)
		if loaded <= 0:
			return false
		cancel_reload()
		_pay(loaded, giver)
		rounds += loaded
		return true
	var full: int = _affordable(capacity(), giver)
	if full <= rounds:
		return false
	cancel_reload()
	_pay(full, giver)
	rounds = full
	return true


func apply_upgrades(upgrades: Upgrades, weapon_type: WeaponType) -> void:
	super(upgrades, weapon_type)
	var magazine: Upgrade = weapon_type.magazine_upgrade if weapon_type else null
	magazine_multiplier = upgrades.multiplier(magazine)
	_show_pips(^"MagazinePips", upgrades, magazine)
	rounds = mini(rounds, capacity())
	var gauge := get_node_or_null(^"AmmoGauge") as AmmoGauge
	if gauge:
		gauge.build(capacity())


func _can_attack() -> bool:
	return rounds > 0 and (not reloading or _single())


func _attack() -> void:
	cancel_reload()
	rounds -= 1
	var direction: Vector3 = aim_direction
	if is_instance_valid(aim_target) and not aim_target.dead:
		direction = _muzzle.global_position.direction_to(aim_target.get_aim_point())
	var spread: float = deg_to_rad(settings.spread)
	for pellet: int in settings.pellets:
		var angle: float = 0.0
		if settings.pellets > 1:
			angle = lerpf(-spread * 0.5, spread * 0.5, float(pellet) / (settings.pellets - 1))
		_fire(direction.rotated(Vector3.UP, angle))
	if rounds == 0:
		_start_reload()


func _get_settings() -> WeaponSettings:
	return settings


func _single() -> bool:
	return settings.reload_mode == RangedWeaponSettings.ReloadMode.SINGLE


func _start_reload() -> bool:
	if not can_reload():
		# A full magazine just needs nothing; only a missing reload is worth a warning.
		if rounds < capacity():
			reload_denied.emit()
		return false
	if not _single() and not careful:
		rounds = 0
	reloading = true
	chain = 0
	_start_round()
	return true


func _start_round() -> void:
	reload_elapsed = 0.0
	reload_duration = _round_time()
	timing_pressed = false
	fumbled = false


## The time of the next reload (round), quicker with a chain of timed rounds.
func _round_time() -> float:
	var speedup: float = minf(chain * settings.chain_speedup, settings.max_chain_speedup)
	return settings.reload_time * (1.0 - speedup)


func _time_press() -> bool:
	if timing_pressed:
		return false
	timing_pressed = true
	var share: float = reload_share()
	var hit: bool = (
		share >= settings.sweet_spot_start
		and share <= settings.sweet_spot_start + settings.sweet_spot_width
	)
	if hit:
		chain += 1
		reload_timed.emit(true)
		_finish_round()
	else:
		fumbled = true
		chain = 0
		reload_duration += settings.fumble_time
		reload_timed.emit(false)
	return true


## Loads the reload's rounds (the whole magazine, or one round) and takes them from the spares or
## pays them. A single-round reload goes on with the next round until it's full or nothing gives
## more.
func _finish_round() -> void:
	if not _single():
		var kept: int = rounds if careful else 0
		var loaded: int = _available(capacity() - kept)
		_take(loaded)
		rounds = kept + loaded
		reloading = false
		return
	if _available(1) < 1:
		reloading = false
		return
	_take(1)
	rounds += 1
	if rounds < capacity() and _available(1) >= 1:
		_start_round()
	else:
		reloading = false


## How many of `count` rounds a reload gets right now: all of them aboard, else from the spares
## while there are any, else what the holder's ore pays.
func _available(count: int) -> int:
	if supplier and supplier.ammo_free:
		return count
	if spare_rounds > 0:
		return mini(count, spare_rounds)
	return _affordable(count, supplier)


## Takes `count` rounds for a reload, the way `_available` counted them.
func _take(count: int) -> void:
	if supplier and supplier.ammo_free:
		return
	if spare_rounds > 0:
		spare_rounds = maxi(spare_rounds - count, 0)
		return
	_pay(count, supplier)


## How many of `count` rounds `payer` can pay right now.
func _affordable(count: int, payer: Player) -> int:
	if not payer:
		return 0
	if payer.ammo_free:
		return count
	return mini(count, OreAmmo.affordable(payer.cargo, settings.ore_per_round))


func _pay(count: int, payer: Player) -> void:
	if payer and not payer.ammo_free:
		OreAmmo.spend(payer, count * settings.ore_per_round)


## Projectiles don't hit the holder and are added to its parent, so they fly on independently.
## They start inside the holder and travel to the muzzle first: a muzzle poking into a wall
## would otherwise spawn them inside it, where the ray doesn't detect it.
func _fire(direction: Vector3) -> void:
	var muzzle: Vector3 = _muzzle.global_position
	var projectile := projectile_scene.instantiate() as Projectile
	projectile.velocity = direction * settings.projectile_speed
	projectile.max_distance = settings.projectile_range
	projectile.damage = settings.damage * damage_multiplier
	projectile.stagger = settings.stagger
	projectile.push = settings.push
	projectile.exclude = [holder.get_rid()]
	projectile.shooter = holder
	holder.get_parent().add_child(projectile)
	projectile.global_position = Vector3(
		holder.global_position.x, muzzle.y, holder.global_position.z
	)
	projectile.move_to(muzzle)
	projectile.reset_physics_interpolation()
