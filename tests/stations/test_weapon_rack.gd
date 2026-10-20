extends GutTest
## The weapon racks (the armory's wall, the workbench's rack): rows by origin, for any number.

const HARL: WeaponType = preload("res://game/weapons/types/harl/harl.tres")
const BRASK: WeaponType = preload("res://game/weapons/types/brask/brask.tres")
const DRAY: WeaponType = preload("res://game/weapons/types/dray/dray.tres")


func test_rows_by_origin_for_18_weapons() -> void:
	var arsenal: Arsenal = _arsenal({TOOL = 7, COLONY = 5, PROTOTYPE = 6})
	var rack: WeaponRack = _rack(arsenal)
	assert_eq(rack.get_parts().size(), 18)
	assert_eq(
		rack.get_row_origins(),
		[WeaponType.Origin.COLONY, WeaponType.Origin.TOOL, WeaponType.Origin.PROTOTYPE]
	)
	assert_eq(rack.get_labels().size(), 3, "a name per row")
	assert_eq(rack.get_labels()[1].text, "Converted mining tools")
	var order: Array[WeaponType] = rack.get_order()
	var last_y: float = INF
	var last_x: float = -INF
	for i: int in order.size():
		var part: StationPart = rack.get_part(order[i])
		if i > 0 and order[i].origin != order[i - 1].origin:
			assert_lt(part.position.y, last_y - 0.1, "the next row goes down")
			last_x = -INF
		elif i > 0:
			assert_almost_eq(part.position.y, last_y, 0.001, "same row")
		assert_gt(part.position.x, last_x, "along the row")
		last_y = part.position.y
		last_x = part.position.x
	var tools: Array[WeaponType] = order.filter(
		func(weapon_type: WeaponType) -> bool: return weapon_type.origin == WeaponType.Origin.TOOL
	)
	var listed: Array[WeaponType] = arsenal.weapons.filter(
		func(weapon_type: WeaponType) -> bool: return weapon_type.origin == WeaponType.Origin.TOOL
	)
	assert_eq(tools, listed, "a row keeps the arsenal's order")


func test_empty_origins_get_no_row() -> void:
	var rack: WeaponRack = _rack(_arsenal({TOOL = 2, COLONY = 0, PROTOTYPE = 1}))
	assert_eq(rack.get_row_origins(), [WeaponType.Origin.TOOL, WeaponType.Origin.PROTOTYPE])
	assert_eq(rack.get_labels().size(), 2)
	assert_almost_eq(rack.get_parts()[0].position.y, 0.0, 0.001, "the first row at the top")


func test_panel_covers_every_weapon() -> void:
	var rack := WeaponRack.new()
	rack.weapons = _arsenal({COLONY = 3, TOOL = 7, PROTOTYPE = 1})
	var panel := MeshInstance3D.new()
	panel.mesh = BoxMesh.new()
	rack.add_child(panel)
	rack.panel = panel
	add_child_autofree(rack)
	var box := panel.mesh as BoxMesh
	var aabb := AABB(panel.position - box.size * 0.5, box.size)
	for part: StationPart in rack.get_parts():
		var at := Vector3(part.position.x, part.position.y, panel.position.z)
		assert_true(aabb.has_point(at), "%s on the panel" % part.name)
	for label: Label3D in rack.get_labels():
		var at := Vector3(label.position.x, label.position.y, panel.position.z)
		assert_true(aabb.has_point(at), "%s on the panel" % label.name)


func test_shows_what_a_player_owns() -> void:
	var rack: WeaponRack = _rack(_arsenal({COLONY = 2, TOOL = 0, PROTOTYPE = 0}))
	var player := Player.new()
	var owned: WeaponType = rack.get_order()[0]
	player.arsenal = Arsenal.new()
	player.arsenal.weapons.append(owned)
	player.upgrades = Upgrades.new()
	rack.show_for(player)
	var solid := rack.get_display(owned).find_children("*", "GeometryInstance3D", true, false)
	assert_eq((solid[0] as GeometryInstance3D).transparency, 0.0)
	var other := rack.get_display(rack.get_order()[1])
	var locked := other.find_children("*", "GeometryInstance3D", true, false)
	assert_gt((locked[0] as GeometryInstance3D).transparency, 0.0, "see-through")
	player.free()


func test_workbench_cycles_in_rack_order() -> void:
	var map: Node3D = preload("res://tests/support/test_map.gd").instantiate() as Node3D
	add_child_autofree(map)
	await wait_physics_frames(2)
	var station := map.get_node("Ship/Rooms/Lower/Weapons/UpgradeStation") as WeaponStation
	var rack := station.get_node("Rack") as WeaponRack
	var order: Array[WeaponType] = rack.get_order()
	assert_eq(station.bench_weapon, order[0])
	for i: int in order.size():
		station._cycle(1)
		assert_eq(station.bench_weapon, order[(i + 1) % order.size()])
	assert_eq(rack.get_row_origins().size(), 2, "colony arms and tools so far")


## An arsenal of copies of the three weapons, `counts` per origin (by name), listed mixed.
func _arsenal(counts: Dictionary) -> Arsenal:
	var arsenal := Arsenal.new()
	var sources: Array[WeaponType] = [HARL, BRASK, DRAY]
	var n: int = 0
	for origin_name: String in counts:
		for i: int in counts[origin_name] as int:
			var copy := sources[n % 3].duplicate() as WeaponType
			copy.origin = WeaponType.Origin[origin_name]
			copy.display_name = "W%d" % n
			arsenal.weapons.append(copy)
			n += 1
	return arsenal


func _rack(arsenal: Arsenal) -> WeaponRack:
	var rack := WeaponRack.new()
	rack.weapons = arsenal
	add_child_autofree(rack)
	return rack
