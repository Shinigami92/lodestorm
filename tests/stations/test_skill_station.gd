extends GutTest
## The skill graph in the skills room (see GAME_DESIGN.md, Upgrade stations).

const TEST_MAP := preload("res://tests/support/test_map.gd")
const DASH: Skill = preload("res://game/progression/skills/tree/dash.tres")
const RELOAD_ON_THE_MOVE: Skill = preload(
	"res://game/progression/skills/tree/reload_on_the_move.tres"
)
const SUIT: Skill = preload("res://game/progression/skills/tree/reinforced_suit.tres")
const SPARES: Skill = preload("res://game/progression/skills/tree/spare_magazines.tres")
const SCANNER: Skill = preload("res://game/progression/skills/tree/ore_scanner.tres")
const KYRITE: OreType = preload("res://game/ores/types/ore_kyrite.tres")
const OLVANE: OreType = preload("res://game/ores/types/ore_olvane.tres")
const VYREL: OreType = preload("res://game/ores/types/ore_vyrel.tres")

var _map: Node3D
var _player: Player
var _ship: Ship
var _station: SkillStation


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	_ship = _map.get_node("Ship") as Ship
	_station = _ship.get_node("Rooms/Lower/Skills/SkillGraph") as SkillStation
	await wait_physics_frames(2)


func test_graph_shows_every_skill_and_opens_on_the_first() -> void:
	assert_eq(_station.get_parts().size(), _station.tree.get_skills().size())
	await _open()
	assert_eq(_player.menu, _station)
	assert_eq(_station.selected.item, DASH, "the first cluster's root")
	assert_eq((_station.card_menu as SkillCard).skill, DASH)


func test_learning_pays_from_the_hold() -> void:
	await _open()
	assert_false(_station.can_learn(DASH), "the hold is empty")
	assert_false(_station.learn(DASH))
	_player.hold.add(KYRITE, 1000.0)
	_send(&"interact")
	assert_true(_player.skills.is_running(DASH))
	assert_eq(_player.hold.amount(KYRITE), 1000.0 - DASH.ranks[0].cost[KYRITE])
	assert_false(_station.can_learn(DASH), "under way")
	_player.skills.finish_all()
	assert_eq(_player.skills.rank(DASH), 1)
	assert_false(_station.can_learn(DASH), "single rank: learned")
	assert_eq(_station.user, _player, "learning doesn't close it")


func test_a_skill_opens_once_the_one_before_is_learned() -> void:
	_player.hold.add(KYRITE, 5000.0)
	_player.hold.add(OLVANE, 5000.0)
	_player.hold.add(VYREL, 5000.0)
	await _open()
	assert_false(_station.can_learn(RELOAD_ON_THE_MOVE))
	assert_true(_station.learn(DASH))
	assert_false(_station.can_learn(RELOAD_ON_THE_MOVE), "dash is still under way")
	_player.skills.finish_all()
	assert_true(_station.learn(RELOAD_ON_THE_MOVE))


func test_ranked_skills_learn_rank_by_rank() -> void:
	_player.hold.add(KYRITE, 5000.0)
	_player.hold.add(OLVANE, 5000.0)
	await _open()
	assert_true(_station.learn(SUIT))
	assert_false(_station.learn(SUIT), "one rank at a time")
	_player.skills.finish_all()
	assert_true(_station.learn(SUIT))
	_player.skills.finish_all()
	assert_eq(_player.skills.rank(SUIT), 2)
	assert_false(_station.can_learn(SUIT), "rank 3 needs pallin")


func test_nothing_can_be_learned_during_a_mission() -> void:
	_player.hold.add(KYRITE, 1000.0)
	await _open()
	TEST_MAP.pick_mission(_map)
	_ship.ramp_button.use(_player)
	await wait_process_frames(2)
	assert_true(_station.is_locked())
	assert_false(_station.learn(DASH))
	assert_eq(_player.hold.amount(KYRITE), 1000.0, "nothing paid")
	assert_true((_station.card_menu as SkillCard).get_learn_button().disabled)


func test_directions_and_tabs_move_through_the_graph() -> void:
	await _open()
	_send(&"move_right")
	assert_eq(_station.selected.item, SUIT, "the cluster to the right")
	_send(&"tab_next")
	assert_eq(_station.selected.item, SPARES, "the next cluster's root")
	assert_eq(_station.pan, _station.tree.cluster_of(SPARES).center, "centered on it")
	_send(&"tab_prev")
	_send(&"tab_prev")
	assert_eq(_station.selected.item, DASH)
	_send(&"tab_prev")
	assert_eq(_station.selected.item, SCANNER, "wraps around")


func test_zoom_frames_closer_and_scales_the_card() -> void:
	await _open()
	var full: float = _station.view_height
	_station.set_zoom(0.5)
	assert_almost_eq(_station.view_height, full * 0.5, 0.001)
	_station.set_zoom(0.1)
	assert_eq(_station.zoom, SkillStation.MIN_ZOOM, "clamped")
	await wait_process_frames(2)
	assert_almost_eq(_station.card.global_basis.x.length(), SkillStation.MIN_ZOOM, 0.001)
	_station.close()
	assert_eq(_station.zoom, 1.0, "the next one starts with the whole graph")
	assert_almost_eq(_station.view_height, full, 0.001)


## The mouse can point at every other skill while one is selected: the card never covers them
## (and with the whole graph in view, it stays in view).
func test_card_covers_no_other_skill() -> void:
	await _open()
	for zoom: float in [1.0, SkillStation.MIN_ZOOM]:
		_station.set_zoom(zoom)
		for selected: StationPart in _station.get_parts():
			var size: Vector2 = _station.card.size * zoom
			var card := Rect2(_station.card_spot(selected) - size * 0.5, size)
			if zoom == 1.0:
				var skill_name: String = (selected.item as Skill).display_name
				assert_true(_station.view_rect().encloses(card), "%s: card in view" % skill_name)
			for other: StationPart in _station.get_parts():
				if other == selected:
					continue
				var point := Vector2(other.position.x, other.position.y)
				var label: String = (
					"zoom %s: %s covers %s"
					% [
						zoom,
						(selected.item as Skill).display_name,
						(other.item as Skill).display_name
					]
				)
				assert_false(card.grow(SkillStation.NODE_SIZE * 0.5).has_point(point), label)


func test_panning_stays_on_the_graph() -> void:
	await _open()
	_station.set_pan(Vector2(100.0, -100.0))
	var bounds: Rect2 = _station.graph_bounds()
	assert_eq(_station.pan, Vector2(bounds.end.x, bounds.position.y))


func test_mouse_drag_pans_and_wheel_zooms() -> void:
	await _open()
	_station.set_zoom(0.5)
	var camera: Camera3D = _station.get_viewport().get_camera_3d()
	var graph := _station.get_node("Graph") as Node3D
	var center: Vector2 = camera.unproject_position(graph.global_position)
	var before: Vector2 = _station.pan
	_mouse_button(MOUSE_BUTTON_RIGHT, true, center)
	_mouse_move(center + Vector2(80.0, 0.0), Vector2(80.0, 0.0))
	_mouse_button(MOUSE_BUTTON_RIGHT, false, center + Vector2(80.0, 0.0))
	assert_lt(_station.pan.x, before.x, "dragging right moves the view left")
	var zoom: float = _station.zoom
	_mouse_button(MOUSE_BUTTON_WHEEL_UP, true, center)
	assert_lt(_station.zoom, zoom)


func test_debug_overlay_teaches_every_skill() -> void:
	var overlay: CanvasLayer = get_tree().root.get_node("DebugOverlay") as CanvasLayer
	overlay.call(&"learn_skills")
	for skill: Skill in _station.tree.get_skills():
		assert_eq(_player.skills.rank(skill), skill.max_rank(), skill.display_name)


func _open() -> void:
	_station.open(_player)
	await wait_process_frames(2)


func _send(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		get_viewport().push_input(event, true)


func _mouse_button(button: MouseButton, pressed: bool, at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = at
	get_viewport().push_input(event, true)


func _mouse_move(at: Vector2, relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_RIGHT
	get_viewport().push_input(event, true)
