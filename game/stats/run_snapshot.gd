class_name RunSnapshot
extends RefCounted
## What a location holds, for the session log: its ore nodes and nests as a run starts (`map`), and
## what's left of them and of the aliens as it ends (`leftovers`). Positions are x and z in m.


## The ship's position, every ore node ([ore, x, z, units, rich]) and every nest ([x, z]).
static func map(tree: SceneTree, ship: Ship) -> Dictionary:
	var nodes: Array = []
	for node: OreNode in tree.get_nodes_in_group(OreNode.GROUP):
		var at: Array = xz(node.global_position)
		nodes.append(
			[GameEvents.id_of(node.ore_type), at[0], at[1], roundi(node.amount), node.rich]
		)
	var nests: Array = []
	for nest: AlienNest in tree.get_nodes_in_group(AlienNest.GROUP):
		nests.append(xz(nest.global_position))
	return {
		"ship": xz(ship.global_position) if ship else [],
		"nodes": nodes,
		"nests": nests,
	}


## What's left: the units still in the ore nodes by ore, how many nodes ran dry, the aliens alive
## by strain and the nests still standing.
static func leftovers(tree: SceneTree) -> Dictionary:
	var ore_left: Dictionary[String, int] = {}
	var dry: int = 0
	for node: OreNode in tree.get_nodes_in_group(OreNode.GROUP):
		var ore: String = GameEvents.id_of(node.ore_type)
		ore_left[ore] = ore_left.get_or_add(ore, 0) as int + roundi(maxf(node.amount, 0.0))
		if node.is_dry():
			dry += 1
	var aliens: Dictionary[String, int] = {}
	for alien: Alien in tree.get_nodes_in_group(Alien.GROUP):
		var strain: String = GameEvents.id_of(alien.strain)
		aliens[strain] = aliens.get_or_add(strain, 0) as int + 1
	return {
		"ore_left": ore_left,
		"nodes_dry": dry,
		"aliens": aliens,
		"nests": tree.get_nodes_in_group(AlienNest.GROUP).size(),
	}


## `position`'s x and z, to 0.1 m.
static func xz(position: Vector3) -> Array:
	return [snappedf(position.x, 0.1), snappedf(position.z, 0.1)]
