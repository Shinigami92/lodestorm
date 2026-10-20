class_name MagazineFeed
extends WeaponFeed
## A weapon fed by magazines (the whole magazine reloads at once) or single rounds (loaded one
## after another), see `MagazineAmmo`. All values TBD (playtest).

## How a reload fills the weapon: the whole magazine at once (the rounds left in it are lost), or
## one round after another (the loaded ones stay).
enum ReloadMode { MAGAZINE, SINGLE }

## Rounds (shots) a full magazine holds at MK1.
@export var magazine: int = 24
@export var reload_mode: ReloadMode = ReloadMode.MAGAZINE
## Seconds a reload takes: the whole magazine, or one round with `ReloadMode.SINGLE`.
@export var reload_time: float = 1.6
## The timing window of a reload, as shares of the reload time: pressing `reload` within it
## finishes the reload (the round) right away, pressing it outside adds `fumble_time`.
@export var sweet_spot_start: float = 0.55
@export var sweet_spot_width: float = 0.15
@export var fumble_time: float = 0.5
## `ReloadMode.SINGLE`: each round in a row loaded within the window makes the next ones quicker by
## this share of the reload time, up to `max_chain_speedup`.
@export var chain_speedup: float = 0.1
@export var max_chain_speedup: float = 0.3

@export_group("Sounds")
## A reload starting.
@export var reload_sound: Sound
## The rounds going in: the magazine at the end of a reload, or each single round.
@export var load_sound: Sound


func create_ammo(weapon: Weapon) -> WeaponAmmo:
	return MagazineAmmo.new(weapon, self)


## Whether a press `share` of the way through a reload (round) is within the window.
func in_window(share: float) -> bool:
	return share >= sweet_spot_start and share <= sweet_spot_start + sweet_spot_width
