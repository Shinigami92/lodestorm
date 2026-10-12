extends GutTest

const ORE_NODE := preload("res://scenes/mining/ore_node.tscn")
const ORE_CYAN := preload("res://scenes/mining/ores/ore_cyan.tres")
const ROCKS := preload("res://assets/rocks/rocks.glb")


func test_mesh_by_part_name() -> void:
	assert_not_null(ModelParts.mesh(ROCKS, &"Boulder_a"))
	assert_null(ModelParts.mesh(ROCKS, &"NoSuchPart"))


## Ore nodes show their type's model variant: one rock base and many crystals spread over the
## deposit (not piled up at its center), all drawn in the ore's glowing material.
func test_ore_node_uses_model_variant() -> void:
	var node := ORE_NODE.instantiate() as OreNode
	node.ore_type = ORE_CYAN
	node.variant = 1
	add_child_autofree(node)
	var crystals: Array[Node] = node.get_node("Crystals").get_children()
	assert_gt(crystals.size(), 5)
	var spots: Array[Vector3] = []
	for crystal: MeshInstance3D in crystals:
		assert_eq(crystal.material_override, ORE_CYAN.get_material())
		if crystal.position not in spots:
			spots.append(crystal.position)
	assert_gt(spots.size(), 1)
	var deposit := node.get_node("Deposit") as MeshInstance3D
	assert_eq(deposit.mesh, ModelParts.mesh(ORE_CYAN.model, &"Base_cyan_b"))


func test_scatter_type_takes_mesh_from_model() -> void:
	var type := ScatterType.new()
	type.model = ROCKS
	type.model_part = &"Rubble_a"
	assert_eq(type.get_mesh(), ModelParts.mesh(ROCKS, &"Rubble_a"))
