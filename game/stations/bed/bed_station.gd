class_name BedStation
extends Station
## A player's bed in their cabin, where they quit the game ("Sleep", see GAME_DESIGN.md, UI): the
## bed is its part, its card offers "Sleep". Sleeping saves the progress one last time (not during
## a run: what changes then is only saved once it's over, so the run underway is lost, and the card
## says so), fades the screen to black (the camera stays on the bed) and quits to the desktop, the
## same as "Quit" in the pause panel (`ScreenFade.quit_game`). Bed `number` belongs to the
## `number`th player; nobody else can use it.

## Whose bed it is: the `number`th player (1: the first, the one playing solo).
@export_range(1, 4) var number: int = 1
## The bed it is (outlined while selected).
@export var bed: Node3D
## Whether sleeping quits the game (off in tests).
@export var quits: bool = true

## Whether its player fell asleep (the game is about to quit).
var asleep: bool = false

@onready var _part: StationPart = $Part


func _ready() -> void:
	super()
	_part.outline = bed


func _process(delta: float) -> void:
	super(delta)
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
	show_card(false)
	ScreenFade.quit_game(self, quits, close)
	return true
