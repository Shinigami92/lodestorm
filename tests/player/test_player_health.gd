extends GutTest

const PLAYER_SCENE: PackedScene = preload("res://game/player/player.tscn")
const KYRITE: OreType = preload("res://game/ores/types/ore_kyrite.tres")

var _player: Player
var _light: SuitLight


func before_each() -> void:
	_player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(_player)
	_light = _player.get_node("SuitLight") as SuitLight
	watch_signals(_player)


func after_each() -> void:
	Input.action_release(&"move_right")


func test_starts_unhurt() -> void:
	assert_eq(_player.health, _player.settings.max_health)
	assert_false(_player.dead)
	assert_eq(_light.color, SuitLight.COLOR_HEALTHY)


func test_damage_lowers_health() -> void:
	_player.take_damage(30.0)
	assert_eq(_player.health, _player.settings.max_health - 30.0)
	assert_signal_emitted_with_parameters(_player, "health_changed", [_player.health])
	assert_false(_player.dead)


func test_suit_light_shows_health() -> void:
	var max_health: float = _player.settings.max_health
	_player.take_damage(max_health * 0.6)
	assert_eq(_light.color, SuitLight.COLOR_HURT)
	_player.take_damage(max_health * 0.2)
	assert_eq(_light.color, SuitLight.COLOR_CRITICAL)
	_player.heal()
	assert_eq(_light.color, SuitLight.COLOR_HEALTHY)


func test_dies_at_zero_health_and_drops_cargo() -> void:
	_player.cargo.add(KYRITE, 120.0)
	_player.take_damage(_player.settings.max_health + 50.0)
	assert_eq(_player.health, 0.0)
	assert_true(_player.dead)
	assert_signal_emit_count(_player, "died", 1)
	assert_true(_player.cargo.is_empty(), "everything carried is lost")
	assert_eq((_player.get_node("CargoRack") as CargoRack).total(), 0.0)
	assert_eq(_light.color, SuitLight.COLOR_DEAD)


func test_dead_player_stays_dead() -> void:
	_player.take_damage(_player.settings.max_health)
	_player.take_damage(10.0)
	_player.heal()
	assert_true(_player.dead)
	assert_eq(_player.health, 0.0)
	assert_signal_emit_count(_player, "died", 1)


func test_dead_player_cannot_move() -> void:
	_player.take_damage(_player.settings.max_health)
	var start: Vector3 = _player.global_position
	Input.action_press(&"move_right")
	await wait_physics_frames(10)
	assert_eq(_player.global_position, start)


func test_dead_player_gets_no_hose() -> void:
	assert_eq(Player.nearest(get_tree(), _player.global_position, 1.0), _player)
	_player.take_damage(_player.settings.max_health)
	assert_null(Player.nearest(get_tree(), _player.global_position, 1.0))


func test_respawn_restores_player() -> void:
	_player.take_damage(_player.settings.max_health)
	var spot := Vector3(3.0, 0.0, 4.0)
	_player.respawn(spot)
	assert_false(_player.dead)
	assert_eq(_player.health, _player.settings.max_health)
	assert_eq(_player.global_position, spot)
	assert_eq(_light.color, SuitLight.COLOR_HEALTHY)
	assert_true(_player.arms.weapon.visible, "weapon is drawn again outside the ship")


func test_goes_down_with_a_bleed_out_and_keeps_cargo() -> void:
	_player.vitals.bleed_out = 3.0
	_player.cargo.add(KYRITE, 120.0)
	_player.take_damage(_player.settings.max_health + 50.0)
	assert_true(_player.down)
	assert_true(_player.fallen)
	assert_false(_player.dead)
	assert_signal_not_emitted(_player, "died")
	assert_eq(_player.cargo.total(), 120.0, "nothing carried is lost while down")
	assert_null(Player.nearest(get_tree(), _player.global_position, 1.0), "aliens leave it alone")
	_player.take_damage(10.0)
	_player.heal()
	assert_eq(_player.health, 0.0, "a downed player neither takes damage nor heals")


func test_downed_player_gets_up() -> void:
	_player.vitals.bleed_out = 3.0
	_player.take_damage(_player.settings.max_health)
	assert_true(_player.vitals.get_up(0.5))
	assert_false(_player.fallen)
	assert_eq(_player.health, _player.max_health() * 0.5)
	assert_true(_player.arms.weapon.visible, "weapon is drawn again")
	assert_false(_player.vitals.get_up(0.5), "only a downed player gets up")


func test_downed_player_bleeds_out() -> void:
	_player.vitals.bleed_out = 0.1
	_player.cargo.add(KYRITE, 120.0)
	_player.take_damage(_player.settings.max_health)
	await wait_physics_frames(15)
	assert_true(_player.dead)
	assert_signal_emit_count(_player, "died", 1)
	assert_true(_player.cargo.is_empty(), "dying drops what it carried")
