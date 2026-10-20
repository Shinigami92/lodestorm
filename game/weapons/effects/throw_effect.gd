class_name ThrowEffect
extends WeaponEffect
## Throws the alien a hit lands on (Clout's punch) along the hit: up to `distance` m at a full
## charge, down to `jab_distance` for one let go at once, times its strain's knockback, so heavy
## strains are only shoved and the apex not at all. It flies staggered and stays so for
## `landing_stagger` after. Every other alien within `path_width` of its way takes `passed_share`
## of the hit and is knocked `aside` m out of the way (they don't fly on); a nest it flies into
## takes that share too. Flying into rock or a nest stops it there with `wall_share` of the hit on
## top, staggered for `wall_stagger` (or dazed as long as its charge's daze, if that's longer).
## Players and miners don't stop it. The MK level of the weapon's throw throws farther and passes
## more of the hit on. See `AlienThrow`. All values TBD (playtest).

## How far a full charge throws (m, before the strain's knockback), and one let go at once.
@export var distance: float = 7.0
@export var jab_distance: float = 1.5
## How fast it flies (m/s).
@export var speed: float = 16.0
## Seconds it stays staggered after it landed.
@export var landing_stagger: float = 0.5
## Aliens this close to its way (center to center, m) are hit.
@export var path_width: float = 0.8
## Share of the hit (damage and stagger) the aliens it passes take, and how far they're knocked
## aside (m, before their knockback).
@export_range(0.0, 1.0) var passed_share: float = 0.5
@export var aside: float = 2.0
## Share of the hit it takes on top when it flies into rock or a nest, and seconds it's staggered.
@export var wall_share: float = 0.5
@export var wall_stagger: float = 1.0

@export_group("Sounds")
## Landing on the ground, and slamming into rock or a nest.
@export var land_sound: Sound
@export var crash_sound: Sound


func add_to(hit: Hit, weapon: Weapon) -> void:
	var charge := weapon.type.trigger as ChargeTrigger
	var full: float = 1.0
	if charge and charge.min_power < 1.0:
		full = clampf(inverse_lerp(charge.min_power, 1.0, weapon.power), 0.0, 1.0)
	var farther: float = weapon.multiplier(WeaponPart.Stat.THROW)
	hit.throw = self
	hit.throw_distance = lerpf(jab_distance, distance, full) * farther
	hit.throw_passed = minf(passed_share * farther, 1.0)
