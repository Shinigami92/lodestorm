extends GutTest

const TEST_MAP := preload("res://tests/support/map_fixture.gd")

var _map: Node3D
var _mission: Mission
var _voyage: Voyage
var _table: HoloTable
var _content: Node3D


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_mission = _map.get_node("Mission") as Mission
	_voyage = _map.get_node("Voyage") as Voyage
	_table = _map.get_node("Ship/Rooms/Upper/Bridge/HoloTable") as HoloTable
	_content = _table.get_node("Hologram/Content")
	await wait_physics_frames(2)


func after_each() -> void:
	# What the game frees a frame late (a swapped model, weapon or view) isn't counted as an orphan.
	await wait_process_frames(1)


func test_shows_mission_location() -> void:
	var meshes: int = _voyage.location.find_children("*", "MeshInstance3D", true, false).size()
	assert_gt(_content.get_child_count() * 2, meshes)
	var hologram: Node = _table.get_node("Hologram")
	var parts: Array[Node] = hologram.find_children("*", "VisualInstance3D", true, false)
	assert_gt(parts.size(), 0)
	for part: VisualInstance3D in parts:
		assert_eq(part.layers, RenderLayers.EFFECTS, "decals (the aim reticle) leave it out")


func test_hologram_fits_above_table() -> void:
	var to_table: Transform3D = _table.global_transform.affine_inverse()
	var hologram_y: float = (_table.get_node("Hologram") as Node3D).position.y
	for part: MeshInstance3D in _content.get_children():
		var box: AABB = to_table * part.global_transform * part.mesh.get_aabb()
		for i: int in 8:
			var corner: Vector3 = box.get_endpoint(i)
			assert_lt(Vector2(corner.x, corner.z).length(), _table.radius * 1.5, part.name)
			assert_gt(corner.y, hologram_y - 0.01, part.name)


func test_ship_stands_out() -> void:
	var landmarks: int = 0
	for part: MeshInstance3D in _content.get_children():
		var material := part.material_override as ShaderMaterial
		if material.get_shader_parameter(&"color") == HoloTable.LANDMARK_COLOR:
			landmarks += 1
	assert_gt(landmarks, 0)
	assert_lt(landmarks, _content.get_child_count())


func test_shows_fresh_location_of_next_run() -> void:
	var before: Node = _content.get_child(0)
	_voyage.reset_location()
	assert_ne(_content.get_child(0), before)
	assert_gt(_content.get_child_count(), 0)
