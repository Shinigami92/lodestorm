class_name MagazineAmmo
extends WeaponAmmo
## The ammo of a weapon fed by magazines or single rounds (`MagazineFeed`). Each attack uses one
## of its `rounds`; a full magazine holds `capacity()` (more with the capacity's MK level).
## `reload` refills it, also automatically once it runs empty or the trigger is pulled on an empty
## weapon: from its spares (`spare_rounds`, from the ship's stock) while it has any, then with
## ammo the holder's suit makes from carried ore (`OreAmmo`, paid per round loaded); aboard it's
## free. A magazine reload throws away the rounds left in it and fills the whole magazine (the
## weapon can't attack meanwhile; with `careful`, it keeps them and only tops the magazine up);
## a single-round reload loads one round after another until it's full and stops when it fires.
## Pressing `reload` again during a reload (the round being loaded) is the timing press: within the
## window it finishes right away, outside it the reload takes longer. Single rounds loaded within
## the window in a row get quicker. The weapon's `AmmoGauge` shows all this on the weapon.
## Sounds: the reload starting and the rounds going in (from the feed), an empty click when it
## can't reload, and for the local player a tick when the window opens and whether a press hit it.

const EMPTY_SOUND: Sound = preload("res://assets/audio/sfx/weapons/empty_click.tres")
const WINDOW_SOUND: Sound = preload("res://assets/audio/sfx/weapons/window_tick.tres")
const TIMED_HIT_SOUND: Sound = preload("res://assets/audio/sfx/weapons/timed_hit.tres")
const TIMED_MISS_SOUND: Sound = preload("res://assets/audio/sfx/weapons/timed_miss.tres")

var feed: MagazineFeed
## Whether a magazine reload keeps the rounds left in it and only tops it up (the careful reload
## skill), instead of throwing them away.
var careful: bool = false
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


func _init(fed: Weapon, magazine_feed: MagazineFeed) -> void:
	super(fed)
	feed = magazine_feed


func capacity() -> int:
	return maxi(1, roundi(feed.magazine * weapon.multiplier(WeaponPart.Stat.CAPACITY)))


func process(delta: float) -> void:
	if reloading:
		var share: float = reload_share()
		reload_elapsed += delta
		if (
			not timing_pressed
			and share < feed.sweet_spot_start
			and reload_share() >= feed.sweet_spot_start
		):
			weapon.play(WINDOW_SOUND, true, true)
		if reload_elapsed >= reload_duration:
			if not timing_pressed or fumbled:
				chain = 0
			_finish_round()
	# Pulling the trigger on an empty weapon reloads it.
	if weapon.trigger_held and not _trigger_was_held and rounds == 0 and not reloading:
		_start_reload()
	_trigger_was_held = weapon.trigger_held


func can_attack() -> bool:
	return rounds > 0 and (not reloading or is_single())


func use() -> void:
	cancel_reload()
	rounds -= 1
	if rounds == 0:
		_start_reload()


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
	if is_single():
		return _available(1) >= 1
	if careful:
		return _available(capacity() - rounds) > 0
	return _available(capacity()) > rounds


## Whether it loads single rounds rather than whole magazines.
func is_single() -> bool:
	return feed.reload_mode == MagazineFeed.ReloadMode.SINGLE


## How far the current reload (round) is, as a share of its time without fumbles: compare with
## the window (`feed.sweet_spot_start`, `feed.sweet_spot_width`).
func reload_share() -> float:
	return reload_elapsed / _round_time() if reloading else 0.0


## Like a reload: a magazine replaces the rounds left in it, single rounds top it up.
func receive_ammo(giver: Player) -> bool:
	if is_single():
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


func _start_reload() -> bool:
	if not can_reload():
		# A full magazine just needs nothing; only a missing reload is worth a warning.
		if rounds < capacity():
			weapon.play(EMPTY_SOUND)
			reload_denied.emit()
		return false
	if not is_single() and not careful:
		rounds = 0
	reloading = true
	chain = 0
	_start_round()
	weapon.play(feed.reload_sound)
	return true


func _start_round() -> void:
	reload_elapsed = 0.0
	reload_duration = _round_time()
	timing_pressed = false
	fumbled = false


## The time of the next reload (round), quicker with a chain of timed rounds.
func _round_time() -> float:
	var speedup: float = minf(chain * feed.chain_speedup, feed.max_chain_speedup)
	return feed.reload_time * (1.0 - speedup)


func _time_press() -> bool:
	if timing_pressed:
		return false
	timing_pressed = true
	if feed.in_window(reload_share()):
		chain += 1
		weapon.play(TIMED_HIT_SOUND, true)
		reload_timed.emit(true)
		_finish_round()
	else:
		fumbled = true
		chain = 0
		reload_duration += feed.fumble_time
		weapon.play(TIMED_MISS_SOUND, true)
		reload_timed.emit(false)
	return true


## Loads the reload's rounds (the whole magazine, or one round) and takes them from the spares or
## pays them. A single-round reload goes on with the next round until it's full or nothing gives
## more.
func _finish_round() -> void:
	if not is_single():
		var kept: int = rounds if careful else 0
		var loaded: int = _available(capacity() - kept)
		_take(loaded)
		rounds = kept + loaded
		reloading = false
		if loaded > 0:
			weapon.play(feed.load_sound)
		return
	if _available(1) < 1:
		reloading = false
		return
	_take(1)
	rounds += 1
	weapon.play(feed.load_sound)
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
	return mini(count, OreAmmo.affordable(payer.cargo, feed.ore_per_round))


func _pay(count: int, payer: Player) -> void:
	if payer and not payer.ammo_free:
		OreAmmo.spend(payer, count * feed.ore_per_round)
