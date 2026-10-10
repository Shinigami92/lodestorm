extends GutTest

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const CYAN: OreType = preload("res://scenes/mining/ores/ore_cyan.tres")
const GREEN: OreType = preload("res://scenes/mining/ores/ore_green.tres")

var _player: Player
var _rack: CargoRack


func before_each() -> void:
	_player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(_player)
	_rack = _player.get_node("CargoRack") as CargoRack
	_rack.units_per_canister = 100.0


func test_empty_without_cargo() -> void:
	assert_eq(_rack.get_child_count(), 0)
	assert_eq(_rack.canister_count(CYAN), 0)


func test_partial_canister_fills_up() -> void:
	_player.add_cargo(CYAN, 25.0)
	assert_eq(_rack.canister_count(CYAN), 1)
	assert_almost_eq(_rack.top_fill(CYAN), 0.25, 0.001)
	_player.add_cargo(CYAN, 50.0)
	assert_eq(_rack.canister_count(CYAN), 1)
	assert_almost_eq(_rack.top_fill(CYAN), 0.75, 0.001)


func test_full_canisters_stack_up() -> void:
	_player.add_cargo(CYAN, 100.0)
	assert_eq(_rack.canister_count(CYAN), 1)
	assert_almost_eq(_rack.top_fill(CYAN), 1.0, 0.001)
	_player.add_cargo(CYAN, 130.0)
	assert_eq(_rack.canister_count(CYAN), 3)
	assert_almost_eq(_rack.top_fill(CYAN), 0.3, 0.001)


func test_one_column_per_ore_type() -> void:
	_player.add_cargo(CYAN, 10.0)
	_player.add_cargo(GREEN, 150.0)
	assert_eq(_rack.get_child_count(), 2)
	assert_eq(_rack.canister_count(CYAN), 1)
	assert_eq(_rack.canister_count(GREEN), 2)
	var cyan_x: float = (_rack.get_child(0) as Node3D).position.x
	var green_x: float = (_rack.get_child(1) as Node3D).position.x
	assert_almost_eq(cyan_x, -green_x, 0.001, "columns are centered")
	assert_gt(green_x - cyan_x, CargoRack.CANISTER_RADIUS * 2.0, "columns don't overlap")


func test_shrinks_when_cargo_goes_down() -> void:
	_rack.show_cargo(CYAN, 250.0)
	assert_eq(_rack.canister_count(CYAN), 3)
	_rack.show_cargo(CYAN, 40.0)
	assert_eq(_rack.canister_count(CYAN), 1)
	assert_almost_eq(_rack.top_fill(CYAN), 0.4, 0.001)
	_rack.show_cargo(CYAN, 0.0)
	assert_eq(_rack.canister_count(CYAN), 0)
