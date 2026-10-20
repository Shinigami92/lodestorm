class_name HeatAmmo
extends MagazineAmmo
## The ammo of a weapon fed by a fuel cell that heats up (`HeatFeed`: Scald, Kith, Zenith). The
## cell is its magazine (see `MagazineAmmo`: spares first, then ore, a reload with its timing
## window). Every attack adds heat (less with the MK level of the weapon's cooling); a moment
## after the trigger is let go it cools by itself, so short bursts never overheat. At full heat it
## overheats: it stops firing and vents for the feed's vent time. Pressing `reload` while it's hot
## vents it early (for its share of that time); during a vent the press is its timing press like a
## reload's: within the window it's cool at once, outside it the vent takes longer. Sounds: an
## alarm when it overheats, a hiss when a vent starts, the reload's timing sounds.

var heat_feed: HeatFeed
## Heat, from 0 (cold) to 1 (overheated).
var heat: float = 0.0
## Whether it's venting (it can't fire meanwhile).
var venting: bool = false

## Heat when the vent started, seconds into it, and how long it takes.
var _vent_heat: float = 0.0
var _vent_elapsed: float = 0.0
var _vent_duration: float = 0.0
## Seconds since the last attack.
var _idle: float = INF


func _init(fed: Weapon, fed_by: HeatFeed) -> void:
	super(fed, fed_by)
	heat_feed = fed_by


func process(delta: float) -> void:
	_idle += delta
	if venting:
		var share: float = vent_share()
		_vent_elapsed += delta
		if (
			not timing_pressed
			and share < feed.sweet_spot_start
			and vent_share() >= feed.sweet_spot_start
		):
			weapon.play(WINDOW_SOUND, true, true)
		heat = _vent_heat * (1.0 - clampf(_vent_elapsed / _vent_duration, 0.0, 1.0))
		if _vent_elapsed >= _vent_duration:
			_finish_vent()
	elif _idle >= heat_feed.cool_delay:
		heat = maxf(heat - heat_feed.cool_rate * delta, 0.0)
	super.process(delta)


func can_attack() -> bool:
	return super.can_attack() and not venting


func use() -> void:
	super.use()
	_idle = 0.0
	heat += heat_feed.heat_per_round / weapon.multiplier(WeaponPart.Stat.COOLING)
	if heat >= 1.0:
		heat = 1.0
		weapon.play(heat_feed.overheat_sound)
		_start_vent()


## The `reload` action: the timing press of a vent or a reload under way, else a vent while it's
## hot, else a new cell.
func reload() -> bool:
	if venting:
		return _time_vent()
	if not reloading and heat >= heat_feed.vent_from:
		_start_vent()
		return true
	return super.reload()


func fill(spare_magazines: int) -> void:
	super.fill(spare_magazines)
	heat = 0.0
	venting = false


func refilling() -> bool:
	return venting or super.refilling()


func refill_share() -> float:
	return vent_share() if venting else super.refill_share()


func heat_share() -> float:
	return heat


## How far the vent is, as a share of its time without a fumble.
func vent_share() -> float:
	if not venting:
		return 0.0
	return _vent_elapsed / maxf(heat_feed.vent_time * _vent_heat, 0.01)


## No new cell while it vents.
func _start_reload() -> bool:
	if venting:
		return false
	return super._start_reload()


func _start_vent() -> void:
	cancel_reload()
	venting = true
	_vent_heat = heat
	_vent_elapsed = 0.0
	_vent_duration = maxf(heat_feed.vent_time * heat, 0.01)
	timing_pressed = false
	fumbled = false
	weapon.play(heat_feed.vent_sound)


func _time_vent() -> bool:
	if timing_pressed:
		return false
	timing_pressed = true
	if feed.in_window(vent_share()):
		weapon.play(TIMED_HIT_SOUND, true)
		_finish_vent()
		reload_timed.emit(true)
	else:
		fumbled = true
		_vent_duration += feed.fumble_time
		weapon.play(TIMED_MISS_SOUND, true)
		reload_timed.emit(false)
	return true


## Cool again; an empty cell reloads right away.
func _finish_vent() -> void:
	venting = false
	heat = 0.0
	if rounds == 0:
		_start_reload()
