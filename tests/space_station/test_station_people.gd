extends GutTest
## Waypost Ostra's people: the named NPCs at their places with their topics, the bartender's
## rumors following the heat shield, and the ambient colonists walking, sitting and saying their
## remarks.

const TEST_MAP := preload("res://tests/support/map_fixture.gd")
const NAMED: Dictionary[String, NpcProfile] = {
	"Kade": preload("res://game/npcs/ostra/depot_master.tres"),
	"Selin": preload("res://game/npcs/ostra/councillor.tres"),
	"Nell": preload("res://game/npcs/ostra/bartender.tres"),
	"Rook": preload("res://game/npcs/ostra/rival_captain.tres"),
}
## The room each of them is at home in (see `NpcRoutine.get_own_room`).
const ROOMS: Dictionary[String, StringName] = {
	"Kade": &"Depot", "Selin": &"Council", "Nell": &"Bar", "Rook": &"Bar"
}

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


func after_each() -> void:
	# What the game frees a frame late (a swapped model, weapon or view) isn't counted as an orphan.
	await wait_process_frames(1)


func test_named_npcs_stand_at_their_places() -> void:
	for who: String in NAMED:
		var npc := _station.get_node("People/" + who) as Npc
		assert_eq(npc.profile, NAMED[who], who)
		assert_eq(npc.ship, _ship, who + " tells the docked ship's story")
		assert_eq(npc.routine.get_own_room(), ROOMS[who], who + "'s own room")
		assert_false(npc.routine.is_away(), who)
	# Facing the room: the depot master towards the camera, the bartender across the counter.
	assert_almost_eq(_facing("Kade"), Vector3.BACK, Vector3.ONE * 0.01)
	assert_almost_eq(_facing("Nell"), Vector3.RIGHT, Vector3.ONE * 0.01)
	assert_almost_eq(_facing("Rook"), Vector3.LEFT, Vector3.ONE * 0.01)
	# The bartender is talked to across the counter.
	var nell := _station.get_node("People/Nell") as Npc
	var front: Vector3 = nell.global_position + _station.global_basis * Vector3(1.4, 0.0, 1.5)
	assert_eq(Interactable.nearest(get_tree(), front), nell.use_point)
	var away: Vector3 = front + _station.global_basis.x * 1.5
	assert_null(Interactable.nearest(get_tree(), away), "close to the counter only")


## While the station glides in, its people stay at their places on it: they never walk over the
## docked ship's navigation.
func test_named_npcs_keep_their_places_while_docking() -> void:
	_ship.navigation.bake()
	for i: int in 300:
		if _ship.navigation.is_baked():
			break
		await wait_physics_frames(1)
	assert_true(_ship.navigation.is_baked())
	var places: Dictionary[String, Transform3D] = {}
	for who: String in NAMED:
		places[who] = (_station.get_node("People/" + who) as Node3D).transform
	_ship.flight.phase = ShipFlight.Phase.DOCKING
	_ship.flight.phase_time = 0.0
	await wait_physics_frames(120)
	assert_gt(_station.position.distance_to(_ship.position), 50.0, "still gliding in")
	_ship.flight.skip()
	await wait_physics_frames(5)
	for who: String in NAMED:
		var npc := _station.get_node("People/" + who) as Npc
		assert_almost_eq(npc.position, places[who].origin, Vector3.ONE * 0.01, who)
		assert_false(npc.body.is_walking(), who)


func test_every_topic_is_theirs_and_follows_the_greeting() -> void:
	for profile: NpcProfile in NAMED.values():
		var dialogue: Dialogue = profile.dialogue
		assert_not_null(dialogue.greeting, profile.id)
		var topics: Array[Topic] = dialogue.topics.duplicate()
		topics.append(dialogue.greeting)
		for topic: Topic in topics:
			assert_true(Story.is_valid_flag(topic.id), topic.id)
			assert_true(String(topic.id).begins_with(profile.id + "."), topic.id)
			assert_false(topic.lines.is_empty(), topic.id)
			if topic != dialogue.greeting:
				assert_has(topic.requires, dialogue.greeting.id, topic.id)


## Every planet and moon with regions gets a rumor topic, one line per region naming it, so the
## bartender grows with the star system.
func test_the_bartender_knows_every_region() -> void:
	var by_body: Dictionary[StringName, Topic] = {}
	for topic: Topic in NAMED["Nell"].dialogue.topics:
		if not topic.requires_body.is_empty():
			by_body[topic.requires_body] = topic
	for body: CelestialBody in _voyage.settings.system.bodies:
		if body.regions.is_empty():
			assert_false(by_body.has(body.id), "%s has no regions to talk about" % body.id)
			continue
		var topic: Topic = by_body.get(body.id)
		assert_not_null(topic, "a rumor topic about " + body.id)
		if not topic:
			continue
		assert_eq(topic.title, body.display_name)
		assert_eq(topic.lines.size(), body.regions.size(), body.id)
		for i: int in mini(topic.lines.size(), body.regions.size()):
			var region: String = body.regions[i].display_name
			assert_string_contains(topic.lines[i], region)


func test_the_bartender_only_talks_about_bodies_in_reach() -> void:
	var nell := _station.get_node("People/Nell") as Npc
	_ship.story.set_flag(&"bartender.greeting")
	var ids: Array[StringName] = _choice_ids(nell)
	assert_has(ids, &"bartender.torvane")
	assert_has(ids, &"bartender.lisk")
	assert_does_not_have(ids, &"bartender.vehra", "out of reach")
	_ship.heat_shield.restore(2, false, {})
	assert_has(_choice_ids(nell), &"bartender.vehra", "the next plate opens it")


## With every body in reach, the bartender's list is longer than the card: it scrolls, keeping the
## framed entry in view.
func test_a_long_topic_list_scrolls() -> void:
	var nell := _station.get_node("People/Nell") as Npc
	_ship.story.set_flag(&"bartender.greeting")
	_ship.heat_shield.restore(_ship.heat_shield.max_mk(), false, {})
	_player.global_position = nell.use_point.global_position
	nell.open(_player)
	var card := nell.card_menu as TalkCard
	var count: int = nell.get_choices().size() + 1
	assert_gt(count, TalkCard.MAX_ROWS)
	await wait_process_frames(2)
	assert_true(card.is_row_in_view(0))
	assert_false(card.is_row_in_view(count - 1))
	nell.set_choice(count - 1)
	await wait_process_frames(2)
	assert_true(card.is_row_in_view(count - 1), "Goodbye scrolled into view")
	assert_false(card.is_row_in_view(0))
	nell.close()


func test_colonists_show_their_role_only() -> void:
	var mechanic := _station.get_node("People/Mechanic") as Colonist
	assert_eq(mechanic.body.get_plate_text(), "Mechanic")
	assert_true(mechanic.route.is_empty(), "stands at the stall")


## Every colonist has a profile of their own, and no two say the same.
func test_every_colonist_says_their_own_remarks() -> void:
	var said: Dictionary[String, String] = {}
	var profiles: Array[NpcProfile] = []
	for person: Node in _station.get_node("People").get_children():
		var colonist := person as Colonist
		if not colonist:
			continue
		assert_does_not_have(profiles, colonist.profile, colonist.name + " has their own profile")
		profiles.append(colonist.profile)
		assert_gte(colonist.profile.remarks.size(), 4, colonist.name)
		for remark: String in colonist.profile.remarks:
			assert_false(
				said.has(remark), "%s and %s: %s" % [said.get(remark), colonist.name, remark]
			)
			said[remark] = colonist.name


func test_walkers_walk_their_route_and_wait_for_players() -> void:
	var walker := _station.get_node("People/Courier") as Colonist
	_player.global_position = walker.global_position + Vector3(0.0, 0.0, 20.0)
	var start: Vector3 = walker.position
	await wait_physics_frames(30)
	assert_true(walker.is_walking())
	assert_gt(walker.position.x, start.x + 0.3, "towards its first waypoint")
	# A player close by: it stops and turns to them.
	_player.global_position = walker.global_position + walker.global_basis.z * 2.5
	await wait_physics_frames(2)
	var held: Vector3 = walker.position
	await wait_physics_frames(20)
	assert_false(walker.is_walking())
	assert_almost_eq(walker.position, held, Vector3.ONE * 0.001)
	_player.global_position = walker.global_position + Vector3(0.0, 0.0, 20.0)
	await wait_physics_frames(5)
	assert_true(walker.is_walking(), "walks on once the player is gone")


func test_waypoints_loop_with_a_stop() -> void:
	var loader := _station.get_node("People/Loader") as Colonist
	_player.global_position = loader.global_position + Vector3(0.0, 0.0, 40.0)
	loader.position = loader.route[0] - Vector3(0.01, 0.0, 0.0)
	await wait_physics_frames(2)
	assert_eq(loader.next, 1, "on to the next waypoint")
	assert_false(loader.is_walking(), "a stop first")
	await wait_physics_frames(ceili(Colonist.STOP_TIME * Engine.physics_ticks_per_second) + 2)
	assert_true(loader.is_walking())


func test_a_colonist_remarks_while_a_player_stays_close() -> void:
	var gardener := _station.get_node("People/Gardener") as Colonist
	var remarks: Array[String] = gardener.profile.remarks
	_player.global_position = gardener.global_position + Vector3(0.0, 0.0, 10.0)
	await wait_physics_frames(2)
	assert_eq(gardener.get_remark(), "")
	_player.global_position = gardener.global_position + Vector3(0.0, 0.0, 1.5)
	await wait_physics_frames(2)
	assert_eq(gardener.get_remark(), remarks[0])
	await wait_physics_frames(600)
	assert_eq(gardener.get_remark(), remarks[0], "stays while the player does")
	_player.global_position = gardener.global_position + Vector3(0.0, 0.0, 2.3)
	await wait_physics_frames(2)
	assert_eq(gardener.get_remark(), remarks[0], "a step back doesn't end it")
	_player.global_position = gardener.global_position + Vector3(0.0, 0.0, 10.0)
	await wait_physics_frames(2)
	assert_eq(gardener.get_remark(), "", "ends once the player has walked off")
	_player.global_position = gardener.global_position + Vector3(0.0, 0.0, 1.5)
	await wait_physics_frames(2)
	assert_eq(gardener.get_remark(), remarks[1], "the next one after coming back")


## Some sit for good: on a gallery bench looking out, two facing each other in a booth.
func test_seated_colonists_sit_at_their_seats() -> void:
	var facing: Dictionary[String, Vector3] = {
		"HaulerPilot": Vector3.FORWARD,
		"WaterTechnician": Vector3.BACK,
		"Metalworker": Vector3.FORWARD,
	}
	_player.global_position = _station.global_position + Vector3(0.0, 0.0, 200.0)
	await wait_physics_frames(2)
	for who: String in facing:
		var colonist := _station.get_node("People/" + who) as Colonist
		assert_true(colonist.is_sitting(), who)
		assert_eq(colonist.body.get_sit_amount(), 1.0, who + " already sits when the station loads")
		assert_false(colonist.is_walking(), who)
		var way: Vector3 = _station.global_basis.inverse() * colonist.global_basis.z
		assert_almost_eq(way.normalized(), facing[who], Vector3.ONE * 0.01, who)
		var head: float = colonist.body.get_head_position().y - colonist.global_position.y
		assert_lt(head, colonist.body.head_height - 0.3, who + "'s head is lower")
		assert_gt(head, 1.0, who + "'s head is above the seat")


## A seated colonist stays seated and facing ahead when a player comes close, and remarks as usual.
func test_a_seated_colonist_remarks_without_getting_up() -> void:
	var pilot := _station.get_node("People/HaulerPilot") as Colonist
	var basis: Basis = pilot.body.global_basis
	_player.global_position = pilot.global_position + pilot.global_basis.x * 1.5
	await wait_physics_frames(30)
	assert_true(pilot.is_sitting())
	assert_almost_eq(pilot.body.global_basis.z, basis.z, Vector3.ONE * 0.01, "doesn't turn")
	assert_eq(pilot.get_remark(), pilot.profile.remarks[0])
	# Straight above the (lower) head on screen.
	var up: Vector3 = pilot.get_viewport().get_camera_3d().global_basis.y.normalized()
	var above: Vector3 = pilot.bubble.global_position - pilot.body.get_head_position()
	assert_almost_eq(above.normalized(), up, Vector3.ONE * 0.01, "the bubble above the lower head")


## A walker sits down at its seat stop, facing the seat's way, gets up after a while and walks on.
func test_a_walker_sits_at_its_seat_stop_and_walks_on() -> void:
	var teacher := _station.get_node("People/Teacher") as Colonist
	assert_gte(teacher.seat_stop, 0, "the teacher has a seat stop")
	teacher.sit_time = 1.0
	_player.global_position = teacher.global_position + Vector3(0.0, 0.0, 40.0)
	teacher.next = teacher.seat_stop
	teacher.position = teacher.route[teacher.seat_stop] - Vector3(0.01, 0.0, 0.0)
	await wait_physics_frames(2)
	assert_true(teacher.is_sitting(), "sits down")
	assert_eq(teacher.next, (teacher.seat_stop + 1) % teacher.route.size())
	assert_false(teacher.is_walking())
	await wait_physics_frames(50)
	var way: Vector3 = _station.global_basis.inverse() * teacher.global_basis.z
	var seat_way := Vector3(
		sin(deg_to_rad(teacher.seat_yaw)), 0.0, cos(deg_to_rad(teacher.seat_yaw))
	)
	assert_almost_eq(way.normalized(), seat_way, Vector3.ONE * 0.05, "turned to the seat's way")
	assert_gt(teacher.body.get_sit_amount(), 0.9)
	await wait_physics_frames(30)
	assert_false(teacher.is_sitting(), "gets up after a while")
	assert_false(teacher.is_walking(), "not while still getting up")
	var animator := teacher.body.get_node("Animator") as NpcAnimator
	var stand_up: int = ceili(animator.sit_blend_time * Engine.physics_ticks_per_second)
	await wait_physics_frames(stand_up + 10)
	assert_true(teacher.is_walking(), "walks on once up")
	assert_eq(teacher.body.get_sit_amount(), 0.0)


## Where an NPC faces, in the station's axes.
func _facing(who: String) -> Vector3:
	var npc := _station.get_node("People/" + who) as Npc
	return (_station.global_basis.inverse() * npc.global_basis.z).normalized()


func _choice_ids(npc: Npc) -> Array[StringName]:
	var ids: Array[StringName] = []
	for topic: Topic in npc.get_choices(_player):
		ids.append(topic.id)
	return ids
