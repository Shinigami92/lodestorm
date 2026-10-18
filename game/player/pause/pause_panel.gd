class_name PausePanel
extends WorldPanel
## The pause panel (see GAME_DESIGN.md, UI): `pause` with no menu open shows a holo card
## (`PauseCard`) beside the player, facing the camera, with "Resume", "Settings" and "Quit";
## `pause` again (or "Resume") puts it away. Like the other 3D menus, the camera moves in to frame
## the player and the card while it's open, and the player stands still meanwhile.
## Solo, the game stops while it's open (`pausing`: aliens, the timer, the storm), and it opens by
## itself when the window loses focus (`pause_on_focus_loss`). In co-op the game goes on, and the
## card says so. "Quit" ends the game like the bed: aboard right away, during a run after asking
## (the run is lost).

## Where the card's bottom middle floats: beside the player (towards the camera's right), a little
## above the feet, so it never covers them.
const SIDE_OFFSET: float = 0.9
const HEIGHT: float = 0.35

## Whether it opens by itself when the window loses focus, solo (off for windowed probes).
static var pause_on_focus_loss: bool = true

## Whether "Quit" quits the game (off in tests).
@export var quits: bool = true

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
	if holder.dead:
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


## Whether its player can open it now: not while using another menu, nor while dead.
func can_open() -> bool:
	return holder != null and holder.is_inside_tree() and holder.menu == null and not holder.dead


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


## Keeps the card beside the player, facing the camera (its bottom `HEIGHT` above the feet), and
## the camera's focus between the two.
func _place() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if not camera or not holder:
		return
	var view: Basis = camera.global_basis.orthonormalized()
	var flat_right: Vector3 = Vector3(view.x.x, 0.0, view.x.z).normalized()
	var anchor: Vector3 = holder.global_position + Vector3.UP * HEIGHT
	anchor += flat_right * (SIDE_OFFSET + size.x * 0.5)
	var center: Vector3 = anchor + view.y * (size.y * 0.5)
	global_transform = Transform3D(view, center)
	_focus.global_position = holder.global_position.lerp(center, 0.5) + Vector3.UP * 0.3
