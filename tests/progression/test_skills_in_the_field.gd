extends GutTest
## What the rescue drone, the hardened canister, rebuilding spares and the miner radar do for the
## player (see docs/design/progression.md).

const PLAYER_SCENE: PackedScene = preload("res://game/player/player.tscn")
const ORE_NODE: PackedScene = preload("res://game/mining/ore_node.tscn")
const MINER_SCENE: PackedScene = preload("res://game/mining/miner.tscn")
const KYRITE: OreType = preload("res://game/ores/types/ore_kyrite.tres")
const MERIDINE: OreType = preload("res://game/ores/types/ore_meridine.tres")
const SUIT: Skill = preload("res://game/progression/skills/tree/reinforced_suit.tres")
const REGENERATION: Skill = preload("res://game/progression/skills/tree/regeneration.tres")
const DRONE: Skill = preload("res://game/progression/skills/tree/rescue_drone.tres")
const CANISTER: Skill = preload("res://game/progression/skills/tree/hardened_canister.tres")
const SPARES: Skill = preload("res://game/progression/skills/tree/spare_magazines.tres")
const CAREFUL: Skill = preload("res://game/progression/skills/tree/careful_reload.tres")
const REBUILDING: Skill = preload("res://game/progression/skills/tree/rebuilding_spares.tres")
const SCANNER: Skill = preload("res://game/progression/skills/tree/ore_scanner.tres")
const RADAR: Skill = preload("res://game/progression/skills/tree/miner_radar.tres")
const SWARMER: AlienStrain = preload("res://game/aliens/strains/swarmer/swarmer.tres")

var _arena: Node3D
var _player: Player


func before_each() -> void:
	_arena = Node3D.new()
	add_child_autofree(_arena)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0.0, -0.5, 0.0)
	_arena.add_child(body)
	_player = PLAYER_SCENE.instantiate() as Player
	_player.settings = _player.settings.duplicate() as PlayerSettings
	_arena.add_child(_player)
	await wait_physics_frames(2)


func test_rescue_drone_sits_on_the_backpack_while_ready() -> void:
	var drone: RescueDrone = _player.rescue_drone
	var model := drone.get_node("Model") as Node3D
	await wait_physics_frames(1)
	assert_false(drone.is_ready(), "not learned")
	assert_false(model.visible)
	assert_eq(_player.vitals.bleed_out, 0.0, "dies at once without it")
	_learn_drone()
	await wait_physics_frames(1)
	assert_true(drone.is_ready())
	assert_true(model.visible)
	assert_gt(
		_player.vitals.bleed_out, _player.settings.rescue_wait, "longer than the longest wait"
	)


func test_rescue_drone_gets_the_player_up_once_per_run() -> void:
	_learn_drone()
	_player.cargo.add(KYRITE, 100.0)
	await wait_physics_frames(1)
	_player.take_damage(_player.max_health() * 2.0)
	assert_true(_player.down, "down, not dead")
	assert_eq(_player.cargo.amount(KYRITE), 100.0, "keeps what it carries")
	assert_eq(_player.rescue_drone.state, RescueDrone.State.RESCUING)
	await _wait_physics(_player.settings.rescue_time - 0.5)
	assert_true(_player.down, "lies still meanwhile")
	await _wait_physics(0.7)
	assert_false(_player.fallen)
	assert_almost_eq(_player.health, _player.max_health() * _player.settings.rescue_health, 0.01)
	assert_eq(_player.cargo.amount(KYRITE), 100.0)
	assert_false(_player.rescue_drone.is_ready(), "used for this run")
	await _wait_physics(RescueDrone.FLARE_TIME + 0.1)
	_player.take_damage(_player.max_health() * 2.0)
	assert_true(_player.dead, "once per run")
	_player.rescue_drone.restock()
	assert_true(_player.rescue_drone.is_ready(), "ready again for the next run")


func test_rescue_drone_waits_until_no_alien_is_close() -> void:
	_learn_drone()
	var alien: Alien = _add_alien(Vector3(3.0, 0.0, 0.0))
	await wait_physics_frames(1)
	_player.take_damage(_player.max_health() * 2.0)
	await _wait_physics(_player.settings.rescue_time + 0.3)
	assert_true(_player.down, "an alien within the gap")
	alien.global_position = Vector3(_player.settings.rescue_gap + 2.0, 0.0, 0.0)
	alien.reset_physics_interpolation()
	await _wait_physics(0.2)
	assert_false(_player.fallen, "up once it's gone")
	assert_false(alien.is_staggered(), "beyond the flash")


func test_rescue_drone_gives_up_waiting_and_flashes() -> void:
	_learn_drone()
	var alien: Alien = _add_alien(Vector3(3.0, 0.0, 0.0))
	await wait_physics_frames(1)
	_player.take_damage(_player.max_health() * 2.0)
	await _wait_physics(_player.settings.rescue_wait - 0.1)
	assert_true(_player.down, "still waiting")
	var before: float = alien.horizontal_distance(_player)
	await _wait_physics(0.2)
	assert_false(_player.fallen, "up at the longest wait")
	assert_eq(_player.rescue_drone.state, RescueDrone.State.FLARING)
	assert_true(alien.is_staggered(), "the flash staggers it")
	await _wait_physics(0.3)
	assert_gt(alien.horizontal_distance(_player), before + 0.3, "pushed away")
	await _wait_physics(RescueDrone.FLARE_TIME)
	assert_eq(_player.rescue_drone.state, RescueDrone.State.DOCKED)


func test_rescue_drone_shows_as_a_tick_on_the_health_arc() -> void:
	var ring := _player.get_node("SuitRing") as SuitRing
	await wait_process_frames(1)
	assert_eq(ring.drone_alpha, 0.0, "not learned")
	_learn_drone()
	await wait_physics_frames(1)
	await wait_process_frames(1)
	assert_gt(ring.drone_alpha, 0.0)
	_player.take_damage(_player.max_health() * 2.0)
	await _wait_physics(_player.settings.rescue_time + 0.1)
	await wait_process_frames(1)
	assert_eq(ring.drone_alpha, 0.0, "gone once used")


func test_hardened_canister_keeps_the_rarest_share_on_death() -> void:
	_player.skills.raise(SUIT)
	_player.skills.raise(CANISTER)
	_player.cargo.add(KYRITE, 100.0)
	_player.cargo.add(MERIDINE, 20.0)
	var rack := _player.get_node("CargoRack") as CargoRack
	assert_almost_eq(rack.tube_band(0), 30.0 / rack.units_per_tube, 0.001, "behind the band")
	_player.take_damage(_player.max_health() * 2.0)
	assert_true(_player.dead)
	assert_true(_player.cargo.is_empty(), "the rest is lost")
	assert_almost_eq(_player.cargo.secured.get(MERIDINE, 0.0) as float, 20.0, 0.001)
	assert_almost_eq(_player.cargo.secured.get(KYRITE, 0.0) as float, 10.0, 0.001)
	var secured: Dictionary[OreType, float] = _player.cargo.take_secured()
	assert_eq(secured.size(), 2)
	assert_true(_player.cargo.secured.is_empty())


func test_hardened_canister_rank_two_keeps_half() -> void:
	_player.skills.raise(SUIT)
	_player.skills.raise(CANISTER)
	_player.skills.raise(CANISTER)
	_player.cargo.add(KYRITE, 100.0)
	_player.take_damage(_player.max_health() * 2.0)
	assert_almost_eq(_player.cargo.secured.get(KYRITE, 0.0) as float, 50.0, 0.001)


func test_rebuilding_spares_refills_an_empty_spare_from_ore() -> void:
	_learn_rebuilding()
	var harl := _player.arms.get_ammo() as MagazineAmmo
	var capacity: int = harl.capacity()
	var full: int = _player.arms.spare_magazines * capacity
	harl.spare_rounds = full - capacity - 5
	_player.cargo.add(KYRITE, 1000.0)
	var every: float = _player.skills.value(Skill.Effect.REBUILDING_SPARES)
	_player.arms.rebuild_time = every - 0.1
	await _wait_physics(0.2)
	assert_eq(harl.spare_rounds, full - 5, "one magazine")
	var paid: float = capacity * harl.feed.ore_per_round / KYRITE.ammo_yield
	assert_almost_eq(_player.cargo.amount(KYRITE), 1000.0 - paid, 0.01, "paid like a reload")
	_player.arms.rebuild_time = every - 0.1
	await _wait_physics(0.2)
	assert_eq(harl.spare_rounds, full, "only what's missing")
	await _wait_physics(0.2)
	assert_eq(_player.arms.rebuild_time, 0.0, "nothing to rebuild")


func test_rebuilding_spares_waits_for_ore_and_needs_to_be_outside() -> void:
	_learn_rebuilding()
	var harl := _player.arms.get_ammo() as MagazineAmmo
	harl.spare_rounds = 0
	_player.arms.rebuild_time = 1.0
	await _wait_physics(0.2)
	assert_almost_eq(_player.arms.rebuild_time, 1.0, 0.001, "waits without ore")
	_player.cargo.add(KYRITE, 1000.0)
	_player.arms.ammo_free = true
	await _wait_physics(0.2)
	assert_eq(_player.arms.rebuild_time, 0.0, "aboard the ship's stock fills them")
	assert_eq(harl.spare_rounds, 0)


func test_miner_radar_points_to_miners_that_need_the_player() -> void:
	var radar := _player.get_node("MinerRadar") as MinerRadar
	var working: Miner = _add_miner(Vector3(0.0, 0.0, -30.0))
	var full: Miner = _add_miner(Vector3(30.0, 0.0, 0.0))
	var attacked: Miner = _add_miner(Vector3(-30.0, 0.0, 0.0))
	var near: Miner = _add_miner(Vector3(0.0, 0.0, 5.0))
	var someone_elses: Miner = _add_miner(Vector3(0.0, 0.0, 30.0), false)
	await wait_physics_frames(2)
	full.amount = full.capacity()
	near.amount = near.capacity()
	someone_elses.amount = someone_elses.capacity()
	attacked.take_damage(1.0)
	await wait_physics_frames(2)
	assert_eq(radar.shown().size(), 0, "not learned")
	_player.skills.raise(SCANNER)
	_player.skills.raise(RADAR)
	await wait_physics_frames(2)
	var shown: Array[RingPointer] = radar.shown()
	assert_eq(shown.size(), 2, "the full and the attacked one, not the near or working one")
	var headings: Array[Vector3] = []
	for pointer: RingPointer in shown:
		headings.append(pointer.heading().round())
		if pointer.heading().round() == Vector3.LEFT:
			assert_eq(pointer.priority, MinerRadar.ATTACKED_PRIORITY)
		else:
			assert_eq(Color(pointer.color, 1.0), Color(Miner.COLOR_DRY, 1.0), "amber")
	assert_has(headings, Vector3.RIGHT)
	assert_has(headings, Vector3.LEFT)
	assert_true(working.is_standing())
	await _wait_physics(MinerRadar.ATTACK_TIME + 0.1)
	assert_eq(radar.shown().size(), 1, "the attack is over")


func _learn_drone() -> void:
	_player.skills.raise(SUIT)
	_player.skills.raise(REGENERATION)
	_player.skills.raise(DRONE)


func _learn_rebuilding() -> void:
	_player.skills.raise(SPARES)
	_player.skills.raise(CAREFUL)
	_player.skills.raise(REBUILDING)


func _add_alien(at: Vector3) -> Alien:
	var alien: Alien = SWARMER.spawn()
	alien.position = at
	_arena.add_child(alien)
	return alien


## A miner standing on a new ore node at `at`, the player's own unless `own` is false.
func _add_miner(at: Vector3, own: bool = true) -> Miner:
	var node := ORE_NODE.instantiate() as OreNode
	node.ore_type = KYRITE
	node.position = at
	_arena.add_child(node)
	if not own:
		return node.place_miner(MINER_SCENE)
	return node.place_miner(MINER_SCENE, _player.fleet, _player)


## Waits `seconds` of physics time (physics frames: process time runs ahead on a busy runner).
func _wait_physics(seconds: float) -> void:
	await wait_physics_frames(ceili(seconds * Engine.physics_ticks_per_second))
