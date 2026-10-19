class_name AlienBurst
extends AlienAttack
## A bloater's burst: next to its miner (or a player in its way) its sac swells and shudders for the
## wind-up (the clip is the telegraph, see `clip_lead`), then it bursts. It also bursts when it's
## killed, without a wind-up, so killing it at range (ideally next to other aliens) is the answer.
## The burst splashes `damage` on whoever is within `radius` and leaves an acid cloud
## (`AcidCloud`) that hurts players, miners and aliens alike.

## How far the splash and the cloud reach (m).
@export var radius: float = 3.0
## The cloud: how long it hangs (s) and its damage per second.
@export var cloud_time: float = 4.0
@export var cloud_damage: float = 8.0


func act(alien: Alien, _elapsed: float) -> bool:
	alien.take_damage.call_deferred(alien.health)
	return true


func on_death(alien: Alien) -> void:
	if not alien.is_inside_tree():
		return
	var cloud: AcidCloud = AcidCloud.release(
		alien.get_parent(),
		alien.global_position,
		radius,
		cloud_time,
		cloud_damage * alien.damage_factor
	)
	cloud.splash(damage * alien.damage_factor, alien)


func _in_range(alien: Alien, target: Node3D, distance: float) -> bool:
	return distance <= alien.reach_to(target, reach)
