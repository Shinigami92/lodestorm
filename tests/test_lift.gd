extends GutTest

const TEST_MAP := preload("res://tests/support/test_map.gd")

var _map: Node3D
var _player: Player
var _ship: Ship
var _lift: Lift


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	_ship = _map.get_node("Ship") as Ship
	_lift = _ship.get_node("Lifts/NoseLift") as Lift
	_lift.speed = 9.0
	_lift.departure_delay = 0.1
	await wait_physics_frames(2)


func test_rider_goes_to_the_other_deck() -> void:
	await _move(_player, _lift.global_position + Vector3.UP * 0.1)
	await _wait_for_ride()
	assert_eq(_lift.deck, Lift.Deck.UPPER)
	assert_false(_lift.moving)
	assert_almost_eq(_ship.to_local(_player.global_position).y, 7.0, 0.2)


## Riders who came along have to step off before the lift leaves again.
func test_lift_waits_for_riders_to_step_off() -> void:
	await _move(_player, _lift.global_position + Vector3.UP * 0.1)
	await _wait_for_ride()
	await _wait_for_ride()
	assert_eq(_lift.deck, Lift.Deck.UPPER)


func test_player_at_the_gate_calls_the_lift() -> void:
	await _move(_player, _lift.to_global(Vector3(0.0, 4.5, 4.75)))
	await _wait_for_ride()
	assert_eq(_lift.deck, Lift.Deck.UPPER)
	assert_true(_lift.is_open(Lift.Deck.UPPER))


## The gate on a deck without the platform blocks the shaft; it opens once the platform is there.
func test_gates_close_the_empty_shaft() -> void:
	var lobby: Vector3 = _lift.to_global(Vector3(0.0, 5.5, 4.75))
	var shaft: Vector3 = _lift.to_global(Vector3(0.0, 5.5, 0.0))
	assert_false(_lift.is_open(Lift.Deck.UPPER))
	var gate: Node = _lift.get_node("UpperGate")
	assert_eq(_collider(lobby, shaft), gate)
	await _move(_player, lobby + Vector3.DOWN)
	await _wait_for_ride()
	assert_true(_lift.is_open(Lift.Deck.UPPER))
	assert_false(_lift.is_open(Lift.Deck.LOWER))
	assert_ne(_collider(lobby, shaft), gate)


func test_cargo_bay_lift_reaches_the_mess_hall() -> void:
	var lift: Lift = _ship.get_node("Lifts/CargoLift")
	lift.speed = 9.0
	lift.departure_delay = 0.1
	await _move(_player, lift.global_position + Vector3.UP * 0.1)
	await _wait_for_ride()
	assert_eq(lift.deck, Lift.Deck.UPPER)
	var mess: Vector3 = (_ship.get_node("Rooms/Upper/MessHall") as Node3D).global_position
	var exit: Vector3 = lift.to_global(Vector3(0.0, 5.5, 0.0))
	assert_eq(_ray(exit, Vector3(mess.x, exit.y, exit.z)), {}, "door into the mess hall")


func _wait_for_ride() -> void:
	var seconds: float = _lift.departure_delay + _lift.travel_height / _lift.speed + 0.3
	await wait_physics_frames(ceili(seconds * Engine.physics_ticks_per_second))


## What a ray from `from` to `to` hits first, or null.
func _collider(from: Vector3, to: Vector3) -> Object:
	return _ray(from, to).get(&"collider")


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_player.get_rid()]
	return _ship.get_world_3d().direct_space_state.intersect_ray(query)


func _move(player: Player, target: Vector3) -> void:
	player.global_position = target
	player.reset_physics_interpolation()
	await wait_physics_frames(5)
