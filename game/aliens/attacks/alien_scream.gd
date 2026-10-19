class_name AlienScream
extends AlienAttack
## A shrieker's scream: during the wind-up it rears its neck and its throat swells (the clip is the
## telegraph, see `clip_lead`), then it screams. Every alien within `radius` (itself too) is
## `boost` times faster for `boost_time`, and it calls for help (`Alien.called_for_help`): the nest
## nearest to it sends its next pack right away, boosted the same. A ring of sound sweeps over the
## ground (`ScreamWave`). Breaking off the wind-up (a stagger: focus fire) stops it. It screams
## while its target is within `reach`, from a distance.

## How far around it the scream reaches (m).
@export var radius: float = 15.0
## How much faster the aliens it reaches get, and for how many seconds.
@export var boost: float = 1.25
@export var boost_time: float = 6.0


func act(alien: Alien, _elapsed: float) -> bool:
	if clip_lead <= 0.0:
		alien.play_attack()
	for other: Alien in alien.get_tree().get_nodes_in_group(Alien.GROUP):
		var offset: Vector3 = other.global_position - alien.global_position
		if Vector2(offset.x, offset.z).length() <= radius:
			other.status.boost(boost, boost_time)
	alien.called_for_help.emit(alien.global_position, boost, boost_time)
	if alien.is_inside_tree():
		ScreamWave.spawn(alien.get_parent(), alien.global_position, radius)
	return true


func _in_range(_alien: Alien, _target: Node3D, distance: float) -> bool:
	return distance <= reach
