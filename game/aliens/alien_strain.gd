class_name AlienStrain
extends Resource
## An alien strain: its body (`scene`, an `Alien`), how it moves, what it takes and its attacks.
## Every strain plays one role (`role`: guards stay by their nest, hunters go for players,
## raiders for miners), so a role is told apart by its body. A new strain is a scene plus this
## data (see `game/aliens/strains/`). All values TBD (playtest).

## The name the crew calls it.
@export var display_name: String = ""
## The body: a scene with an `Alien` at its root.
@export var scene: PackedScene
## How much one alive counts towards the cap on living aliens (see `MissionSettings.alien_cap`):
## small ones that come in packs count as a share.
@export var cap_share: float = 1.0
## The tier of the bodies that bring it (see `HatchTable`): two new strains per tier.
@export_range(1, 6, 1, "or_greater") var tier: int = 1
## What it goes for: the nest hatches its guards, hunters and raiders from the strains of that role.
@export var role := Alien.Role.HUNTER
## How likely a nest picks it among the guards' or raiders' strains (hunters come in packs, see
## `AlienPack`).
@export var weight: float = 1.0

@export_group("Body")
## Health of an unhurt alien.
@export var max_health: float = 30.0
## Taken off the damage of every hit; at least `Alien.MIN_DAMAGE_SHARE` of it always gets through.
@export var armor: float = 0.0
## Width of the armored side around its front, in degrees (360: armored all around).
@export var armor_arc: float = 360.0
## Share of a hit's stagger that hits on the armor fill (the brute's plates hold, its back doesn't).
@export_range(0.0, 1.0) var armored_stagger: float = 1.0
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
## Seconds it backs off from its target after each attack before it comes in again (stalkers hit
## and run); 0: it doesn't.
@export var retreat_time: float = 0.0
## Whether it circles its target between `keep_away` and the reach of its attacks instead of
## standing (skimmers); with attacks `AlienAttack.on_the_move` it never stops.
@export var circles: bool = false
## Whether it wanders between the location's areas without a target (the Ravager, see
## `Alien.route`), instead of standing.
@export var roams: bool = false
## Keeps at least this far from its target (horizontally, in m): closer, it backs away (spitters);
## 0: it doesn't.
@export var keep_away: float = 0.0
## Guards (and raiders without a miner) stay within this distance of where they hatched (m): they
## only go for players inside it and walk back without one; 0: no leash.
@export var leash: float = 0.0

@export_group("Burrowing")
## Whether it travels under the ground towards its target (burrowers): along the paths, out of
## reach of shots and swings, only a ripple in the ground shows where it is. Attacks marked
## `underground` start from there (`AlienEruption`); without a target it comes up.
@export var burrows: bool = false
## Seconds it stays up after coming up, before it digs in again.
@export var surface_time: float = 3.0
## Seconds digging in and coming up take.
@export var dig_time: float = 0.4

@export_group("Flight")
## How high it flies above the ground (darters, see `AlienFlight`): over cliffs and rock, straight
## at its target, no paths; 0: it walks.
@export var flight_height: float = 0.0
## How high it flies while it dives and right after (low enough for every weapon).
@export var dive_height: float = 1.0

@export_group("Support")
## Whether and how it mends the aliens around it (tenders, see `MendLinks`); null: it doesn't.
@export var mend: AlienMend
## Whether and how it hides (stalkers, see `AlienCloaking`); null: it doesn't.
@export var cloak: AlienCloak
## How strongly the ground shakes around it (the Ravager, see `AlienTremor`): the view's shake at
## its feet with every step (m); 0: it doesn't.
@export var tremor: float = 0.0

@export_group("Sounds")
## Plays its sounds this many times higher (see `AlienSounds`): bigger strains lower.
@export_range(0.3, 2.0, 0.05) var voice_pitch: float = 1.0
## Its own chitter, strike, hits (in the flesh, on the armor) and death; null: the hive's (the
## swarmer's).
@export var chitter_sound: Sound
@export var strike_sound: Sound
@export var hit_sound: Sound
@export var armor_hit_sound: Sound
@export var death_sound: Sound

@export_group("Attacks")
## Tried in order: the first one that is ready and has the target in its range starts.
@export var attacks: Array[AlienAttack] = []


## Hatches a new alien of this strain playing `as_role` (not in the tree yet; nests pass the
## strain's own `role`).
func spawn(as_role: Alien.Role = Alien.Role.GUARD) -> Alien:
	var alien := scene.instantiate() as Alien
	alien.strain = self
	alien.role = as_role
	return alien


## Whether it flies (see `flight_height`).
func flies() -> bool:
	return flight_height > 0.0


## How close the alien has to come for its closest attack (horizontally, center to center, in m):
## of those that start from under the ground if `underground`, of the others if not.
func reach(underground: bool = false) -> float:
	var shortest: float = INF
	for attack: AlienAttack in attacks:
		if attack.underground == underground:
			shortest = minf(shortest, attack.approach())
	return shortest if shortest < INF else 1.0
