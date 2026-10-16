extends GutTest

const PLAYER_SCENE: PackedScene = preload("res://game/player/player.tscn")
const KYRITE: OreType = preload("res://game/ores/types/ore_kyrite.tres")
const OLVANE: OreType = preload("res://game/ores/types/ore_olvane.tres")
const VYREL: OreType = preload("res://game/ores/types/ore_vyrel.tres")
const CATALOG: OreCatalog = preload("res://game/ores/all_ores.tres")

var _player: Player
var _rack: CargoRack


func before_each() -> void:
	_player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(_player)
	_rack = _player.get_node("CargoRack") as CargoRack
	_rack.units_per_tube = 100.0
	_rack.units_per_canister = 50.0


func test_empty_without_cargo() -> void:
	assert_eq(_rack.layers().size(), 0)
	assert_eq(_rack.tube_fill(0), 0.0)
	assert_eq(_rack.canister_count(), 0)
	assert_eq(_visible_layers(_rack.get_node("Tube1")), 0)


func test_rarest_at_the_bottom() -> void:
	_player.add_cargo(KYRITE, 20.0)
	_player.add_cargo(VYREL, 10.0)
	_player.add_cargo(OLVANE, 30.0)
	var layers: Array[Array] = _rack.layers()
	assert_eq(layers.size(), 3)
	var bottom: OreType = layers[0][0]
	var top: OreType = layers[2][0]
	assert_eq(bottom, VYREL, "rarest first (bottom)")
	assert_eq(top, KYRITE, "commonest last (top)")
	assert_almost_eq(_rack.tube_fill(0), 0.6, 0.001)
	assert_eq(_visible_layers(_rack.get_node("Tube1")), 3)


func test_fills_the_tubes_then_canisters() -> void:
	_player.add_cargo(KYRITE, 150.0)
	assert_almost_eq(_rack.tube_fill(0), 1.0, 0.001)
	assert_almost_eq(_rack.tube_fill(1), 0.5, 0.001)
	assert_eq(_rack.canister_count(), 0)
	_player.add_cargo(KYRITE, 120.0)
	assert_eq(_rack.canister_count(), 2, "70 over the tubes: two canisters of 50")
	var left: Node3D = _rack.get_node("Canister1")
	var right: Node3D = _rack.get_node("Canister2")
	assert_lt(left.position.x, 0.0)
	assert_gt(right.position.x, 0.0)


func test_ammo_takes_from_the_top() -> void:
	_player.add_cargo(VYREL, 100.0)
	_player.add_cargo(KYRITE, 100.0)
	var tube_1: Node3D = _rack.get_node("Tube1")
	var tube_2: Node3D = _rack.get_node("Tube2")
	assert_eq(_layer_ore(tube_1, 0), VYREL, "rare ore fills the first tube")
	assert_eq(_layer_ore(tube_2, 0), KYRITE)
	_player.take_ore(KYRITE, 100.0)
	assert_eq(_visible_layers(tube_2), 0, "spending the common ore empties the top")
	assert_eq(_layer_ore(tube_1, 0), VYREL)


func test_at_most_max_canisters() -> void:
	_rack.show_cargo(KYRITE, 100000.0)
	assert_eq(_rack.canister_count(), _rack.max_canisters)


func test_canisters_go_when_cargo_goes_down() -> void:
	_rack.show_cargo(KYRITE, 400.0)
	assert_eq(_rack.canister_count(), 4)
	_rack.show_cargo(KYRITE, 40.0)
	assert_eq(_rack.canister_count(), 0)
	assert_almost_eq(_rack.tube_fill(0), 0.4, 0.001)
	_rack.show_cargo(KYRITE, 0.0)
	assert_eq(_rack.layers().size(), 0)


func test_every_ore_at_once() -> void:
	for ore_type: OreType in CATALOG.ores:
		_player.add_cargo(ore_type, 30.0)
	assert_eq(_rack.layers().size(), CATALOG.ores.size())
	assert_eq(
		_rack.canister_count(),
		mini(ceili((30.0 * CATALOG.ores.size() - 200.0) / 50.0), _rack.max_canisters)
	)
	var shown: int = 0
	for child: Node in _rack.get_children():
		shown += _visible_layers(child)
	assert_gte(shown, CATALOG.ores.size(), "every ore shows somewhere")


func _visible_layers(vessel: Node) -> int:
	var count: int = 0
	for segment: Node3D in vessel.get_node(^"Fill").get_children():
		if segment.visible:
			count += 1
	return count


func _layer_ore(vessel: Node, index: int) -> OreType:
	var segment: MeshInstance3D = vessel.get_node(^"Fill").get_child(index)
	for ore_type: OreType in CATALOG.ores:
		if ore_type.get_glow_material() == segment.material_override:
			return ore_type
	return null
