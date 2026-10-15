extends GutTest
## What the skills do for the player (see GAME_DESIGN.md, Progression).

const ALIEN_SCENE: PackedScene = preload("res://scenes/aliens/alien.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const ORE_NODE: PackedScene = preload("res://scenes/mining/ore_node.tscn")
const MINER_SCENE: PackedScene = preload("res://scenes/mining/miner.tscn")
const BLASTER: WeaponType = preload("res://scenes/weapons/types/blaster.tres")
const HAMMER: WeaponType = preload("res://scenes/weapons/types/hammer.tres")
const ARMOR: Upgrade = preload("res://scenes/upgrades/armor.tres")
const CYAN: OreType = preload("res://scenes/mining/ores/ore_cyan.tres")
const TREE: SkillTree = preload("res://scenes/skills/skill_tree.tres")
const DASH: Skill = preload("res://scenes/skills/dash.tres")
const RELOAD_ON_THE_MOVE: Skill = preload("res://scenes/skills/reload_on_the_move.tres")
const SUIT: Skill = preload("res://scenes/skills/reinforced_suit.tres")
const REGENERATION: Skill = preload("res://scenes/skills/regeneration.tres")
const SPARES: Skill = preload("res://scenes/skills/spare_magazines.tres")
const CAREFUL: Skill = preload("res://scenes/skills/careful_reload.tres")
const SCANNER: Skill = preload("res://scenes/skills/ore_scanner.tres")
const READOUT: Skill = preload("res://scenes/skills/damage_readout.tres")

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


func after_each() -> void:
	for action: StringName in [&"move_right", &"dash"]:
		Input.action_release(action)


func test_every_skill_sits_in_one_cluster_with_its_requirement() -> void:
	var seen: Array[Skill] = []
	for cluster: SkillCluster in TREE.clusters:
		assert_false(cluster.skills.is_empty(), cluster.display_name)
		assert_null(cluster.skills[0].requires, "%s starts with a root" % cluster.display_name)
		for skill: Skill in cluster.skills:
			assert_does_not_have(seen, skill, skill.display_name)
			seen.append(skill)
			assert_gt(skill.max_rank(), 0, skill.display_name)
			assert_ne(skill.effect, Skill.Effect.NONE, skill.display_name)
			if skill.requires:
				assert_eq(TREE.cluster_of(skill.requires), cluster, "no gates between clusters")
			for rank: SkillRank in skill.ranks:
				assert_false(rank.cost.is_empty(), "%s costs ore" % skill.display_name)
	assert_eq(seen.size(), 8)


func test_ranks_open_in_order_up_to_the_highest() -> void:
	var skills := Skills.new()
	assert_eq(skills.rank(SUIT), 0)
	assert_false(skills.is_open(REGENERATION), "needs the reinforced suit")
	assert_false(skills.raise(REGENERATION))
	for i: int in SUIT.max_rank():
		assert_true(skills.raise(SUIT))
	assert_false(skills.raise(SUIT), "at the highest rank")
	assert_null(skills.next_rank(SUIT))
	assert_true(skills.is_open(REGENERATION))
	assert_true(skills.raise(REGENERATION))
	assert_eq(skills.value(Skill.Effect.HEALTH), SUIT.ranks[-1].value)
	assert_true(skills.has(Skill.Effect.REGENERATION))
	assert_false(skills.has(Skill.Effect.DASH))


func test_each_player_has_their_own_skills() -> void:
	var other := PLAYER_SCENE.instantiate() as Player
	_arena.add_child(other)
	_player.skills.raise(DASH)
	assert_eq(other.skills.rank(DASH), 0)


func test_reinforced_suit_adds_health_before_the_armor() -> void:
	var base: float = _player.settings.max_health
	_player.skills.raise(SUIT)
	assert_eq(_player.max_health(), base + SUIT.ranks[0].value)
	assert_eq(_player.health, _player.max_health(), "the extra health is there right away")
	_player.upgrades.raise(ARMOR)
	var armor: float = ARMOR.levels[0].multiplier
	assert_almost_eq(_player.max_health(), (base + SUIT.ranks[0].value) * armor, 0.001)


func test_regeneration_heals_after_a_while_without_damage() -> void:
	_player.settings.regeneration_delay = 0.5
	_player.skills.raise(SUIT)
	_player.skills.raise(REGENERATION)
	_player.take_damage(40.0)
	var hurt: float = _player.health
	await _wait_physics(0.3)
	assert_eq(_player.health, hurt, "not right after the damage")
	assert_false(_player.regenerating)
	await _wait_physics(0.5)
	assert_true(_player.regenerating)
	assert_gt(_player.health, hurt)
	await _wait_physics(40.0 / REGENERATION.ranks[0].value)
	assert_eq(_player.health, _player.max_health())
	assert_false(_player.regenerating, "stops at full health")


func test_no_regeneration_without_the_skill() -> void:
	_player.settings.regeneration_delay = 0.1
	_player.take_damage(20.0)
	var hurt: float = _player.health
	await _wait_physics(0.5)
	assert_eq(_player.health, hurt)


func test_dash_needs_the_skill_and_its_cooldown() -> void:
	assert_false(_player.suit_dash.dash(Vector3.RIGHT), "not learned")
	_player.skills.raise(DASH)
	var start: Vector3 = _player.global_position
	assert_true(_player.suit_dash.dash(Vector3.RIGHT))
	assert_false(_player.suit_dash.dash(Vector3.RIGHT), "cooling down")
	await _wait_physics(_player.settings.dash_time + 0.1)
	var moved: float = _player.global_position.x - start.x
	assert_almost_eq(moved, _player.settings.dash_distance, 0.6)
	assert_almost_eq(_player.global_position.z, start.z, 0.05)
	await _wait_physics(_player.settings.dash_cooldown)
	assert_eq(_player.suit_dash.cooldown, 0.0)
	assert_true(_player.suit_dash.dash(Vector3.RIGHT))


func test_dash_action_dashes_where_the_player_moves() -> void:
	_player.skills.raise(DASH)
	var strip := _player.get_node("DashStrip") as DashStrip
	await wait_process_frames(1)
	assert_true(strip.visible, "the strip shows with the skill")
	assert_eq(strip.fill, 1.0)
	Input.action_press(&"move_right")
	await wait_physics_frames(2)
	Input.action_press(&"dash")
	await wait_physics_frames(2)
	assert_true(_player.suit_dash.is_dashing())
	Input.action_release(&"dash")
	await wait_process_frames(2)
	assert_lt(strip.fill, 1.0, "the strip fills up again")
	assert_gt(_player.velocity.length(), _player.settings.move_speed * 2.0)


func test_reload_on_the_move_keeps_full_speed() -> void:
	var speeds: Array[float] = []
	for learned: bool in [false, true]:
		if learned:
			_player.skills.raise(DASH)
			_player.skills.raise(RELOAD_ON_THE_MOVE)
		var blaster := _player.weapon as RangedWeapon
		blaster.rounds = 1
		Input.action_press(&"move_right")
		assert_true(_player.reload())
		await _wait_physics(0.4)
		speeds.append(Vector2(_player.velocity.x, _player.velocity.z).length())
		Input.action_release(&"move_right")
		await _wait_physics(blaster.settings.reload_time)
	var full: float = _player.settings.move_speed
	assert_almost_eq(speeds[0], full * _player.settings.reload_move_speed, 0.05)
	assert_almost_eq(speeds[1], full, 0.05)


func test_spare_magazines_add_a_magazine_per_rank() -> void:
	var before: int = _player.spare_magazines
	_player.skills.raise(SPARES)
	_player.skills.raise(SPARES)
	assert_eq(_player.spare_magazines, before + 2)
	var blaster := _player.weapon as RangedWeapon
	assert_eq(blaster.spare_rounds, (before + 2) * blaster.capacity(), "filled right away")


func test_careful_reload_keeps_the_rounds_left() -> void:
	var blaster := _player.weapon as RangedWeapon
	_player.settings.spare_magazines = 1
	_player.skills.raise(SPARES)
	_player.skills.raise(CAREFUL)
	assert_true(blaster.careful)
	var capacity: int = blaster.capacity()
	blaster.rounds = 10
	var spares: int = blaster.spare_rounds
	assert_true(_player.reload())
	assert_eq(blaster.rounds, 10, "keeps them during the reload")
	await _wait_physics(blaster.settings.reload_time + 0.1)
	assert_eq(blaster.rounds, capacity)
	assert_eq(blaster.spare_rounds, spares - (capacity - 10), "only the missing rounds")


func test_reload_throws_the_rest_away_without_careful_reload() -> void:
	var blaster := _player.weapon as RangedWeapon
	assert_false(blaster.careful)
	blaster.rounds = 10
	var spares: int = blaster.spare_rounds
	_player.reload()
	assert_eq(blaster.rounds, 0)
	await _wait_physics(blaster.settings.reload_time + 0.1)
	assert_eq(blaster.spare_rounds, spares - blaster.capacity())


func test_ore_scanner_points_to_the_nearest_node_in_range() -> void:
	var near := _add_node(Vector3(0.0, 0.0, -10.0))
	var other := _add_node(Vector3(30.0, 0.0, 0.0))
	_add_node(Vector3(-60.0, 0.0, 0.0))
	var scanner := _player.get_node("OreScanner") as OreScanner
	await _wait_physics(0.1)
	assert_false(scanner.visible, "not learned")
	_player.skills.raise(SCANNER)
	await _wait_physics(0.1)
	assert_true(scanner.visible)
	assert_eq(scanner.target, near)
	# The arrow's tip points along its -Z: towards the node.
	assert_almost_eq(-scanner.global_basis.z.z, -1.0, 0.01)
	near.place_miner(MINER_SCENE)
	await _wait_physics(0.1)
	assert_eq(scanner.target, near, "also with a miner on it")
	_player.global_position = Vector3(29.0, 0.0, 0.0)
	_player.reset_physics_interpolation()
	await _wait_physics(0.1)
	assert_false(scanner.visible, "close enough to place a miner")


func test_damage_readout_shows_hits_and_adds_up_pellets() -> void:
	var alien := ALIEN_SCENE.instantiate() as Alien
	alien.settings = alien.settings.duplicate() as AlienSettings
	alien.settings.max_health = 1000.0
	alien.position = Vector3(0.0, 0.0, -5.0)
	_arena.add_child(alien)
	await wait_physics_frames(1)
	assert_null(DamageNumber.show_hit(_player, alien, 10.0), "not learned")
	_player.skills.raise(SCANNER)
	_player.skills.raise(READOUT)
	var number: DamageNumber = DamageNumber.show_hit(_player, alien, 10.0)
	assert_not_null(number)
	assert_eq(DamageNumber.show_hit(_player, alien, 5.0), number, "pellets at once add up")
	assert_eq(number.text, "15")
	await _wait_physics(DamageNumber.MERGE_TIME + 0.05)
	var later: DamageNumber = DamageNumber.show_hit(_player, alien, 5.0)
	assert_ne(later, number, "a later hit shows anew")
	await _wait_physics(DamageNumber.LIFETIME + 0.1)
	assert_false(is_instance_valid(later), "gone after its lifetime")
	assert_not_null(DamageNumber.show_hit(_player, alien, 5.0), "a hit after that shows again")
	assert_null(DamageNumber.show_hit(alien, alien, 5.0), "only players' hits")


func test_hits_with_the_hammer_show_their_damage() -> void:
	_player.arsenal.unlock(HAMMER)
	_player.loadout.assign(0, HAMMER)
	_player.skills.raise(SCANNER)
	_player.skills.raise(READOUT)
	var alien := ALIEN_SCENE.instantiate() as Alien
	alien.settings = alien.settings.duplicate() as AlienSettings
	alien.settings.max_health = 1000.0
	alien.position = Vector3(0.0, 0.0, -1.5)
	_arena.add_child(alien)
	await wait_physics_frames(1)
	Input.action_press(&"attack")
	await wait_physics_frames(2)
	Input.action_release(&"attack")
	assert_true(alien.has_meta(DamageNumber.META))
	var number := alien.get_meta(DamageNumber.META) as DamageNumber
	assert_not_null(number)
	assert_eq(number.amount, (_player.weapon as MeleeWeapon).settings.damage)


func _add_node(at: Vector3) -> OreNode:
	var node := ORE_NODE.instantiate() as OreNode
	node.ore_type = CYAN
	node.position = at
	_arena.add_child(node)
	return node


## Waits `seconds` of physics time (physics frames: process time runs ahead on a busy runner).
func _wait_physics(seconds: float) -> void:
	await wait_physics_frames(ceili(seconds * Engine.physics_ticks_per_second))
