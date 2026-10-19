class_name AlienStrain
extends Resource
## An alien strain: its body (`scene`, an `Alien`), how it moves, what it takes and its attacks.
## Which role it plays (guard, hunter, raider) is up to the nest that hatches it, so a new strain is
## a scene plus this data (see `game/aliens/strains/`). All values TBD (playtest).

## The name the crew calls it.
@export var display_name: String = ""
## The body: a scene with an `Alien` at its root.
@export var scene: PackedScene
## How much one alive counts towards the cap on living aliens (see `MissionSettings.alien_cap`):
## small ones that come in packs count as a share.
@export var cap_share: float = 1.0
## The tier of the bodies that bring it (see `HatchTable`): two new strains per tier.
@export_range(1, 6, 1, "or_greater") var tier: int = 1
## How likely a nest sends it out as a raider, against the other strains (0: never; hunters and
## guards come in packs, see `AlienPack`).
@export var raider_weight: float = 1.0

@export_group("Body")
## Health of an unhurt alien.
@export var max_health: float = 30.0
## Taken off the damage of every hit; at least `Alien.MIN_DAMAGE_SHARE` of it always gets through.
@export var armor: float = 0.0
## Width of the armored side around its front, in degrees (360: armored all around).
@export var armor_arc: float = 360.0
## Stagger a hit fills (see `WeaponSettings.stagger`) up to which it keeps going; past it, it's
## staggered for `stagger_time` and its attack is broken off. The stagger drains in a second.
@export var stagger_threshold: float = 25.0
@export var stagger_time: float = 0.5
## How far hits push it, as a share of the weapon's push (heavy strains less).
@export var knockback: float = 1.0
## Its steps against the swarmer's (`AlienLegs`: how far and how high a foot steps): shorter legs,
## smaller steps.
@export var stride: float = 1.0

@export_group("Movement")
## Top speed in m/s; below the player's, so running away works.
@export var move_speed: float = 5.2
## How fast the alien reaches top speed and stops again, in m/s².
@export var acceleration: float = 30.0
## How fast the body turns towards its target (higher = snappier).
@export var turn_speed: float = 10.0
## Players closer than this (horizontally, in m) get noticed and chased.
@export var detection_range: float = 18.0
## A chased player farther away than this (horizontally, in m) gets away (not from hunters).
@export var chase_range: float = 20.0
## Keeps at least this far from its target (horizontally, in m): closer, it backs away (spitters);
## 0: it doesn't.
@export var keep_away: float = 0.0

@export_group("Burrowing")
## Whether it travels under the ground towards its target (burrowers): along the paths, out of
## reach of shots and swings, only a ripple in the ground shows where it is. Attacks marked
## `underground` start from there (`AlienEruption`); without a target it comes up.
@export var burrows: bool = false
## Seconds it stays up after coming up, before it digs in again.
@export var surface_time: float = 3.0
## Seconds digging in and coming up take.
@export var dig_time: float = 0.4

@export_group("Attacks")
## Tried in order: the first one that is ready and has the target in its range starts.
@export var attacks: Array[AlienAttack] = []


## Hatches a new alien of this strain with `role` (not in the tree yet).
func spawn(role: Alien.Role = Alien.Role.GUARD) -> Alien:
	var alien := scene.instantiate() as Alien
	alien.strain = self
	alien.role = role
	return alien


## How close the alien has to come for its closest attack (horizontally, center to center, in m):
## of those that start from under the ground if `underground`, of the others if not.
func reach(underground: bool = false) -> float:
	var shortest: float = INF
	for attack: AlienAttack in attacks:
		if attack.underground == underground:
			shortest = minf(shortest, attack.approach())
	return shortest if shortest < INF else 1.0
