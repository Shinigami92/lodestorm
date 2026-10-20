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
## For a model whose attack clip is the telegraph (the warden rearing up): the clip starts this
## many seconds before the attack acts (its hit lands then) and moves the legs itself; 0: the clip
## plays when it hits and the body crouches during the wind-up.
@export var clip_lead: float = 0.0
## Whether it's used on miners (raiders) too, or only on players.
@export var against_miners: bool = true
## Whether the alien keeps moving as before during the wind-up and the recovery (a skimmer spits
## while it circles); otherwise it stops.
@export var on_the_move: bool = false
## Whether it starts from under the ground (burrowers, see `AlienStrain.burrows`); the others only
## start while the alien is up.
@export var underground: bool = false
## Played when the wind-up starts (the telegraph's sound) and when it acts (a scream), in the
## strain's voice (see `AlienSounds`); null: none.
@export var wind_up_sound: Sound
@export var act_sound: Sound


## Whether it can start on `target`, `distance` m away (horizontally).
func can_start(alien: Alien, target: Node3D, distance: float) -> bool:
	if underground != alien.underground or not (against_miners or target is Player):
		return false
	return _in_range(alien, target, distance)


## How close the alien comes to its target for this attack (horizontally, center to center, in m).
func approach() -> float:
	return reach


## Called once when the wind-up starts (a telegraph on the ground, where to face).
func prepare(_alien: Alien) -> void:
	pass


## Called once when the wind-up is over.
func begin(_alien: Alien) -> void:
	pass


## Called once when the attack ends or is broken off (a stagger, death), after `prepare`.
func finish(_alien: Alien) -> void:
	pass


## Whether it moves the alien (a leap, a charge, a dive): a gravity well holding the alien stops
## it and doesn't let it start (see `AlienStatus.hold`).
func moves() -> bool:
	return false


## Called once when the alien dies, however (a bloater bursts).
func on_death(_alien: Alien) -> void:
	pass


## Called every physics frame from `begin` on, `elapsed` seconds after it. Returns whether it's
## done.
@abstract func act(alien: Alien, elapsed: float) -> bool

## Whether `target`, `distance` m away, is in range to start.
@abstract func _in_range(alien: Alien, target: Node3D, distance: float) -> bool
