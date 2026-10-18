extends GutTest
## Ground hazards (`GroundHazard`): slick ice makes players and aliens slide a little, vents burst
## after a warning and hurt whoever stands on them, shards hurt a little every moment, mud slows
## walking (not the dash).

const SWARMER: AlienStrain = preload("res://game/aliens/strains/swarmer/swarmer.tres")
const PLAYER_SCENE: PackedScene = preload("res://game/player/player.tscn")
const REAL_TIME := preload("res://tests/support/real_time.gd")
const DASH: Skill = preload("res://game/progression/skills/tree/dash.tres")
const GRIP: float = 0.15
const MUD_SPEED: float = 0.6

var _arena: Node3D
var _player: Player


func before_each() -> void:
	_arena = Node3D.new()
	add_child_autofree(_arena)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100.0, 1.0, 100.0)
	floor_shape.shape = box
	floor_shape.position.y = -0.5
	floor_body.add_child(floor_shape)
	_arena.add_child(floor_body)
	_player = PLAYER_SCENE.instantiate() as Player
	_arena.add_child(_player)


func after_each() -> void:
	for action: StringName in InputMap.get_actions():
		Input.action_release(action)


func test_feet_grip_as_usual_without_hazards() -> void:
	assert_eq(_player.ground_contact.grip(), 1.0)


## On slick ice the player gets up to speed (and stops) much slower: they slide a little.
func test_player_slides_on_slick_ice() -> void:
	var normal: float = await _speed_after_starting()
	_player.velocity = Vector3.ZERO
	_add_ice(_player.global_position)
	await wait_physics_frames(3)
	assert_eq(_player.ground_contact.grip(), GRIP, "stands on the ice")
	var slick: float = await _speed_after_starting()
	assert_gt(normal, 3.0, "speeds up on ordinary ground")
	assert_lt(slick, normal * 0.5, "slides on the ice")
	# Up to speed, then letting go: it takes a while to stop.
	Input.action_press(&"move_right")
	await wait_physics_frames(60)
	Input.action_release(&"move_right")
	await wait_physics_frames(6)
	assert_gt(Vector2(_player.velocity.x, _player.velocity.z).length(), 2.0, "slides on")


func test_aliens_slide_too() -> void:
	var alien := SWARMER.spawn()
	alien.position = Vector3(20.0, 0.0, 0.0)
	_arena.add_child(alien)
	_add_ice(alien.global_position)
	await wait_physics_frames(3)
	assert_eq(alien.ground_contact.grip(), GRIP)


## Stepping off the ice, or the ice going away with its location, gives the grip back.
func test_grip_comes_back_off_the_ice() -> void:
	var ice: GroundHazard = _add_ice(_player.global_position)
	await wait_physics_frames(3)
	assert_eq(_player.ground_contact.grip(), GRIP)
	_player.global_position += Vector3(30.0, 0.0, 0.0)
	await wait_physics_frames(3)
	assert_eq(_player.ground_contact.grip(), 1.0, "stepped off")
	ice.global_position = _player.global_position
	await wait_physics_frames(3)
	assert_eq(_player.ground_contact.grip(), GRIP, "back on")
	ice.free()
	assert_eq(_player.ground_contact.grip(), 1.0, "ice gone")


## The least grip counts where hazards overlap.
func test_least_grip_counts() -> void:
	var contact := GroundContact.new()
	var ice := GroundHazard.new()
	ice.grip = 0.2
	var slush := GroundHazard.new()
	slush.grip = 0.6
	contact.enter(slush)
	contact.enter(ice)
	assert_eq(contact.grip(), 0.2)
	contact.leave(ice)
	assert_eq(contact.grip(), 0.6)
	ice.free()
	slush.free()


## A vent glows and rumbles first, then bursts, hurting the player standing on it, and rests again.
func test_vent_warns_then_bursts() -> void:
	var vent: GroundVent = _add_vent(_player.global_position)
	await wait_physics_frames(3)
	var health: float = _player.health
	assert_false(vent.is_warning(), "rests first")
	var warned: bool = await REAL_TIME.wait_until(vent.is_warning, 10.0)
	assert_true(warned, "glows before it bursts")
	assert_eq(_player.health, health, "no harm while it warns")
	var burst: bool = await REAL_TIME.wait_until(
		func() -> bool: return _player.health < health, 5.0
	)
	assert_true(burst, "bursts")
	assert_almost_eq(_player.health, health - vent.damage, 0.01)
	assert_false(vent.is_warning(), "rests again")


## A burst hurts aliens on the vent too, not the ones beside it.
func test_vent_hurts_aliens() -> void:
	var at := Vector3(30.0, 0.0, 0.0)
	var vent: GroundVent = _add_vent(at)
	var alien := SWARMER.spawn()
	alien.position = at
	_arena.add_child(alien)
	var beside := SWARMER.spawn()
	beside.position = at + Vector3(8.0, 0.0, 0.0)
	_arena.add_child(beside)
	await wait_physics_frames(3)
	vent.hurt(vent.damage)
	assert_almost_eq(alien.health, alien.max_health() - vent.damage, 0.01)
	assert_eq(beside.health, beside.max_health())


## Shards hurt the player standing on them a little all the time, and stop once they step off.
func test_shards_hurt_while_standing_on_them() -> void:
	var shards: GroundShards = _add_shards(_player.global_position)
	await wait_physics_frames(3)
	var health: float = _player.health
	await wait_physics_frames(Engine.physics_ticks_per_second * 2)
	var hurt: float = health - _player.health
	assert_almost_eq(
		hurt, shards.damage_per_second * 2.0, shards.damage_per_second * GroundShards.TICK
	)
	_player.global_position += Vector3(20.0, 0.0, 0.0)
	await wait_physics_frames(3)
	health = _player.health
	await wait_physics_frames(Engine.physics_ticks_per_second)
	assert_eq(_player.health, health, "off the shards")


## In mud the player walks at its share of their speed, and walks as usual again once out.
func test_mud_slows_walking() -> void:
	var mud: GroundMud = _add_mud(_player.global_position)
	await wait_physics_frames(3)
	assert_eq(_player.ground_contact.speed(), MUD_SPEED, "stands in the mud")
	Input.action_press(&"move_right")
	await wait_physics_frames(20)
	var slowed: float = Vector2(_player.velocity.x, _player.velocity.z).length()
	assert_almost_eq(slowed, _player.settings.move_speed * MUD_SPEED, 0.05)
	mud.global_position += Vector3(40.0, 0.0, 0.0)
	await wait_physics_frames(20)
	var walking: float = Vector2(_player.velocity.x, _player.velocity.z).length()
	assert_almost_eq(walking, _player.settings.move_speed, 0.05, "out of the mud")


## The dash isn't slowed by the mud: it's the way out.
func test_dash_is_not_slowed_by_mud() -> void:
	_player.skills.raise(DASH)
	_add_mud(_player.global_position)
	await wait_physics_frames(3)
	assert_true(_player.suit_dash.dash(Vector3.RIGHT))
	await wait_physics_frames(1)
	var dashing: float = Vector2(_player.velocity.x, _player.velocity.z).length()
	var settings: PlayerSettings = _player.settings
	assert_almost_eq(dashing, settings.dash_distance / settings.dash_time, 0.05)


func test_mud_slows_aliens() -> void:
	var alien := SWARMER.spawn()
	alien.position = Vector3(20.0, 0.0, 0.0)
	_arena.add_child(alien)
	_add_mud(alien.global_position)
	await wait_physics_frames(3)
	assert_eq(alien.ground_contact.speed(), MUD_SPEED)
	assert_eq(_player.ground_contact.speed(), 1.0, "not the player beside it")


## How fast the player runs after moving right for a few physics frames from standing.
func _speed_after_starting() -> float:
	Input.action_press(&"move_right")
	await wait_physics_frames(6)
	var speed: float = Vector2(_player.velocity.x, _player.velocity.z).length()
	Input.action_release(&"move_right")
	return speed


func _add_ice(at: Vector3) -> GroundHazard:
	var ice := GroundHazard.new()
	ice.grip = GRIP
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 6.0
	cylinder.height = 3.0
	var shape := CollisionShape3D.new()
	shape.shape = cylinder
	ice.add_child(shape)
	_arena.add_child(ice)
	ice.global_position = at
	return ice


func _add_shards(at: Vector3) -> GroundShards:
	var shards := GroundShards.new()
	shards.collision_layer = 0
	shards.collision_mask = PhysicsLayers.WORLD
	var cylinder := CylinderShape3D.new()
	cylinder.radius = shards.radius
	cylinder.height = 3.0
	var shape := CollisionShape3D.new()
	shape.shape = cylinder
	shards.add_child(shape)
	_arena.add_child(shards)
	shards.global_position = at
	return shards


func _add_mud(at: Vector3) -> GroundMud:
	var mud := GroundMud.new()
	mud.speed = MUD_SPEED
	mud.collision_layer = 0
	mud.collision_mask = PhysicsLayers.WORLD
	var cylinder := CylinderShape3D.new()
	cylinder.radius = mud.radius
	cylinder.height = 3.0
	var shape := CollisionShape3D.new()
	shape.shape = cylinder
	mud.add_child(shape)
	_arena.add_child(mud)
	mud.global_position = at
	return mud


func _add_vent(at: Vector3) -> GroundVent:
	var vent := GroundVent.new()
	vent.rest = Vector2(0.5, 0.5)
	vent.warning = 0.5
	vent.collision_layer = 0
	vent.collision_mask = PhysicsLayers.WORLD
	var cylinder := CylinderShape3D.new()
	cylinder.radius = vent.radius
	cylinder.height = 3.0
	var shape := CollisionShape3D.new()
	shape.shape = cylinder
	vent.add_child(shape)
	_arena.add_child(vent)
	vent.global_position = at
	return vent
