extends GutTest
## Finding a quest's step (`QuestMark`, `QuestPointer`): what the tracked quest still needs in a
## location carries a mark, lit (an amber beam) while its quest is tracked and out once it's done;
## the location hologram shows the lit ones, the suit ring points to the nearest, and the regions
## with an active step are known for the navigator's diamonds.

const LOCATION: PackedScene = preload("res://game/locations/generated_location.tscn")
const PLAYER_SCENE: PackedScene = preload("res://game/player/player.tscn")
const HOLO_TABLE: PackedScene = preload("res://game/ship/holo_table.tscn")
const DUST: LocationBiome = preload("res://game/locations/biomes/dust.tres")
const ITEMS := preload("res://tests/quests/test_quest_items.gd")

var _log: QuestLog
var _quest: Quest


func before_each() -> void:
	_quest = ITEMS.make_quest()
	_log = QuestLog.new()
	_log.catalog = QuestCatalog.new()
	_log.catalog.quests = [_quest]
	_log.accept(_quest, [])


## The fragments' crates and the case carry a mark, lit while the quest is tracked; an opened
## crate's goes out for good.
func test_marks_light_while_tracked_and_go_out_when_done() -> void:
	var location: GeneratedLocation = _location()
	var marks: Array[QuestMark] = _marks(location)
	var crates: int = 0
	for crate: Crate in location.find_children("*", "Crate", true, false):
		if crate.content is BlueprintFragment:
			crates += 1
	assert_eq(marks.size(), crates + 1, "a fragment's crates and the case")
	assert_eq(_log.tracked, _quest.id, "accepting it tracked it")
	for mark: QuestMark in marks:
		assert_true(mark.is_lit())
	await wait_seconds(QuestMark.CHECK * 2.0)
	assert_true(marks[0].get_beam().visible, "its beam")
	_log.tracked = &""
	assert_false(marks[0].is_lit(), "not while another quest is tracked")
	_log.tracked = _quest.id
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	var crate := marks[0].get_parent() as Crate
	assert_not_null(crate, "the first mark is on a crate")
	if crate:
		crate.use(player)
		assert_false(marks[0].is_lit(), "opened")
		assert_true(marks[1].is_lit() if marks.size() > 1 else true, "the others stay")


## The suit ring's arrow points to the nearest lit mark, hides close to it and with none lit.
func test_the_pointer_points_to_the_nearest_lit_mark() -> void:
	var location: GeneratedLocation = _location()
	var marks: Array[QuestMark] = _marks(location)
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	var pointer := player.get_node(^"QuestPointer") as QuestPointer
	assert_eq(pointer.priority, 1, "after the ship's")
	var far: Vector3 = marks[0].global_position + Vector3(40.0, 0.0, 0.0)
	player.global_position = far
	await wait_physics_frames(2)
	var nearest: QuestMark = marks[0]
	for mark: QuestMark in marks:
		if _flat(mark.global_position - far) < _flat(nearest.global_position - far):
			nearest = mark
	assert_eq(pointer.target, nearest)
	assert_true(pointer.visible)
	var to_mark: Vector3 = nearest.global_position - pointer.global_position
	assert_almost_eq(pointer.heading().angle_to(Vector3(to_mark.x, 0.0, to_mark.z)), 0.0, 0.01)
	_log.tracked = &""
	await wait_physics_frames(2)
	assert_false(pointer.visible, "none lit")
	_log.tracked = _quest.id
	player.global_position = nearest.global_position + Vector3(2.0, 0.0, 0.0)
	await wait_physics_frames(2)
	assert_false(pointer.visible, "close to it")


## The location hologram shows a quest beam per mark (crates too), while it's lit.
func test_the_hologram_shows_the_lit_marks() -> void:
	var location: GeneratedLocation = _location()
	var table := HOLO_TABLE.instantiate() as HoloTable
	add_child_autofree(table)
	table.show_location(location)
	var beams: Dictionary[MeshInstance3D, QuestMark] = table.get_quest_markers()
	assert_eq(beams.size(), _marks(location).size())
	for beam: MeshInstance3D in beams:
		assert_true(beam.visible)
		var material := beam.material_override as ShaderMaterial
		var color: Color = material.get_shader_parameter(&"color")
		assert_eq(color, QuestMark.COLOR, "amber")
	for marker: MeshInstance3D in table.get_markers():
		assert_false(beams.has(marker), "not among the ore beams")
	for part: MeshInstance3D in table.get_node(^"Hologram/Content").get_children():
		assert_ne(part.mesh, _marks(location)[0].get_beam().mesh, "the beam itself isn't copied")
	_log.tracked = &""
	await wait_seconds(QuestMark.CHECK * 2.0)
	for beam: MeshInstance3D in beams:
		assert_false(beam.visible, "another quest tracked")


## The regions with a goal of an active step not done yet, filled for the tracked quest's.
func test_regions_with_an_active_step() -> void:
	assert_eq(QuestVisit.regions(_log), {ITEMS.REGION: true} as Dictionary[StringName, bool])
	_log.tracked = &""
	assert_eq(QuestVisit.regions(_log), {ITEMS.REGION: false} as Dictionary[StringName, bool])
	var step: QuestStep = _quest.steps[0]
	_log.add_progress(_quest, step, 0, 3.0)
	_log.add_progress(_quest, step, 1, 1.0)
	assert_true(QuestVisit.regions(_log).is_empty(), "every goal there done")


func _location() -> GeneratedLocation:
	var location := LOCATION.instantiate() as GeneratedLocation
	location.world_seed = 5
	location.biome = DUST
	location.area_count = 6
	location.quest_visit = QuestVisit.new(_log, ITEMS.REGION)
	add_child_autofree(location)
	return location


func _marks(location: Node) -> Array[QuestMark]:
	var marks: Array[QuestMark] = []
	marks.assign(location.find_children("*", "QuestMark", true, false))
	return marks


static func _flat(offset: Vector3) -> float:
	return Vector2(offset.x, offset.z).length()
