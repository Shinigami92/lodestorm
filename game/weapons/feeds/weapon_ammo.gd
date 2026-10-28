@abstract class_name WeaponAmmo
extends RefCounted
## The ammo of one fed weapon, made by its `WeaponFeed`: the rounds loaded and in spare, and how it
## reloads. The weapon asks it before each attack (`can_attack`, `use`) and ticks it
## (`process`); the holder reloads it (`reload`), fills it for a run (`fill`) and hands a teammate
## ammo (`receive_ammo`). Rounds beyond the spares are paid with ore by the `supplier` (see
## `OreAmmo`); aboard (`PlayerArms.ammo_free`) they're free. The weapon's gauge and the suit ring
## show it the same way for every feed: the rounds, a refill (`refilling`: a reload, a drained
## battery, a vent) with its timing window, and the heat (`heat_share`).

## Emitted when a reload can't start although it isn't full (nothing pays more rounds).
@warning_ignore("unused_signal")
signal reload_denied
## Emitted after the timing press of a reload: whether it was within the window.
@warning_ignore("unused_signal")
signal reload_timed(hit: bool)

## The weapon it feeds.
var weapon: Weapon
## Pays the reloads with its carried ore (the holder); null: it can't reload.
var supplier: Player
## Rounds loaded.
var rounds: int = 0
## Rounds in spare (spare magazines, spare shells); reloads use them before ore.
var spare_rounds: int = 0
## Whether the holder is reloading it by hand (they walk slower meanwhile).
var reloading: bool = false
## Whether the current reload (round) had a timing press outside the window.
var fumbled: bool = false


func _init(fed: Weapon) -> void:
	weapon = fed


## Rounds it holds when full, with the MK level of the weapon's capacity.
@abstract func capacity() -> int

## Called every physics frame before the weapon's attack (a reload going on).
@abstract func process(delta: float) -> void

## Whether the weapon can attack right now.
@abstract func can_attack() -> bool

## Takes the round of an attack.
@abstract func use() -> void

## The `reload` action. Returns whether it did something.
@abstract func reload() -> bool

## Stops a reload.
@abstract func cancel_reload() -> void

## Fills it for free (the ship's stock) with `spare_magazines` full spares, cancelling a reload.
@abstract func fill(spare_magazines: int) -> void

## Loads ammo `giver` makes from their carried ore (a teammate handing it over). Returns whether it
## got more than it had.
@abstract func receive_ammo(giver: Player) -> bool

## Whether a refill could start now; false when it's empty and nothing pays more rounds.
@abstract func can_reload() -> bool

## How far the current refill (a reload, its round) is, as a share of it.
@abstract func refill_share() -> float


## Whether it's refilling and can't attack meanwhile: a magazine reload, a drained battery.
func refilling() -> bool:
	return reloading


## Whether a refill loads one round after another (they show one by one).
func is_single() -> bool:
	return false


## The window of the timing press during a refill, as shares of it (from x to y); none when x > y.
func timing_window() -> Vector2:
	return Vector2(1.0, 0.0)


## Whether a press `share` of the way through a refill is within its timing window.
func in_window(share: float) -> bool:
	var window: Vector2 = timing_window()
	return share >= window.x and share <= window.y


## How hot it is, from 0 (cold, or it doesn't heat up) to 1 (overheated), see `HeatAmmo`.
func heat_share() -> float:
	return 0.0


## Whether it has spares (spare magazines, shells) from the ship's stock.
func uses_spares() -> bool:
	return true


## Refills one spare magazine missing below `max_spares` rounds with ammo the `supplier` makes from
## carried ore (the rebuilding spares skill), as much as the ore pays. Returns the rounds it added
## (0 for feeds without spares).
func rebuild_spare(_max_spares: int) -> int:
	return 0


## Called after the weapon's MK levels changed: no more rounds than it holds now, and its gauge
## gets one segment per round where it shows them.
func upgraded() -> void:
	rounds = mini(rounds, capacity())
	var gauge: AmmoGauge = weapon.get_gauge()
	if gauge:
		gauge.build(capacity())


func is_full() -> bool:
	return rounds >= capacity()
