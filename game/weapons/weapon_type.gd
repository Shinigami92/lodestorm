class_name WeaponType
extends Resource
## One weapon of the game, composed of Resources: what feeds it (`feed`: its ammo; melee weapons
## have none), how holding the button attacks (`trigger`: per press, spinning up, charging; none:
## at its rate while held), how an attack reaches its targets (`delivery`: projectiles, a swing)
## and what a hit does to them (`effects`), plus the parts the workbench upgrades (`parts`) and its
## model (`scene`), so most weapons are data plus a greybox scene. `create` makes one to hold or
## show.
## Players own weapon types (`Arsenal`): the first ones from the start, the others built at the
## workbench from their blueprint for ore (`build_cost`), and take some into a mission
## (`Loadout`). `game/weapons/all_weapons.tres` lists every weapon of the game.

## Where a weapon comes from: the militia's standard issue, the prospectors' converted mining
## tools, or the lost expedition's prototypes. Shapes its look and groups the racks.
enum Origin { COLONY, TOOL, PROTOTYPE }
## How the holder carries it between attacks (see `PlayerAnimator`): raised to aim (the ranged
## weapons), a blade in one hand, a hammer in both, a tool braced at the hip in both.
enum Hold { AIM, BLADE, HAMMER, BRACE }

## Its name, the same in every language (like the ores and places).
@export var display_name: String = ""
## What it is, translated, shown under its name (e.g. "Assault rifle").
@export var class_word: String = ""
## One line on how it plays, shown in the armory.
@export var description: String = ""
@export var origin: Origin = Origin.COLONY
## The model, its root a `Weapon`: with a `Muzzle` marker where projectiles leave, an
## `AmmoGauge` for a fed weapon, a `Model` that swings, and pips per part (see `WeaponPart`).
@export var scene: PackedScene
## Attacks (shots, swings) per second while the attack button is held, at MK1.
@export var attack_rate: float = 6.0
## Seconds from switching to it until it can attack: the model swings up meanwhile.
@export var draw_time: float = 0.3
@export var hold: Hold = Hold.AIM
## Its ammo; null for melee weapons.
@export var feed: WeaponFeed
## How holding the attack button attacks; null: at `attack_rate` while it's held.
@export var trigger: WeaponTrigger
@export var delivery: WeaponDelivery
## What every hit does (damage, ...), in order.
@export var effects: Array[WeaponEffect] = []
## The parts the workbench upgrades, in the order it lists them.
@export var parts: Array[WeaponPart] = []
## The ore building it from its blueprint takes, from the hold; empty: nothing (the starting
## weapons are owned anyway). All amounts TBD (playtest).
@export var build_cost: Dictionary[OreType, int] = {}

@export_group("Sounds")
## Each attack (a shot, a swing).
@export var attack_sound: Sound


## Whether it's a melee weapon: no ammo.
func is_melee() -> bool:
	return feed == null


## Its parts as upgrades, in the order the workbench lists them.
func get_upgrades() -> Array[Upgrade]:
	var upgrades: Array[Upgrade] = []
	upgrades.assign(parts)
	return upgrades


## Its part improving `stat`, or null.
func get_part(stat: WeaponPart.Stat) -> WeaponPart:
	for part: WeaponPart in parts:
		if part.stat == stat:
			return part
	return null


## A new weapon of this type, not in the tree yet; its ammo (if fed) starts empty.
func create() -> Weapon:
	var weapon := scene.instantiate() as Weapon
	weapon.type = self
	if feed:
		weapon.ammo = feed.create_ammo(weapon)
	return weapon
