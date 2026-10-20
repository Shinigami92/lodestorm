class_name AlienCharge
extends AlienAttack
## A brute's charge: during the wind-up (head down, its eyes and back flaring) its line shows on the
## ground (`ChargeLine`, aimed at where the target stood when it started), then it runs along it at
## `charge_speed`, hitting every player within `width` of its path once, up to `overshoot` past the
## target's spot. A step out of the line dodges it. It runs through players (hitting them);
## running into rock, a miner or another alien ends it dazed for `daze` (its soft back open);
## otherwise it stands still for `recovery`.

## The target has to be between these distances to start (horizontally, in m).
@export var min_range: float = 5.0
@export var max_range: float = 14.0
## Speed of the charge, in m/s.
@export var charge_speed: float = 13.0
## How far past the target's spot it runs (m), and how far at most.
@export var overshoot: float = 3.0
@export var max_length: float = 18.0
## Players this close to its center while it runs are hit (horizontally, m).
@export var width: float = 1.3
## Seconds it stands dazed after running into something.
@export var daze: float = 1.5
## The target may stand this much higher or lower (m).
@export var max_height_difference: float = 1.5

## The line of the charge under way, how long it is (m) and the players it hit, per alien.
var _lines: Dictionary[Alien, ChargeLine] = {}
var _lengths: Dictionary[Alien, float] = {}
var _hit: Dictionary[Alien, Array] = {}


func moves() -> bool:
	return true


func prepare(alien: Alien) -> void:
	var offset: Vector3 = alien.target.global_position - alien.global_position
	offset.y = 0.0
	alien.attack_facing = offset.normalized()
	_lengths[alien] = minf(offset.length() + overshoot, max_length)
	var line := ChargeLine.new()
	line.length = _lengths[alien]
	line.width = width
	line.duration = wind_up
	_lines[alien] = line
	alien.get_parent().add_child(line)
	line.global_transform = Transform3D(
		Basis.looking_at(alien.attack_facing), alien.global_position
	)


func begin(alien: Alien) -> void:
	var direction: Vector3 = alien.attack_facing
	if direction == Vector3.ZERO:
		direction = -alien.global_basis.z
	var length: float = _lengths.get(alien, max_length)
	alien.lunge(direction, length, 0.0, true)
	_hit[alien] = []
	for player: Player in alien.get_tree().get_nodes_in_group(Player.GROUP):
		alien.add_collision_exception_with(player)


func act(alien: Alien, elapsed: float) -> bool:
	var hit: Array = _hit.get(alien, [])
	for player: Player in alien.get_tree().get_nodes_in_group(Player.GROUP):
		if player in hit or not Alien.is_prey(alien.get_tree(), player):
			continue
		var offset: Vector3 = player.global_position - alien.global_position
		if _can_hit(offset) and Vector2(offset.x, offset.z).length() <= width:
			Alien.hurt(player, damage * alien.damage_factor, alien.global_position)
			hit.append(player)
	if not alien.lunge_step(charge_speed, elapsed * charge_speed):
		return false
	_free_line(alien)
	if not hit.is_empty():
		alien.play_attack()
	if alien.lunge_stalled:
		alien.stagger_for.call_deferred(daze)
	return true


func finish(alien: Alien) -> void:
	_free_line(alien)
	_lengths.erase(alien)
	if _hit.erase(alien):
		for player: Player in alien.get_tree().get_nodes_in_group(Player.GROUP):
			alien.remove_collision_exception_with(player)


## Whether a player `offset` away from it (within `width`) is hit: not too far above or below.
func _can_hit(offset: Vector3) -> bool:
	return absf(offset.y) <= max_height_difference


## Takes the line off the ground once the charge is over or broken off.
func _free_line(alien: Alien) -> void:
	if _lines.has(alien):
		if is_instance_valid(_lines[alien]):
			_lines[alien].queue_free()
		_lines.erase(alien)


func _in_range(alien: Alien, target: Node3D, distance: float) -> bool:
	if distance < min_range or distance > max_range:
		return false
	return absf(target.global_position.y - alien.global_position.y) <= max_height_difference
