class_name PausePanel
extends WorldPanel
## The pause panel (see docs/design/ui.md): `pause` with no menu open shows a holo card
## (`PauseCard`) beside the player's suit ring, facing the camera, with "Resume", "Settings" and
## "Quit"; `pause` again (or "Resume") puts it away. Like the other 3D menus, the camera moves in
## while it's open, framing the player, the whole ring (its marks, pointers and the ship's
## countdown) and the card, and the player stands still meanwhile.
## Solo, the game stops while it's open (`pausing`: aliens, the timer, the storm), and it opens by
## itself when the window loses focus (`pause_on_focus_loss`). In co-op the game goes on, and the
## card says so. "Quit" ends the game like the bed: aboard right away, during a run after asking
## (the run is lost).

## How far the card floats beside the suit ring (towards the camera's right, beyond its marks,
## pointers and the ship's countdown; m), centered on the feet on screen, so it covers neither.
const SIDE_GAP: float = 0.25
## How high the suit reaches above the feet (the helmet, the backpack; m), kept on screen.
const BODY_TOP: float = 2.0
## Share of the view's height kept free on each side of what it frames.
const MARGIN: float = 0.05
## Steps that settle the card's size and the view (each depends on the other).
const FIT_STEPS: int = 6

## Whether it opens by itself when the window loses focus, solo (off for windowed probes).
static var pause_on_focus_loss: bool = true

## Whether "Quit" quits the game (off in tests).
@export var quits: bool = true
## How much the camera would see framing the card alone (visible height in m): the card grows
## with the view (`view_height`, which frames the ring too), so it keeps this size on screen and
## its text stays readable.
@export var card_view_height: float = 2.6

## The player whose panel it is.
var holder: Player
## Whether it stopped the game (solo) while it's open.
var pausing: bool = false
## Whether "Quit" was chosen (the game is about to quit).
var quitting: bool = false

var _focus := Node3D.new()


func _ready() -> void:
	super()
	_focus.name = "Focus"
	add_child(_focus)
	_focus.top_level = true
	view_focus = _focus
	view_height = card_view_height
	get_card().panel = self


func _exit_tree() -> void:
	# Never leaves the game stopped (e.g. the map reloads).
	if pausing:
		pausing = false
		get_tree().paused = false


func _process(delta: float) -> void:
	super(delta)
	if not user:
		return
	if holder.fallen:
		close()
		return
	# Someone joined: the game goes on.
	if pausing and not SaveGame.is_solo(get_tree()):
		_set_pausing(false)
	_place()


func _input(event: InputEvent) -> void:
	if not holder:
		return
	if user:
		super(event)
	elif event.is_action_pressed(&"pause") and can_open():
		get_viewport().set_input_as_handled()
		open(holder)


func _notification(what: int) -> void:
	if (
		what == NOTIFICATION_APPLICATION_FOCUS_OUT
		and pause_on_focus_loss
		and not user
		and can_open()
		and SaveGame.is_solo(get_tree())
	):
		open(holder)


## Whether its player can open it now: only the local one, not while using another menu, nor while
## down or dead.
func can_open() -> bool:
	return (
		holder != null
		and holder.local
		and holder.is_inside_tree()
		and holder.menu == null
		and not holder.fallen
	)


## Whether the card shows.
func is_shown() -> bool:
	return user != null


## The card.
func get_card() -> PauseCard:
	return content as PauseCard


func get_look_target() -> Vector3:
	return global_position


## Whether quitting now loses the run underway.
func loses_run() -> bool:
	var mission := get_tree().get_first_node_in_group(Mission.GROUP) as Mission
	return mission != null and mission.is_underway()


## "Quit": aboard it saves and quits right away (`ScreenFade.quit_game`); during a run it asks
## first (the run is lost), and `confirmed` answers yes. Returns whether it's quitting.
func quit(confirmed: bool = false) -> bool:
	if quitting or not user:
		return false
	if loses_run() and not confirmed:
		get_card().show_page(PauseCard.Page.QUIT)
		return false
	quitting = true
	content.visible = false
	ScreenFade.quit_game(self, quits)
	return true


func _opened() -> void:
	visible = true
	super()
	_set_pausing(SaveGame.is_solo(get_tree()))
	get_card().show_page(PauseCard.Page.MAIN)
	_place()


func _closed() -> void:
	super()
	visible = false
	_set_pausing(false)


func _set_pausing(paused: bool) -> void:
	if pausing == paused:
		return
	pausing = paused
	get_tree().paused = paused
	if get_card():
		get_card().show_page(get_card().page)


## Keeps the card beside the player's suit ring, facing the camera, and frames the player, the ring
## and the card: the card grows with the view, so it keeps its size on screen.
func _place() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if not camera or not holder:
		return
	var view: Basis = camera.global_basis.orthonormalized()
	var feet: Vector3 = holder.global_position
	var shown: PackedVector3Array = _ring_outline()
	shown.append(feet + Vector3.UP * BODY_TOP)
	var ring_right: float = 0.0
	for spot: Vector3 in shown:
		ring_right = maxf(ring_right, view.x.dot(spot - feet))
	var height: float = view_height
	for step: int in FIT_STEPS:
		var grow: float = height / card_view_height
		var half: Vector2 = size * 0.5 * grow
		var center: Vector3 = feet + view.x * (ring_right + SIDE_GAP + half.x)
		global_transform = Transform3D(view.scaled(Vector3.ONE * grow), center)
		var points: PackedVector3Array = shown.duplicate()
		for side: Vector2 in [
			Vector2(-1.0, -1.0), Vector2(1.0, -1.0), Vector2(-1.0, 1.0), Vector2.ONE
		]:
			points.append(center + view.x * side.x * half.x + view.y * side.y * half.y)
		height = _frame(camera, view, points)
	view_height = height


## What the card mustn't cover and the view keeps on screen: the suit ring (its marks and pointers)
## and the ship's countdown beside it.
func _ring_outline() -> PackedVector3Array:
	var points := PackedVector3Array([holder.global_position])
	var ring := holder.get_node_or_null(^"SuitRing") as SuitRing
	if ring:
		points.append_array(ring.outline())
	var ship := holder.get_node_or_null(^"ShipPointer") as ShipPointer
	if ship:
		points.append_array(ship.countdown_corners())
	return points


## Moves the camera's focus to the middle of `points` (global) and returns the view height (m at
## the focus) that keeps them all on screen, `MARGIN` inside its edges.
func _frame(camera: Camera3D, view: Basis, points: PackedVector3Array) -> float:
	var origin: Vector3 = holder.global_position
	var low := Vector2.INF
	var high := -Vector2.INF
	var local := PackedVector3Array()
	for spot: Vector3 in points:
		var at: Vector3 = view.transposed() * (spot - origin)
		local.append(at)
		low = low.min(Vector2(at.x, at.y))
		high = high.max(Vector2(at.x, at.y))
	var middle: Vector2 = (low + high) * 0.5
	_focus.global_position = origin + view.x * middle.x + view.y * middle.y
	var screen: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = screen.x / maxf(screen.y, 1.0)
	var usable: float = 1.0 - 2.0 * MARGIN
	var orthogonal: bool = camera.projection == Camera3D.PROJECTION_ORTHOGONAL
	var tangent: float = tan(deg_to_rad(camera.fov) * 0.5)
	# Perspective: the camera stands `view_height / (2 * tangent)` from the focus, and what's
	# nearer to it (+Z) looks bigger.
	var needed: float = 0.0
	for at: Vector3 in local:
		var off: float = maxf(absf(at.y - middle.y), absf(at.x - middle.x) / aspect) / usable
		needed = maxf(needed, off if orthogonal else off / tangent + at.z)
	return 2.0 * needed if orthogonal else 2.0 * needed * tangent
