class_name MeleeWeapon
extends Weapon
## Swings at everything in front of the holder per attack: every alien within reach and the
## swing's arc (around the aim direction, or the direction to the locked target) takes the damage,
## unless something solid is in the way, and so does a destructible (a nest) whose edge is within
## reach and the arc. The model (`Model`) sweeps through the arc, a stand-in for
## a swing animation. A swing that hits something plays the settings' `hit_sound`.

## Emitted after every swing with the aliens it hit.
signal swung(hits: Array[Alien])

## Share of the time between swings the sweep takes.
const SWEEP_SHARE: float = 0.6

@export var settings: MeleeWeaponSettings

var _sweep: Tween

@onready var _model: Node3D = $Model


func _attack() -> void:
	var direction: Vector3 = aim_direction
	if PlayerAim.is_lockable(aim_target):
		var to_target: Vector3 = aim_target.global_position - holder.global_position
		to_target.y = 0.0
		if to_target.length() > 0.01:
			direction = to_target.normalized()
	var aliens: Array[Alien] = []
	var exclude: Array[RID] = [holder.get_rid()]
	for node: Node in get_tree().get_nodes_in_group(Alien.GROUP):
		var alien := node as Alien
		if alien.is_hittable():
			aliens.append(alien)
			exclude.append(alien.get_rid())
	var hits: Array[Alien] = []
	for alien: Alien in aliens:
		if _in_swing(alien, direction, exclude):
			hits.append(alien)
	for alien: Alien in hits:
		var away: Vector3 = alien.global_position - holder.global_position
		var point: Vector3 = alien.get_aim_point() - Vector3(away.x, 0.0, away.z).normalized() * 0.4
		var hit := Hit.new(
			settings.damage * damage_multiplier,
			settings.stagger,
			settings.push,
			away if away.length() > 0.01 else direction,
			point,
			holder
		)
		DamageNumber.show_hit(holder, alien, alien.take_hit(hit))
	var struck: bool = not hits.is_empty()
	for node: Node in get_tree().get_nodes_in_group(Destructible.GROUP):
		var body := node as Destructible
		if body.is_hittable() and _reaches(body, direction):
			struck = true
			var away: Vector3 = body.global_position - holder.global_position
			away.y = 0.0
			var along: Vector3 = away.normalized() if away.length() > 0.01 else direction
			var point: Vector3 = body.get_aim_point() - along * body.radius()
			var hit := Hit.new(settings.damage * damage_multiplier, 0.0, 0.0, along, point, holder)
			DamageNumber.show_hit(holder, body, body.take_hit(hit))
	if struck:
		_play(settings.hit_sound)
	_play_sweep()
	swung.emit(hits)


func _get_settings() -> WeaponSettings:
	return settings


## Whether `alien` is within reach and the arc around `direction`, with nothing solid in between
## (other aliens don't block, a swing hits them all).
func _in_swing(alien: Alien, direction: Vector3, exclude: Array[RID]) -> bool:
	var offset: Vector3 = alien.global_position - holder.global_position
	if absf(offset.y) > settings.reach:
		return false
	offset.y = 0.0
	var distance: float = offset.length()
	if distance > settings.reach:
		return false
	if distance > 0.01 and offset.angle_to(direction) > deg_to_rad(settings.arc) * 0.5:
		return false
	var query := PhysicsRayQueryParameters3D.create(
		holder.global_position + Vector3.UP, alien.get_aim_point(), PhysicsLayers.SHOTS
	)
	query.exclude = exclude
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Whether `body`'s edge is within reach and its middle within the arc around `direction` (or
## the holder stands at it).
func _reaches(body: Destructible, direction: Vector3) -> bool:
	var offset: Vector3 = body.global_position - holder.global_position
	if absf(body.get_aim_point().y - holder.global_position.y) > settings.reach + body.aim_height:
		return false
	offset.y = 0.0
	var distance: float = offset.length() - body.radius()
	if distance > settings.reach:
		return false
	return distance <= 0.0 or offset.angle_to(direction) <= deg_to_rad(settings.arc) * 0.5


func _play_sweep() -> void:
	if _sweep:
		_sweep.kill()
	var half: float = deg_to_rad(settings.arc) * 0.5
	var duration: float = SWEEP_SHARE / settings.attack_rate
	_model.rotation.y = half
	_sweep = create_tween()
	_sweep.tween_property(_model, ^"rotation:y", -half, duration * 0.4)
	_sweep.tween_property(_model, ^"rotation:y", 0.0, duration * 0.6)
