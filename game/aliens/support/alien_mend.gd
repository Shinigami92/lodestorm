class_name AlienMend
extends Resource
## How a tender mends the aliens around it (`AlienStrain.mend`, see `MendLinks`): pulsing links from
## the tips of its tendrils to up to `links` aliens near it, healing them and hardening their
## armor. All values TBD (playtest).

## How many aliens it links at once.
@export var links: int = 3
## Aliens this close get linked (horizontally, m); a link breaks beyond `break_range`.
@export var link_range: float = 8.0
@export var break_range: float = 10.0
## Health a linked alien gets back per second (scaled by its tier, see `Alien.health_factor`).
@export var heal_per_second: float = 5.0
## Armor a linked alien gets on every side.
@export var armor: float = 3.0
## Bones the links start from, one per link (the tendrils' tips); without them, above its body.
@export var tip_bones: PackedStringArray = ["Tendril1Tip", "Tendril2Tip", "Tendril3Tip"]
