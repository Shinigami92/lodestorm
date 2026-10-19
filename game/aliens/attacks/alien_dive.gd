class_name AlienDive
extends AlienCharge
## A darter's dive, a charge from the air: during the wind-up it hovers, its sting glowing, and its
## line shows on the ground (`ChargeLine`); then it swoops down along it to its strain's
## `dive_height` (`AlienFlight.low`), stinging every player within `width` once it's low enough,
## and stays low for `recovery` before it climbs again: the moment every weapon reaches it.

## It only stings players at most this far below it (m).
@export var sting_height: float = 1.8


## It hovers this far away to dive (the middle of its range), not right above its target.
func approach() -> float:
	return (min_range + max_range) * 0.5


func prepare(alien: Alien) -> void:
	super.prepare(alien)
	# The line lies on the ground, not at the height it hovers at.
	var line: ChargeLine = _lines.get(alien)
	var ground: float = AlienFlight.ground_below(alien, alien.global_position)
	if line and ground > -INF:
		line.global_position.y = ground


func begin(alien: Alien) -> void:
	alien.flight.low = true
	super.begin(alien)


func finish(alien: Alien) -> void:
	alien.flight.low = false
	super.finish(alien)


func _can_hit(offset: Vector3) -> bool:
	return offset.y >= -sting_height and offset.y <= max_height_difference
