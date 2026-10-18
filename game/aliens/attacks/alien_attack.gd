@abstract class_name AlienAttack
extends Resource
## One of a strain's attacks (see `AlienStrain.attacks`). When its target is in range and it's
## ready, the alien winds up for `wind_up` seconds (the telegraph: it crouches, its eyes flare),
## then the attack acts until `act` says it's done, then the alien stands still for `recovery`.
## A stagger breaks it off at any point. All values TBD (playtest).

## Damage of a hit (scaled by the alien's tier, see `Alien.damage_factor`).
@export var damage: float = 10.0
## A hit lands when the target is this close (horizontally, center to center, in m). For a miner,
## its body radius is added: a miner is wider than a player.
@export var reach: float = 1.4
## Seconds from one start to the next.
@export var cooldown: float = 1.0
## Seconds of the telegraph before it acts.
@export var wind_up: float = 0.0
## Seconds it stands still afterwards: an opening to hit back.
@export var recovery: float = 0.0
## Whether it's used on miners (raiders) too, or only on players.
@export var against_miners: bool = true


## Whether it can start on `target`, `distance` m away (horizontally).
func can_start(alien: Alien, target: Node3D, distance: float) -> bool:
	return (against_miners or target is Player) and _in_range(alien, target, distance)


## Called once when the wind-up is over.
func begin(_alien: Alien) -> void:
	pass


## Called every physics frame from `begin` on, `elapsed` seconds after it. Returns whether it's
## done.
@abstract func act(alien: Alien, elapsed: float) -> bool

## Whether `target`, `distance` m away, is in range to start.
@abstract func _in_range(alien: Alien, target: Node3D, distance: float) -> bool
