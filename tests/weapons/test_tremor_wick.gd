extends GutTest
## Tremor (shells lobbed in an arc, blasting where they land) and Wick (proximity charges tossed a
## short way), and the blast they share.

const SWARMER: AlienStrain = preload("res://game/aliens/strains/swarmer/swarmer.tres")
const PLAYER_SCENE: PackedScene = preload("res://game/player/player.tscn")
const PINNER: WeaponType = preload("res://game/weapons/types/pinner/pinner.tres")
const TREMOR: WeaponType = preload("res://game/weapons/types/tremor/tremor.tres")
const WICK: WeaponType = preload("res://game/weapons/types/wick/wick.tres")
const LOB: LobDelivery = preload("res://game/weapons/types/tremor/delivery.tres")
const CHARGES: ChargeDelivery = preload("res://game/weapons/types/wick/delivery.tres")
const TREMOR_DAMAGE: DamageEffect = preload("res://game/weapons/types/tremor/damage.tres")
const WICK_DAMAGE: DamageEffect = preload("res://game/weapons/types/wick/damage.tres")

var _arena: Node3D
var _player: Player


func before_each() -> void:
	_arena = Node3D.new()
	add_child_autofree(_arena)
	_add_box(Vector3(0.0, -0.5, 0.0), Vector3(100.0, 1.0, 100.0))
	_player = PLAYER_SCENE.instantiate() as Player
	_arena.add_child(_player)
	for weapon_type: WeaponType in [TREMOR, WICK]:
		_player.arsenal.unlock(weapon_type)
	await wait_physics_frames(1)


func after_each() -> void:
	Input.action_release(&"attack")


func test_tremor_lands_on_the_target_else_the_cursor_else_along_the_aim() -> void:
	var tremor: Weapon = _equip(TREMOR)
	var alien := _add_alien(Vector3(3.0, 0.0, -9.0), 100.0)
	await wait_physics_frames(1)
	tremor.aim_target = alien
	assert_almost_eq(LOB.landing_point(tremor), alien.global_position, Vector3.ONE * 0.01)
	tremor.aim_target = null
	tremor.aim_point = Vector3(-5.0, 0.0, -5.0)
	assert_almost_eq(LOB.landing_point(tremor), Vector3(-5.0, 0.0, -5.0), Vector3.ONE * 0.01)
	tremor.aim_point = Vector3(0.0, 0.0, -50.0)
	assert_almost_eq(
		LOB.landing_point(tremor), Vector3(0.0, 0.0, -LOB.reach), Vector3.ONE * 0.01, "its reach"
	)
	tremor.aim_point = Vector3.INF
	tremor.aim_direction = Vector3.RIGHT
	assert_almost_eq(
		LOB.landing_point(tremor),
		Vector3(LOB.stick_reach, 0.0, 0.0),
		Vector3.ONE * 0.01,
		"along the aim without a spot"
	)


func test_tremor_lands_on_a_rock_top_along_the_aim_but_not_on_a_deck_above() -> void:
	var tremor: Weapon = _equip(TREMOR)
	_add_box(Vector3(0.0, 1.25, -LOB.stick_reach), Vector3(3.0, 2.5, 3.0))
	_add_box(Vector3(LOB.stick_reach, 4.5, 0.0), Vector3(3.0, 0.2, 3.0))
	await wait_physics_frames(1)
	tremor.aim_point = Vector3.INF
	tremor.aim_direction = Vector3.FORWARD
	assert_almost_eq(LOB.landing_point(tremor).y, 2.5, 0.01, "the rock's top")
	tremor.aim_direction = Vector3.RIGHT
	assert_almost_eq(LOB.landing_point(tremor).y, 0.0, 0.01, "under the deck")


func test_tremor_blasts_where_it_lands_less_towards_the_edge_and_not_behind_rock() -> void:
	_equip(TREMOR)
	var spot := Vector3(0.0, 0.0, -LOB.stick_reach)
	var middle := _add_alien(spot, 1000.0)
	var edge := _add_alien(spot + Vector3(2.5, 0.0, 0.0), 1000.0)
	var sheltered := _add_alien(spot + Vector3(-2.5, 0.0, 0.0), 1000.0)
	var outside := _add_alien(spot + Vector3(0.0, 0.0, -LOB.blast_radius - 1.0), 1000.0)
	_add_box(spot + Vector3(-1.3, 1.5, 0.0), Vector3(0.3, 3.0, 3.0))
	await wait_seconds(TREMOR.draw_time + 0.05)
	await _attack_once()
	assert_eq(_player.arms.weapon.ammo.rounds, _player.arms.weapon.ammo.capacity() - 1)
	await wait_seconds(LOB.stick_reach / LOB.speed + 0.3)
	var full: float = TREMOR_DAMAGE.damage
	assert_almost_eq(_dealt(middle), full, full * 0.1, "the full blast in the middle")
	var share: float = Blast.share_at(2.5, LOB.blast_radius)
	assert_almost_eq(_dealt(edge), full * share, full * 0.08, "less towards the edge")
	assert_eq(_dealt(sheltered), 0.0, "rock shelters it")
	assert_eq(_dealt(outside), 0.0)


func test_tremor_stays_under_a_ceiling() -> void:
	_equip(TREMOR)
	_add_box(Vector3(0.0, 4.0, 0.0), Vector3(60.0, 0.2, 60.0))
	var spot := Vector3(0.0, 0.0, -LOB.stick_reach)
	var alien := _add_alien(spot, 1000.0)
	var shots: Array[LobbedShot] = []
	_arena.child_entered_tree.connect(
		func(node: Node) -> void:
			if node is LobbedShot:
				shots.append(node as LobbedShot)
	)
	await wait_seconds(TREMOR.draw_time + 0.05)
	await _attack_once()
	assert_eq(shots.size(), 1)
	var shot: LobbedShot = shots[0]
	var middle: float = lerpf(shot.start.y, shot.landing.y, 0.5)
	assert_lt(
		middle + shot.arc_height, 3.9 - LobDelivery.CEILING_MARGIN + 0.01, "under the ceiling"
	)
	await wait_seconds(LOB.stick_reach / LOB.speed + 0.3)
	assert_gt(_dealt(alien), TREMOR_DAMAGE.damage * 0.5, "it landed on the ground, not the ceiling")


func test_blast_hurts_no_player() -> void:
	var alien := _add_alien(_player.global_position + Vector3(1.5, 0.0, 0.0), 1000.0)
	await wait_physics_frames(1)
	var health: float = _player.health
	Blast.explode(
		_arena, _player.global_position, 3.0, Hit.new(50.0, 0.0, 0.0, Vector3.FORWARD, Vector3.ZERO)
	)
	assert_eq(_player.health, health)
	assert_gt(_dealt(alien), 0.0)


func test_tremor_blast_part_widens_the_blast() -> void:
	var part: WeaponPart = TREMOR.get_part(WeaponPart.Stat.BLAST)
	assert_not_null(part)
	for level: int in 7:
		_player.upgrades.raise(part)
	var tremor: Weapon = _equip(TREMOR)
	assert_almost_eq(LOB.blast_radius_of(tremor), LOB.blast_radius * part.multiplier(8), 0.001)
	assert_gt(LOB.blast_radius_of(tremor), LOB.blast_radius)


func test_wick_charge_flies_past_aliens_arms_and_trips_on_one_close() -> void:
	_equip(WICK)
	var passed := _add_alien(Vector3(0.0, 0.0, -1.2), 1000.0)
	await wait_seconds(WICK.draw_time + 0.05)
	await _attack_once()
	await wait_seconds(CHARGES.stick_reach / CHARGES.speed + 0.1)
	var placed: Array[PlacedCharge] = ChargeDelivery.placed_by(_player)
	assert_eq(placed.size(), 1)
	var charge: PlacedCharge = placed[0]
	assert_almost_eq(
		charge.global_position, Vector3(0.0, 0.0, -CHARGES.stick_reach), Vector3.ONE * 0.1
	)
	assert_false(charge.is_armed(), "arming")
	await wait_seconds(CHARGES.arm_time + 0.1)
	assert_true(charge.is_armed())
	assert_eq(_dealt(passed), 0.0, "an alien beyond its reach doesn't trip it")
	var close := _add_alien(charge.global_position + Vector3(1.0, 0.0, 0.0), 1000.0)
	await wait_seconds(PlacedCharge.CHECK_INTERVAL + 0.05)
	assert_true(charge.is_tripped())
	await wait_seconds(CHARGES.trip_time + 0.1)
	assert_false(is_instance_valid(charge), "blasted")
	var share: float = Blast.share_at(1.0, CHARGES.blast_radius)
	assert_almost_eq(_dealt(close), WICK_DAMAGE.damage * share, WICK_DAMAGE.damage * 0.1)


func test_wick_charges_ignore_players() -> void:
	_equip(WICK)
	await wait_seconds(WICK.draw_time + 0.05)
	await _attack_once()
	await wait_seconds(CHARGES.stick_reach / CHARGES.speed + CHARGES.arm_time + 0.2)
	var charge: PlacedCharge = ChargeDelivery.placed_by(_player)[0]
	assert_true(charge.is_armed())
	var teammate := PLAYER_SCENE.instantiate() as Player
	teammate.local = false
	teammate.number = 2
	_arena.add_child(teammate)
	teammate.global_position = charge.global_position + Vector3(0.5, 0.0, 0.0)
	await wait_seconds(0.5)
	assert_true(charge.is_armed(), "a player doesn't trip it")


func test_wick_one_charge_too_many_removes_the_oldest() -> void:
	_equip(WICK)
	await wait_seconds(WICK.draw_time + 0.05)
	var first: PlacedCharge
	for toss: int in CHARGES.charges + 1:
		await _attack_once()
		if toss == 0:
			first = ChargeDelivery.placed_by(_player)[0]
		await wait_seconds(1.0 / WICK.attack_rate)
	await wait_physics_frames(2)
	assert_eq(ChargeDelivery.placed_by(_player).size(), CHARGES.charges)
	assert_false(is_instance_valid(first), "the oldest is gone")


func test_wick_charges_part_lets_more_out() -> void:
	var part: WeaponPart = WICK.get_part(WeaponPart.Stat.CHARGES)
	assert_not_null(part)
	var wick: Weapon = _equip(WICK)
	assert_eq(CHARGES.charges_of(wick), CHARGES.charges)
	_player.upgrades.raise(part)
	wick.apply_upgrades(_player.upgrades)
	assert_eq(CHARGES.charges_of(wick), CHARGES.charges + 1, "one more per level")


func test_landing_ring_shows_where_it_lands_while_drawn() -> void:
	var tremor: Weapon = _equip(TREMOR)
	var ring := tremor.get_node("LandingRing") as LandingRing
	await wait_seconds(TREMOR.draw_time + 0.05)
	await wait_process_frames(1)
	assert_true(ring.visible)
	var landing: Vector3 = LOB.landing_point(tremor)
	assert_almost_eq(
		Vector2(ring.global_position.x, ring.global_position.z),
		Vector2(landing.x, landing.z),
		Vector2.ONE * 0.05
	)
	_player.loadout.assign(0, PINNER)
	await wait_process_frames(1)
	assert_false(
		is_instance_valid(ring) and ring.is_visible_in_tree(), "only with a lobbing weapon"
	)


func _equip(weapon_type: WeaponType) -> Weapon:
	_player.loadout.assign(0, weapon_type)
	assert_eq(_player.arms.get_weapon_type(), weapon_type)
	return _player.arms.weapon


func _attack_once() -> void:
	Input.action_press(&"attack")
	await wait_physics_frames(1)
	Input.action_release(&"attack")
	await wait_physics_frames(1)


func _dealt(alien: Alien) -> float:
	return alien.max_health() - alien.health


## An alien standing still (it notices nobody) with `health`.
func _add_alien(at: Vector3, health: float) -> Alien:
	var alien := SWARMER.spawn()
	alien.strain = alien.strain.duplicate() as AlienStrain
	alien.strain.max_health = health
	alien.strain.detection_range = 0.0
	alien.position = at
	_arena.add_child(alien)
	return alien


func _add_box(at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = at
	_arena.add_child(body)
