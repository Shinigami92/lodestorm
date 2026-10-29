class_name Station
extends WorldMenu
## An object that is the menu (see docs/design/ui.md): a workbench, a fitting frame, a miner's
## maintenance pad. A player uses it with `interact` at its `Use` child (an `Interactable`), steps
## where they stand, and their camera frames it (see `WorldMenu`). Its parts (`StationPart`s) are
## selectable:
## - mouse: the cursor points at them (outlined while hovered), a click selects one;
## - gamepad and keyboard: `move_*` and the ui_* directions move the highlight to the nearest part
##   in that direction on screen (for stations sharing a `room`, among the parts of all of them,
##   handing the user over to the station of the part it lands on), `tab_prev`/`tab_next` switch
##   between groups (`_cycle`, e.g. the next weapon on the rack), `interact` and `ui_accept` press
##   the card's main action, `pause` and `ui_cancel` step back (`_back`) or close.
## The holo card (`Card`, a transparent `WorldPanel` showing a `StationCard`, which keeps to the
## middle of it and only takes the height it needs) floats beside the selected part,
## faces the camera and draws over everything; the mouse uses its buttons like on a screen. An
## amber leader line runs from the card to the selected part, with a dot on the part.

## Actions that move the highlight, and their direction on screen.
const DIRECTIONS: Dictionary[StringName, Vector2] = {
	&"move_forward": Vector2.UP,
	&"move_back": Vector2.DOWN,
	&"move_left": Vector2.LEFT,
	&"move_right": Vector2.RIGHT,
	&"ui_up": Vector2.UP,
	&"ui_down": Vector2.DOWN,
	&"ui_left": Vector2.LEFT,
	&"ui_right": Vector2.RIGHT,
}
const PRESS_ACTIONS: Array[StringName] = [&"interact", &"ui_accept"]
## How fast the card glides to the next part (per s).
const CARD_SPEED: float = 14.0
## Width of the leader line and size of its dot on the part, in m.
const LEADER_WIDTH: float = 0.012
const LEADER_DOT: float = 0.035
## How far to either side of a direction (on screen) the highlight looks for the next part first.
const CONE: float = deg_to_rad(60.0)

## The room it shares with other stations (e.g. `&"cargo_bay"`: the silos, the furnaces and the
## ingot rack): the directions move the highlight across all of them (never into another room).
## Empty: only its own parts.
@export var room: StringName = &""

## The selected part, or null.
var selected: StationPart
## The part under the mouse cursor, or null.
var hovered: StationPart
## The card's menu.
var card_menu: StationCard
## The mission, found in the scene tree when not set: one underway locks the stations that
## change progress or gear (`locks_while_underway`, see `is_locked`).
var mission: Mission:
	get:
		if not is_instance_valid(_mission) and is_inside_tree():
			_mission = get_tree().get_first_node_in_group(Mission.GROUP) as Mission
		return _mission
	set(value):
		_mission = value
## The ship it stands in (the nearest one), found when not set: whose hold, story or shield it
## works with.
var ship: Ship:
	get:
		# Ships join their group when they're ready, after their rooms: looked up until found.
		if not is_instance_valid(_ship) and is_inside_tree():
			_ship = Ship.nearest(get_tree(), global_position)
		return _ship
	set(value):
		_ship = value
## Whether a mission underway locks it (nothing is bought, built, started or swapped then),
## set by the stations that change progress or gear.
var locks_while_underway: bool = false

## Directions held down right now (a stick sends many events while held: only the first counts).
var _held: Dictionary[Vector2, bool] = {}
var _mission: Mission
var _ship: Ship
var _leader: MeshInstance3D
var _leader_mesh := ImmediateMesh.new()

@onready var card: WorldPanel = $Card
## Where players use it; without a `Use` child the station opens itself (e.g. the hold, from its
## silos).
@onready var use_point: Interactable = get_node_or_null(^"Use") as Interactable


func _ready() -> void:
	card_menu = card.content as StationCard
	if card_menu:
		card_menu.station = self
	card.visible = false
	if use_point:
		use_point.used.connect(_on_used)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = StationPart.SELECTED_COLOR
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.render_priority = WorldPanel.ON_TOP_PRIORITY
	_leader = MeshInstance3D.new()
	_leader.mesh = _leader_mesh
	_leader.material_override = material
	_leader.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_leader.top_level = true
	_leader.layers = RenderLayers.EFFECTS
	_leader.visible = false
	add_child(_leader, false, Node.INTERNAL_MODE_BACK)


func _process(delta: float) -> void:
	if not user:
		return
	_place_card(1.0 - exp(-CARD_SPEED * delta))


func _input(event: InputEvent) -> void:
	if not user:
		return
	if _shortcut(event):
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton or event is InputEventMouseMotion:
		_point(event as InputEventMouse)
	elif CLOSE_ACTIONS.any(event.is_action_pressed):
		get_viewport().set_input_as_handled()
		if not _back():
			close()
	elif event.is_action_pressed(&"tab_prev") or event.is_action_pressed(&"tab_next"):
		get_viewport().set_input_as_handled()
		_cycle(-1 if event.is_action_pressed(&"tab_prev") else 1)
	elif PRESS_ACTIONS.any(event.is_action_pressed):
		get_viewport().set_input_as_handled()
		if card_menu:
			card_menu.press_primary()
	else:
		_steer(event)


## The parts the highlight moves between right now, in order (the first is selected on opening).
func get_parts() -> Array[StationPart]:
	var parts: Array[StationPart] = []
	for node: Node in find_children("*", "StationPart", true, false):
		var part := node as StationPart
		if part.is_visible_in_tree():
			parts.append(part)
	return parts


## The parts of every station in its `room` that `player` can use (not one someone else is
## using), for moving the highlight across them; only its own parts outside a room.
func room_parts(player: Player) -> Array[StationPart]:
	if room.is_empty():
		return get_parts()
	var parts: Array[StationPart] = []
	for menu: WorldMenu in get_tree().get_nodes_in_group(GROUP):
		var station := menu as Station
		if not station or station.room != room or not station.is_visible_in_tree():
			continue
		if not station.can_use(player) or (station.user and station.user != player):
			continue
		parts.append_array(station.get_parts())
	return parts


## The station `part` belongs to (its nearest `Station` ancestor), or null.
static func of(part: Node) -> Station:
	var node: Node = part.get_parent() if part else null
	while node and not node is Station:
		node = node.get_parent()
	return node as Station


## Hands the user over to `station` with `part` selected (moving the highlight across a room).
func hand_over(station: Station, part: StationPart) -> void:
	var player: Player = user
	if not player or station == self:
		return
	close()
	station.select(part)
	station.open(player)


## The parts the mouse can point at right now: `get_parts` and maybe more (e.g. the weapons on
## the rack).
func get_pickable_parts() -> Array[StationPart]:
	return get_parts()


## Selects `part` (null: none) and shows it on the card.
func select(part: StationPart) -> void:
	if selected and selected != part:
		selected.set_highlight(
			StationPart.Highlight.HOVERED if selected == hovered else StationPart.Highlight.NONE
		)
	selected = part
	if part:
		part.set_highlight(StationPart.Highlight.SELECTED)
	if card_menu:
		card_menu.show_part(part)


## Moves the highlight to the next part in `direction` on screen (up is -Y), if there is one (see
## `_neighbor`).
func step(direction: Vector2) -> void:
	if not selected:
		return
	var best: StationPart = _neighbor(selected, direction)
	if not best:
		return
	# A part of another station of the room hands the user over; any other is its own (a locker's
	# wall is a node of its own).
	var station: Station = Station.of(best)
	if station and station != self and not room.is_empty() and station.room == room:
		hand_over(station, best)
	else:
		select(best)


## The part the highlight moves to from `part` in `direction` (on screen: up is -Y), or null. By
## default the nearest of `room_parts` in that direction on screen (a part of another station of
## the room hands the user over to it); a station with a grid of parts (the weapon racks) moves
## along it instead.
func _neighbor(part: StationPart, direction: Vector2) -> StationPart:
	return _nearest_on_screen(part, direction, room_parts(user) if user else get_parts())


## The one of `parts` nearest to `part` in `direction` on screen, or null: the nearest within
## `CONE` of the direction (a part close by and a bit to the side beats one straight on but far
## away, like the next row of silos), else the most nearly straight on of the ones that lie that
## way at all.
func _nearest_on_screen(
	part: StationPart, direction: Vector2, parts: Array[StationPart]
) -> StationPart:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if not camera:
		return null
	var from: Vector2 = camera.unproject_position(part.global_position)
	var spread: float = tan(CONE)
	var best: StationPart = null
	var best_score: float = INF
	var fallback: StationPart = null
	var fallback_score: float = INF
	for candidate: StationPart in parts:
		if candidate == part:
			continue
		var offset: Vector2 = camera.unproject_position(candidate.global_position) - from
		var along: float = offset.dot(direction)
		if along <= 0.0:
			continue
		var aside: float = absf(offset.cross(direction))
		var score: float = along + 0.5 * aside
		if aside <= along * spread and score < best_score:
			best = candidate
			best_score = score
		# Straight in that direction counts more than off to the side.
		var wide: float = along + 2.0 * aside
		if wide < fallback_score:
			fallback = candidate
			fallback_score = wide
	return best if best else fallback


## Shows or hides the card and its leader line (e.g. while the bed's player falls asleep).
func show_card(shown: bool) -> void:
	card.visible = shown
	_leader.visible = shown


## Shows the card again for what's selected (e.g. after buying).
func refresh() -> void:
	if card_menu:
		card_menu.show_part(selected)


## The player using it looks at the selected part, else at it.
func get_look_target() -> Vector3:
	return selected.global_position if selected else global_position


## Steps back one level (e.g. the navigator from a planet to the system) instead of closing.
## Returns whether it did.
func _back() -> bool:
	return false


## Handles a station's own keys (e.g. the locker's `slot_1`/`slot_2`). Returns whether it did.
func _shortcut(_event: InputEvent) -> bool:
	return false


## The `number`th player (1: the first, the one playing solo), or null: whose locker or bed it is.
## The order players joined in, until co-op gives them stable seats.
static func nth_player(tree: SceneTree, number: int) -> Player:
	var players: Array[Node] = tree.get_nodes_in_group(Player.GROUP)
	return players[number - 1] as Player if number >= 1 and number <= players.size() else null


## Whether nothing can be done right now: while a mission is underway, for the stations it locks
## (`locks_while_underway`).
func is_locked() -> bool:
	return locks_while_underway and mission != null and mission.is_underway()


## The player whose state it shows (their hold, batch, fleet): the one using it, else the one
## the ship's cutaway follows (the camera's), else the first local player.
func viewer() -> Player:
	if user:
		return user
	return ship.get_viewing_player() if ship else Player.first_local(get_tree())


## Whether `player` may use it (e.g. only their own locker).
func can_use(_player: Player) -> bool:
	return true


## Whether `item` (an upgrade, a skill) is bought here; finished jobs chime at the station that
## sells them (see `ProgressClock`).
func sells(_item: Resource) -> bool:
	return false


## Switches to the previous (-1) or next (1) group of parts; nothing by default.
func _cycle(_step: int) -> void:
	pass


## Moves the highlight for a direction action; a held stick moves it once.
func _steer(event: InputEvent) -> void:
	for action: StringName in DIRECTIONS:
		if not InputMap.has_action(action):
			continue
		var pressed: bool = event.is_action_pressed(action, true)
		if not pressed and not event.is_action_released(action):
			continue
		get_viewport().set_input_as_handled()
		var direction: Vector2 = DIRECTIONS[action]
		var repeated: bool = _held.get(direction, false) and not event.is_echo()
		_held[direction] = pressed
		if pressed and not repeated:
			step(direction)
		return


## Called when the mouse clicks `part`; selects it by default.
func _picked(part: StationPart) -> void:
	select(part)


func _opened() -> void:
	if use_point:
		use_point.enabled = false
	_held.clear()
	# A subclass may have picked what to start with already.
	if not selected:
		var parts: Array[StationPart] = get_parts()
		select(parts[0] if not parts.is_empty() else null)
	card.visible = true
	card.set_on_top(true)
	_leader.visible = true
	_place_card(1.0)


func _closed() -> void:
	if use_point:
		use_point.enabled = true
	card.visible = false
	_leader.visible = false
	card.set_on_top(false)
	_hover(null)
	select(null)


func _on_used(player: Player) -> void:
	if can_use(player):
		open(player)


func _point(event: InputEventMouse) -> void:
	get_viewport().set_input_as_handled()
	if card.point(event):
		_hover(null)
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if not camera:
		return
	var nearest: StationPart = _part_at(camera, event.position)
	_hover(nearest)
	var click := event as InputEventMouseButton
	if click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT and nearest:
		_picked(nearest)


## The part the mouse cursor at `screen_position` points at, or null: by default the pickable part
## nearest to it on screen, within its `pick_radius`.
func _part_at(camera: Camera3D, screen_position: Vector2) -> StationPart:
	var nearest: StationPart = null
	var nearest_distance: float = INF
	for part: StationPart in get_pickable_parts():
		var distance: float = part.distance_on_screen(camera, screen_position)
		if distance < nearest_distance:
			nearest = part
			nearest_distance = distance
	return nearest


## Where the card floats: by default beside the selected part (its `card_offset`).
func _card_position(camera: Camera3D) -> Vector3:
	return selected.card_position(camera)


## How big the card is (1: its `size`), e.g. scaled with a zoom so it keeps its size on screen.
func _card_scale() -> float:
	return 1.0


func _hover(part: StationPart) -> void:
	if hovered == part:
		return
	if hovered and hovered != selected and is_instance_valid(hovered):
		hovered.set_highlight(StationPart.Highlight.NONE)
	hovered = part
	if part and part != selected:
		part.set_highlight(StationPart.Highlight.HOVERED)


## Moves the card towards the selected part (`weight` 1: all the way) and turns it to face the
## camera.
func _place_card(weight: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if not camera or not selected:
		return
	var goal: Vector3 = _card_position(camera)
	var view: Basis = camera.global_basis.orthonormalized()
	card.global_transform = Transform3D(
		view * Basis.from_scale(Vector3.ONE * _card_scale()),
		card.global_position.lerp(goal, weight)
	)
	_draw_leader(view)


## The leader line from the card's edge facing the part to the part (its side edge, or the top or
## bottom edge when the part is above or below it), and a dot on the part.
func _draw_leader(view: Basis) -> void:
	_leader_mesh.clear_surfaces()
	if not selected:
		return
	var to: Vector3 = selected.global_position
	var offset: Vector3 = to - card.global_position
	var half: Vector2 = card.size * 0.5 * _card_scale()
	var from: Vector3 = card.global_position
	if absf(view.x.dot(offset)) > half.x:
		from += view.x * signf(view.x.dot(offset)) * half.x
	else:
		from += view.y * signf(view.y.dot(offset)) * half.y
	_leader_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var across: Vector3 = view.z.cross(to - from).normalized() * LEADER_WIDTH * 0.5
	_quad(from - across, from + across, to + across, to - across)
	var dot_x: Vector3 = view.x * LEADER_DOT
	var dot_y: Vector3 = view.y * LEADER_DOT
	_quad(to - dot_x, to + dot_y, to + dot_x, to - dot_y)
	_leader_mesh.surface_end()


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for corner: Vector3 in [a, b, c, a, c, d]:
		_leader_mesh.surface_add_vertex(corner)
