class_name Station
extends WorldMenu
## An object that is the menu (see GAME_DESIGN.md, UI): a workbench, a fitting frame, a miner's
## maintenance pad. A player uses it with `interact` at its `Use` child (an `Interactable`), steps
## to `user_spot`, and their camera frames it (see `WorldMenu`). Its parts (`StationPart`s) are
## selectable:
## - mouse: the cursor points at them (outlined while hovered), a click selects one;
## - gamepad and keyboard: `move_*` and the ui_* directions move the highlight to the nearest part
##   in that direction on screen, `tab_prev`/`tab_next` switch between groups (`_cycle`, e.g. the
##   next weapon on the rack), `interact` and `ui_accept` press the card's main action.
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

## Where the player using it stands, looking along its -Z.
@export var user_spot: Node3D

## The selected part, or null.
var selected: StationPart
## The part under the mouse cursor, or null.
var hovered: StationPart
## The card's menu.
var card_menu: StationCard

## Directions held down right now (a stick sends many events while held: only the first counts).
var _held: Dictionary[Vector2, bool] = {}
var _leader := MeshInstance3D.new()
var _leader_mesh := ImmediateMesh.new()

@onready var card: WorldPanel = $Card
@onready var use_point: Interactable = $Use


func _ready() -> void:
	card_menu = card.content as StationCard
	if card_menu:
		card_menu.station = self
	card.visible = false
	use_point.used.connect(_on_used)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = StationPart.SELECTED_COLOR
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.render_priority = WorldPanel.ON_TOP_PRIORITY
	_leader.mesh = _leader_mesh
	_leader.material_override = material
	_leader.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_leader.top_level = true
	_leader.visible = false
	add_child(_leader, false, Node.INTERNAL_MODE_BACK)


func _process(delta: float) -> void:
	if not user:
		return
	_place_card(1.0 - exp(-CARD_SPEED * delta))


func _input(event: InputEvent) -> void:
	if not user:
		return
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		_point(event as InputEventMouse)
	elif CLOSE_ACTIONS.any(event.is_action_pressed):
		get_viewport().set_input_as_handled()
		close()
	elif event.is_action_pressed(&"tab_prev") or event.is_action_pressed(&"tab_next"):
		get_viewport().set_input_as_handled()
		_cycle(-1 if event.is_action_pressed(&"tab_prev") else 1)
	elif PRESS_ACTIONS.any(event.is_action_pressed):
		get_viewport().set_input_as_handled()
		if card_menu:
			card_menu.press_primary()
	elif _shortcut(event):
		get_viewport().set_input_as_handled()
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


## Moves the highlight to the nearest part in `direction` on screen (up is -Y), if there is one.
func step(direction: Vector2) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if not camera or not selected:
		return
	var from: Vector2 = camera.unproject_position(selected.global_position)
	var best: StationPart = null
	var best_score: float = INF
	for part: StationPart in get_parts():
		if part == selected:
			continue
		var offset: Vector2 = camera.unproject_position(part.global_position) - from
		var along: float = offset.dot(direction)
		if along <= 0.0:
			continue
		# Straight in that direction counts more than off to the side.
		var score: float = along + 2.0 * absf(offset.cross(direction))
		if score < best_score:
			best = part
			best_score = score
	if best:
		select(best)


## Shows the card again for what's selected (e.g. after buying).
func refresh() -> void:
	if card_menu:
		card_menu.show_part(selected)


func get_look_target() -> Vector3:
	if user_spot:
		return user_spot.global_position - user_spot.global_basis.z
	return global_position


## Handles a station's own keys (e.g. the locker's `slot_1`/`slot_2`). Returns whether it did.
func _shortcut(_event: InputEvent) -> bool:
	return false


## Whether `player` may use it (e.g. only their own locker).
func can_use(_player: Player) -> bool:
	return true


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
	use_point.enabled = false
	if user_spot:
		user.global_position = user_spot.global_position
		user.reset_physics_interpolation()
	_held.clear()
	var parts: Array[StationPart] = get_parts()
	select(parts[0] if not parts.is_empty() else null)
	card.visible = true
	card.set_on_top(true)
	_leader.visible = true
	_place_card(1.0)


func _closed() -> void:
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
	var nearest: StationPart = null
	var nearest_distance: float = INF
	for part: StationPart in get_pickable_parts():
		var distance: float = part.distance_on_screen(camera, event.position)
		if distance < nearest_distance:
			nearest = part
			nearest_distance = distance
	_hover(nearest)
	var click := event as InputEventMouseButton
	if click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT and nearest:
		_picked(nearest)


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
	var goal: Vector3 = selected.card_position(camera)
	var view: Basis = camera.global_basis.orthonormalized()
	card.global_transform = Transform3D(view, card.global_position.lerp(goal, weight))
	_draw_leader(view)


## The leader line from the card's edge facing the part to the part, and a dot on the part.
func _draw_leader(view: Basis) -> void:
	_leader_mesh.clear_surfaces()
	if not selected:
		return
	var to: Vector3 = selected.global_position
	var side: float = signf(view.x.dot(to - card.global_position))
	var from: Vector3 = card.global_position + view.x * side * card.size.x * 0.5
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
