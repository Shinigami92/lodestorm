@abstract class_name AmmoGauge
extends Node3D
## Shows a ranged weapon's ammo on the weapon itself, in segments that glow (a child named
## `AmmoGauge`, updated by the weapon every frame): the loaded share of the magazine, the last
## segment blinking amber when it's nearly empty, all of them blinking red when it's empty and
## nothing pays a reload. During a magazine reload the segments fill up like a bar, the one in the
## timing window white (red after a press outside it); during a single-round reload each segment is
## a round and the one being loaded brightens, white within the window.

const WARNING := Color(1.0, 0.55, 0.08)
const EMPTY := Color(1.0, 0.12, 0.08)
const TIMING := Color(1.0, 1.0, 1.0)
const DARK := Color(0.0, 0.0, 0.0)
## Blinks per second of the warnings.
const BLINK_RATE: float = 3.0

## The weapon's ammo color.
@export var color := Color(0.02, 0.7, 1.0)
## How strongly lit segments glow.
@export var energy: float = 4.0

## Prepares the display for a magazine of `capacity` rounds. Works before the weapon enters the
## tree, so the holder can mark the materials together with the weapon's.
@abstract func build(capacity: int) -> void

## Shows the state of `weapon`.
@abstract func show_state(weapon: RangedWeapon) -> void


## The glow (color times energy, black: dark) of each of `count` segments for `weapon`'s state.
func segment_glow(weapon: RangedWeapon, count: int) -> Array[Color]:
	var glow: Array[Color] = []
	glow.resize(count)
	glow.fill(DARK)
	var blink_on: bool = fmod(Time.get_ticks_msec() * 0.001 * BLINK_RATE, 1.0) < 0.5
	var settings: RangedWeaponSettings = weapon.settings
	if weapon.reloading and settings.reload_mode == RangedWeaponSettings.ReloadMode.MAGAZINE:
		var share: float = weapon.reload_share()
		var bar: Color = EMPTY if weapon.fumbled else color
		var window: int = _segment_at(
			settings.sweet_spot_start + settings.sweet_spot_width * 0.5, count
		)
		for i: int in count:
			var reached: bool = (i + 0.5) / count <= share
			if i == window and not weapon.fumbled:
				glow[i] = TIMING * (energy if reached else energy * 0.25)
			elif reached:
				glow[i] = bar * energy
		return glow
	var lit: int = ceili(float(weapon.rounds) / weapon.capacity() * count)
	for i: int in mini(lit, count):
		glow[i] = color * energy
	if weapon.reloading and weapon.rounds < count:
		# The round being loaded brightens; white within the window, red after a fumble.
		var share: float = weapon.reload_share()
		var in_window: bool = (
			share >= settings.sweet_spot_start
			and share <= settings.sweet_spot_start + settings.sweet_spot_width
		)
		var loading: Color = EMPTY if weapon.fumbled else (TIMING if in_window else color)
		glow[weapon.rounds] = loading * energy * clampf(share, 0.15, 1.0)
	elif weapon.rounds == 0 and not weapon.can_reload():
		glow.fill(EMPTY * energy * 0.4 if blink_on else DARK)
	elif lit == 1 and count > 1:
		glow[0] = WARNING * energy if blink_on else DARK
	return glow


static func _segment_at(share: float, count: int) -> int:
	return clampi(floori(share * count), 0, count - 1)
