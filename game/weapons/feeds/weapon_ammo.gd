@abstract class_name WeaponAmmo
extends RefCounted
## The ammo of one fed weapon, made by its `WeaponFeed`: the rounds loaded and in spare, and how it
## reloads. The weapon asks it before each attack (`can_attack`, `use`) and ticks it
## (`process`); the holder reloads it (`reload`), fills it for a run (`fill`) and hands a teammate
## ammo (`receive_ammo`). Rounds beyond the spares are paid with ore by the `supplier` (see
## `OreAmmo`); aboard (`Player.ammo_free`) they're free.

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
var reloading: bool = false


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


## Called after the weapon's MK levels changed: no more rounds than it holds now, and its gauge
## gets one segment per round where it shows them.
func upgraded() -> void:
	rounds = mini(rounds, capacity())
	var gauge: AmmoGauge = weapon.get_gauge()
	if gauge:
		gauge.build(capacity())


func is_full() -> bool:
	return rounds >= capacity()
