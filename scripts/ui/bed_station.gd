class_name BedStation
extends Station
## A player's bed in their cabin, where they quit the game ("Sleep", see GAME_DESIGN.md, UI): the
## bed is its part, its card offers "Sleep". Sleeping saves the progress one last time (not during
## a run: what changes then is only saved once it's over, so the run underway is lost, and the card
## says so), fades the screen to black (the camera stays on the bed) and quits to the desktop
## (there's no main menu yet). Bed `number` belongs to the `number`th player; nobody else can use
## it.

## How long falling asleep takes (the fade to black), in s.
const FADE_TIME: float = 1.2

## Whose bed it is: the `number`th player (1: the first, the one playing solo).
@export_range(1, 4) var number: int = 1
## The bed it is (outlined while selected).
@export var bed: Node3D
## Whether sleeping quits the game (off in tests).
@export var quits: bool = true

## Whether its player fell asleep (the game is about to quit).
var asleep: bool = false
## The mission that makes sleeping lose the run underway; found in the scene tree when not set.
var mission: Mission

@onready var _part: StationPart = $Part


func _ready() -> void:
	super()
	_part.outline = bed


func _process(delta: float) -> void:
	super(delta)
	if not mission:
		mission = get_tree().get_first_node_in_group(Mission.GROUP) as Mission
	if user:
		refresh()


func can_use(player: Player) -> bool:
	return not asleep and player == Station.nth_player(get_tree(), number)


## Whether sleeping now loses the run underway.
func loses_run() -> bool:
	return mission != null and mission.is_underway()


## Saves (unless a run is underway), fades to black and quits. Returns whether it fell asleep.
func sleep() -> bool:
	if asleep or not user:
		return false
	asleep = true
	if not loses_run():
		var save_game := get_tree().get_first_node_in_group(SaveGame.GROUP) as SaveGame
		if save_game:
			save_game.save_progress()
	show_card(false)
	var fade := CanvasLayer.new()
	fade.layer = 100
	var black := ColorRect.new()
	black.color = Color(0.0, 0.0, 0.0, 0.0)
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.add_child(black)
	add_child(fade)
	var tween: Tween = create_tween()
	tween.tween_property(black, ^"color:a", 1.0, FADE_TIME)
	tween.tween_callback(close)
	if quits:
		tween.tween_callback(get_tree().quit)
	return true
