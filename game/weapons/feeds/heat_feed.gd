class_name HeatFeed
extends MagazineFeed
## A weapon firing continuously from a fuel cell that heats up (Scald, Kith, Zenith), see
## `HeatAmmo`: the cell is its magazine (`magazine` rounds, one per attack; reloaded like one,
## from spares and then ore, with the timing window), and every attack adds heat. All values TBD
## (playtest).

## Heat each attack adds at MK1, as a share of full (less with the MK level of the cooling).
@export var heat_per_round: float = 0.02
## Seconds after the last attack until it starts cooling by itself.
@export var cool_delay: float = 0.5
## Share of full heat it loses per second while it cools by itself.
@export var cool_rate: float = 0.4
## Seconds venting full heat takes (an overheat, or `reload` while hot: for a share of it); the
## timing window of a reload (`sweet_spot_start`, `sweet_spot_width`) vents it at once.
@export var vent_time: float = 2.0
## Pressing `reload` vents it early at this share of full heat or more; less: it swaps the cell.
@export var vent_from: float = 0.4

@export_group("Sounds")
## Heat full: it stops firing and vents.
@export var overheat_sound: Sound
## A vent starting (an overheat, or by hand).
@export var vent_sound: Sound


func create_ammo(weapon: Weapon) -> WeaponAmmo:
	return HeatAmmo.new(weapon, self)
