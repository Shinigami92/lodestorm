@abstract class_name AmmoGauge
extends Node3D
## Shows a fed weapon's ammo on the weapon itself, in segments that glow (a child named
## `AmmoGauge`, updated by the weapon every frame): the loaded share of the magazine, the last
## segment blinking amber when it's nearly empty, all of them blinking red when it's empty and
## nothing pays a reload. During a magazine reload (or a drained battery recharging) the segments
## fill up like a bar, the one in the timing window white (red after a press outside it); during a
## single-round reload each segment is a round and the one being loaded brightens, white within the
## window.

const WARNING := Color(1.0, 0.55, 0.08)
const EMPTY := Color(1.0, 0.12, 0.08)
const TIMING := Color(1.0, 1.0, 1.0)
const DARK := Color(0.0, 0.0, 0.0)
## Blinks per second of the warnings.
const BLINK_RATE: float = 3.0

## The weapon's ammo color: warm (amber, orange, gold, warm white), never an ore's hue.
@export var color := Color(1.0, 0.86, 0.66)
## How strongly lit segments glow.
@export var energy: float = 4.0

## Prepares the display for a magazine of `capacity` rounds. Works before the weapon enters the
## tree, so the holder can mark the materials together with the weapon's.
@abstract func build(capacity: int) -> void

## Shows the state of `ammo`.
@abstract func show_state(ammo: WeaponAmmo) -> void


## The glow (color times energy, black: dark) of each of `count` segments for `ammo`'s state.
func segment_glow(ammo: WeaponAmmo, count: int) -> Array[Color]:
	var glow: Array[Color] = []
	glow.resize(count)
	glow.fill(DARK)
	var blink_on: bool = fmod(Time.get_ticks_msec() * 0.001 * BLINK_RATE, 1.0) < 0.5
	var timing: Vector2 = ammo.timing_window()
	if ammo.refilling() and not ammo.is_single():
		var share: float = ammo.refill_share()
		var bar: Color = EMPTY if ammo.fumbled else color
		var window: int = -1
		if timing.x <= timing.y:
			window = _segment_at((timing.x + timing.y) * 0.5, count)
		for i: int in count:
			var reached: bool = (i + 0.5) / count <= share
			if i == window and not ammo.fumbled:
				glow[i] = TIMING * (energy if reached else energy * 0.25)
			elif reached:
				glow[i] = bar * energy
		return glow
	var lit: int = ceili(float(ammo.rounds) / ammo.capacity() * count)
	for i: int in mini(lit, count):
		glow[i] = color * energy
	if ammo.refilling() and ammo.rounds < count:
		# The round being loaded brightens; white within the window, red after a fumble.
		var share: float = ammo.refill_share()
		var loading: Color = EMPTY if ammo.fumbled else (TIMING if ammo.in_window(share) else color)
		glow[ammo.rounds] = loading * energy * clampf(share, 0.15, 1.0)
	elif ammo.rounds == 0 and not ammo.can_reload():
		glow.fill(EMPTY * energy * 0.4 if blink_on else DARK)
	elif lit == 1 and count > 1:
		glow[0] = WARNING * energy if blink_on else DARK
	return glow


static func _segment_at(share: float, count: int) -> int:
	return clampi(floori(share * count), 0, count - 1)
