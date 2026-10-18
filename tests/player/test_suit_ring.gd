extends GutTest

const PLAYER_SCENE: PackedScene = preload("res://game/player/player.tscn")
const SHOTGUN: WeaponType = preload("res://game/weapons/types/shotgun.tres")

var _player: Player
var _ring: SuitRing


func before_each() -> void:
	_player = PLAYER_SCENE.instantiate() as Player
	_ring = _player.get_node("SuitRing") as SuitRing
	# Before its first frame lights everything up.
	_ring.lit_time = 0.2
	add_child_autofree(_player)
	await wait_process_frames(1)


func test_health_arc_shows_the_share_in_its_color() -> void:
	assert_true(_ring.visible)
	assert_eq(_number(&"health_fill"), 1.0)
	_player.take_damage(_player.max_health() * 0.6)
	await wait_process_frames(1)
	assert_eq(_shown_rgb(&"health_color"), _rgb(SuitLight.COLOR_FLASH), "flashes white")
	await wait_seconds(SuitLight.FLASH_DURATION + 0.1)
	assert_almost_eq(_number(&"health_fill"), 0.4, 0.001)
	assert_eq(_shown_rgb(&"health_color"), _rgb(SuitLight.COLOR_HURT))


func test_arcs_dim_after_a_while_unless_low() -> void:
	await wait_seconds(0.2 + SuitRing.FADE_TIME + 0.2)
	assert_eq(_ring.health_glow, 0.0, "full health dims")
	assert_eq(_ring.ammo_glow, 0.0, "a full magazine dims")
	_player.take_damage(_player.max_health() * 0.6)
	(_player.weapon as RangedWeapon).rounds = 2
	await wait_seconds(0.2 + SuitRing.FADE_TIME + 0.2)
	assert_eq(_ring.health_glow, 1.0, "below half stays lit")
	assert_eq(_ring.ammo_glow, 1.0, "nearly empty stays lit")
	_player.heal()
	(_player.weapon as RangedWeapon).rounds = 10
	await wait_process_frames(2)
	assert_gt(_ring.health_glow, 0.0, "a change lights it up")
	await wait_seconds(0.2 + SuitRing.FADE_TIME + 0.2)
	assert_eq(_ring.health_glow, 0.0)
	assert_eq(_ring.ammo_glow, 0.0)


func test_hits_mark_where_they_came_from() -> void:
	# No camera: the screen's top is -Z.
	_player.take_damage(5.0, _player.global_position + Vector3(4.0, 0.0, 0.0))
	_player.take_damage(5.0, _player.global_position + Vector3(0.0, 0.0, 4.0))
	_player.take_damage(5.0)
	await wait_process_frames(1)
	assert_eq(_ring.hits.size(), 2, "the storm's damage comes from nowhere")
	assert_almost_eq(_ring.hits[0].x, 0.25, 0.01, "to the right")
	assert_almost_eq(_ring.hits[1].x, 0.5, 0.01, "towards the camera")
	await wait_seconds(SuitRing.HIT_TIME + 0.1)
	assert_eq(_ring.hits.size(), 0, "the marks fade")


func test_shotgun_shows_its_rounds_as_segments() -> void:
	assert_eq(_number(&"ammo_segments"), 0.0, "the blaster's magazine is one bar")
	_player.arsenal.unlock(SHOTGUN)
	_player.loadout.assign(0, SHOTGUN)
	await wait_process_frames(1)
	var shotgun := _player.weapon as RangedWeapon
	assert_eq(_number(&"ammo_segments"), float(shotgun.capacity()))


func test_quiet_aboard_and_hidden_when_dead() -> void:
	_player.weapon_allowed = false
	await wait_process_frames(1)
	assert_false(_ring.shows_ammo(), "no ammo arc with the weapon holstered")
	assert_eq(_number(&"outline_alpha"), 0.0, "no outline aboard")
	_player.take_damage(_player.max_health())
	await wait_process_frames(1)
	assert_false(_ring.visible)


func _shown_rgb(parameter: StringName) -> Color:
	var color: Color = _ring.shown(parameter)
	return _rgb(color)


static func _rgb(color: Color) -> Color:
	return Color(color, 1.0)


func _number(parameter: StringName) -> float:
	var value: float = _ring.shown(parameter)
	return value
