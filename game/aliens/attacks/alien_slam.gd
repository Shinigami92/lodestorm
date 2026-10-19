class_name AlienSlam
extends AlienAttack
## A warden's slam: after the wind-up (rearing up with its front raised) it brings its front down
## `reach` in front of it, hitting every player within `radius` of that spot, not only its target.
## Stepping out of it during the wind-up dodges it; afterwards it stands still for `recovery`.

## Who stands this much higher or lower than the spot isn't hit (m).
const HIT_HEIGHT: float = 1.5

## How far around the spot it hits (m).
@export var radius: float = 1.6


func act(alien: Alien, _elapsed: float) -> bool:
	var spot: Vector3 = alien.global_position - alien.global_basis.z * reach
	for player: Player in alien.get_tree().get_nodes_in_group(Player.GROUP):
		if not Alien.is_prey(alien.get_tree(), player):
			continue
		var offset: Vector3 = player.global_position - spot
		if absf(offset.y) <= HIT_HEIGHT and Vector2(offset.x, offset.z).length() <= radius:
			Alien.hurt(player, damage * alien.damage_factor, alien.global_position)
	if clip_lead <= 0.0:
		alien.play_attack()
	return true


func _in_range(alien: Alien, target: Node3D, distance: float) -> bool:
	return distance <= alien.reach_to(target, reach + radius * 0.5)
