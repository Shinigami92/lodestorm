class_name AlienTargeting
extends RefCounted
## What an alien goes for (`Alien`'s helper, asked while it doesn't attack): sets its `target` by
## its role. It keeps chasing the target while it's in `strain.chase_range` (with a leash: while
## it's within `strain.leash` of home), otherwise picks the nearest prey in
## `strain.detection_range`. Hunters keep their prey and pick it from any distance. Raiders keep
## their miner until it breaks and pick the nearest working one from any distance, turning on a
## player only while one stands in reach; without a working miner they act like guards. Guards
## defending their nest go for its attacker first (`AlienStatus.defending`).

## Walking back to `Alien.home` after leaving a downed player alone (until it's there or finds
## prey).
var going_home: bool = false

var _alien: Alien


func _init(alien: Alien) -> void:
	_alien = alien


## Picks the alien's `target` (or none).
func update() -> void:
	if _alien.role == Alien.Role.GUARD and _defends():
		return
	if _alien.role == Alien.Role.RAIDER and _update_miner_target():
		var in_way: Player = _player_in_reach()
		if in_way:
			_alien.target = in_way
		return
	var tree: SceneTree = _alien.get_tree()
	var hunter: bool = _alien.role == Alien.Role.HUNTER
	if is_instance_valid(_alien.target) and _alien.target is Player:
		var chased := _alien.target as Player
		if Alien.is_prey(tree, chased) and (hunter or _keeps_chasing(chased)):
			return
		# It leaves a downed player alone and walks back towards its nest (see `RescueDrone`).
		going_home = going_home or chased.fallen
	_alien.target = null
	var nearest_distance: float = INF if hunter else _alien.strain.detection_range
	for player: Player in tree.get_nodes_in_group(Player.GROUP):
		if not Alien.is_prey(tree, player):
			continue
		var distance: float = _alien.horizontal_distance(player)
		if distance <= nearest_distance and (hunter or _within_leash(player)):
			_alien.target = player
			nearest_distance = distance
	going_home = going_home and _alien.target == null


## Whether it defends its nest (`status.defending`): the attacker is prey and within its leash,
## then it's the target. Otherwise it forgets them.
func _defends() -> bool:
	var status: AlienStatus = _alien.status
	if not is_instance_valid(status.defending):
		status.defending = null
		return false
	var attacker := status.defending as Player
	if attacker and Alien.is_prey(_alien.get_tree(), attacker) and _within_leash(attacker):
		_alien.target = attacker
		return true
	status.defending = null
	return false


## Whether a guard (or a raider without a miner) keeps chasing `node`: within its chase range,
## and with a leash, not too far from home.
func _keeps_chasing(node: Node3D) -> bool:
	return _alien.horizontal_distance(node) <= _alien.strain.chase_range and _within_leash(node)


## Whether `node` is within `strain.leash` of home (always without a leash).
func _within_leash(node: Node3D) -> bool:
	if _alien.strain.leash <= 0.0:
		return true
	var offset: Vector3 = node.global_position - _alien.home
	return Vector2(offset.x, offset.z).length() <= _alien.strain.leash


## A living player outside within reach of its closest attack (in a raider's way), or null.
func _player_in_reach() -> Player:
	var tree: SceneTree = _alien.get_tree()
	for player: Player in tree.get_nodes_in_group(Player.GROUP):
		if (
			Alien.is_prey(tree, player)
			and _alien.horizontal_distance(player) <= _alien.strain.reach()
		):
			return player
	return null


## Keeps the target miner while it works, otherwise picks the nearest working one. Returns
## whether there is one.
func _update_miner_target() -> bool:
	var target: Node3D = _alien.target
	if is_instance_valid(target) and target is Miner and not (target as Miner).broken:
		return true
	_alien.target = null
	var nearest_distance: float = INF
	for miner: Miner in _alien.get_tree().get_nodes_in_group(Miner.GROUP):
		var distance: float = _alien.horizontal_distance(miner)
		if not miner.broken and distance <= nearest_distance:
			_alien.target = miner
			nearest_distance = distance
	return _alien.target != null
