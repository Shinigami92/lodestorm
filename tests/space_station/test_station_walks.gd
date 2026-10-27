extends GutTest
## Waypost Ostra's people walking (`NpcRoutine` on the station's `DeckNavigation`): in their own
## room until their greeting is heard, then now and then elsewhere; Nell at a booth, used there.

const TEST_MAP := preload("res://tests/support/map_fixture.gd")

var _map: Node3D
var _player: Player
var _voyage: Voyage
var _ship: Ship
var _station: SpaceStation


func before_each() -> void:
	SaveGame.directory = ""
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	_voyage = _map.get_node("Voyage") as Voyage
	_ship = _map.get_node("Ship") as Ship
	await wait_physics_frames(2)
	var ostra: CelestialBody = _voyage.settings.system.body_by_id(&"ostra")
	_voyage.select(_voyage.offer_for_station(ostra))
	_voyage.skip_flight()
	await wait_physics_frames(2)
	_station = _voyage.location as SpaceStation


func test_the_station_has_its_own_navigation() -> void:
	var navigation: DeckNavigation = _station.navigation
	assert_not_null(navigation)
	assert_ne(navigation.map, _ship.navigation.map, "not the ship's")
	assert_eq(navigation.floors, [0.0] as Array[float], "one deck")
	navigation.bake()
	await _baked(navigation)
	var nell := _people("Nell")
	var booth := _people("NellBooth")
	var path: PackedVector3Array = navigation.find_path(nell.global_position, booth.global_position)
	assert_gt(path.size(), 2, "around the counter's end")
	assert_lt(path[path.size() - 1].distance_to(booth.global_position), 1.0, "to the booth")
	var selin := _people("Selin")
	var gallery := _people("SelinGallery")
	assert_gt(navigation.find_path(selin.global_position, gallery.global_position).size(), 2)


func test_they_leave_their_room_only_after_their_greeting() -> void:
	var selin := _people("Selin") as Npc
	var own: StringName = selin.routine.get_own_room()
	assert_eq(own, &"Council")
	for i: int in 40:
		selin.routine.move_on()
		var spot: WorkSpot = selin.routine.get_work_spot()
		if spot:
			assert_eq(_station.room_plan.room_at(spot.global_position), own, "before the greeting")
	selin.get_story().set_flag(selin.profile.dialogue.greeting.id)
	var rooms: Dictionary[StringName, bool] = {}
	for i: int in 60:
		selin.routine.move_on()
		var spot: WorkSpot = selin.routine.get_work_spot()
		if spot:
			rooms[_station.room_plan.room_at(spot.global_position)] = true
	assert_true(rooms.has(&"Gallery") or rooms.has(&"Concourse"), "now and then elsewhere")


func test_nell_serves_a_booth_and_is_talked_to_there() -> void:
	var nell := _people("Nell") as Npc
	var booth := _people("NellBooth") as WorkSpot
	var across: Transform3D = nell.use_point.transform
	assert_gt(nell.use_point.footprint.x, 0.0, "across her counter at first")
	for i: int in 50:
		nell.routine.move_on()
		if nell.routine.get_work_spot() == booth:
			break
	assert_eq(nell.routine.get_work_spot(), booth)
	await _until(func() -> bool: return nell.body.is_walking(), 30.0)
	assert_true(nell.body.is_walking(), "she walks there")
	await _until(func() -> bool: return not nell.routine.is_underway(), 60.0)
	var at: Vector3 = nell.global_position
	assert_lt(Vector2(at.x - booth.global_position.x, at.z - booth.global_position.z).length(), 0.1)
	assert_eq(nell.routine.get_room(), &"Bar")
	assert_false(nell.routine.is_away(), "the booths are in her bar")
	assert_eq(nell.use_point.footprint, Vector2.ZERO, "used at her feet there")
	assert_almost_eq(nell.use_point.global_position, nell.global_position, Vector3.ONE * 0.01)
	_player.global_position = nell.global_position + Vector3(-1.2, 0.0, 0.0)
	_player.reset_physics_interpolation()
	await wait_physics_frames(2)
	assert_eq(Interactable.nearest(get_tree(), _player.global_position), nell.use_point)
	_player.global_position = _ship.global_position
	_player.reset_physics_interpolation()
	nell.routine.move_on()
	while nell.routine.get_work_spot() == booth:
		nell.routine.move_on()
	await _until(func() -> bool: return nell.routine.is_underway(), 5.0)
	await _until(func() -> bool: return not nell.routine.is_underway(), 60.0)
	if not nell.routine.get_work_spot():
		assert_eq(nell.use_point.transform, across, "across her counter again")


func _people(who: String) -> Node3D:
	return _station.get_node("People/" + who) as Node3D


func _baked(navigation: DeckNavigation) -> void:
	for i: int in 300:
		if navigation.is_baked():
			break
		await wait_physics_frames(1)
	assert_true(navigation.is_baked(), "baked")
	await wait_physics_frames(2)  # the map takes the mesh on the next sync


func _until(done: Callable, seconds: float) -> void:
	for i: int in int(seconds * Engine.physics_ticks_per_second):
		if done.call():
			return
		await wait_physics_frames(1)
