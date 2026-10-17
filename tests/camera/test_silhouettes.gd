extends GutTest
## Players, aliens, miners and nearby ore show as silhouettes behind cliffs (an overlay in their
## color, and their materials mark where they're visible).

const ALIEN: PackedScene = preload("res://game/aliens/alien.tscn")
const MINER: PackedScene = preload("res://game/mining/miner.tscn")
const ORE_NODE: PackedScene = preload("res://game/mining/ore_node.tscn")
const PLAYER: PackedScene = preload("res://game/player/player.tscn")
const KYRITE: OreType = preload("res://game/ores/types/ore_kyrite.tres")


func test_aliens_show_red_behind_cliffs() -> void:
	var alien := ALIEN.instantiate() as Alien
	add_child_autofree(alien)
	var creature := alien.find_child("Creature", true, false) as GeometryInstance3D
	_assert_silhouette(creature.material_overlay, OccludedSilhouette.ALIEN_COLOR)
	_assert_marks_visible(creature)


func test_miners_show_behind_cliffs() -> void:
	var miner := MINER.instantiate() as Miner
	add_child_autofree(miner)
	var frames: Array[Node] = miner.find_children("Frame*", "MeshInstance3D", true, false)
	assert_gt(frames.size(), 0)
	for frame: GeometryInstance3D in frames:
		_assert_silhouette(frame.material_overlay, OccludedSilhouette.MINER_COLOR)


## Ore shows behind cliffs only close to a player, so finding it stays exploring.
func test_ore_shows_behind_cliffs_near_a_player() -> void:
	var node := ORE_NODE.instantiate() as OreNode
	node.ore_type = KYRITE
	add_child_autofree(node)
	var player := PLAYER.instantiate() as Player
	add_child_autofree(player)
	player.global_position = Vector3(OreNode.SILHOUETTE_RANGE + 10.0, 0.0, 0.0)
	await wait_seconds(OreNode.SILHOUETTE_CHECK * 2.0)
	assert_false(node.is_silhouette_shown(), "far away")
	player.global_position = Vector3(OreNode.SILHOUETTE_RANGE - 5.0, 0.0, 0.0)
	await wait_seconds(OreNode.SILHOUETTE_CHECK * 2.0)
	assert_true(node.is_silhouette_shown(), "close")
	var crystal := node.find_child("Crystals").get_child(0) as GeometryInstance3D
	var color: Color = KYRITE.color
	color.a = OccludedSilhouette.ORE_ALPHA
	_assert_silhouette(crystal.material_overlay, color)


func _assert_silhouette(material: Material, color: Color) -> void:
	var silhouette := material as ShaderMaterial
	assert_not_null(silhouette)
	if silhouette:
		assert_eq(silhouette.shader, OccludedSilhouette.SHADER)
		var actual: Color = silhouette.get_shader_parameter(&"color")
		assert_eq(actual, color)


func _assert_marks_visible(mesh: GeometryInstance3D) -> void:
	var instance := mesh as MeshInstance3D
	var material := instance.mesh.surface_get_material(0) as BaseMaterial3D
	if instance.material_override:
		material = instance.material_override as BaseMaterial3D
	assert_eq(material.stencil_reference, OccludedSilhouette.STENCIL_VISIBLE)
	assert_eq(material.stencil_flags, BaseMaterial3D.STENCIL_FLAG_WRITE)
