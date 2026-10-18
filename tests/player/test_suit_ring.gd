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


func test_tilts_with_the_ground() -> void:
	var slope := Basis(Vector3.RIGHT, deg_to_rad(15.0))
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 1.0, 20.0)
	shape.shape = box
	body.add_child(shape)
	body.transform = Transform3D(slope, slope * Vector3(0.0, -0.5, 0.0))
	add_child_autofree(body)
	_player.global_position = Vector3.UP * 0.2
	await wait_physics_frames(30)
	assert_true(_player.is_on_floor())
	var normal: Vector3 = slope * Vector3.UP
	assert_almost_eq(_ring.global_basis.y.normalized().dot(normal), 1.0, 0.01)


func test_tilting_copes_with_a_normal_a_hair_away() -> void:
	# A slerp errors here ("axis must be normalized"), which fails the test.
	for exponent: int in range(10, 36):
		var hair: float = pow(10.0, -exponent)
		var up: Vector3 = SuitRing.tilt_towards(Vector3.UP, Vector3(hair, 1.0, hair), 0.5)
		assert_almost_eq(up.dot(Vector3.UP), 1.0, 0.0001)


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
