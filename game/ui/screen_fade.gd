class_name ScreenFade
extends CanvasLayer
## A full-screen fade to black: a transition, not a HUD (e.g. falling asleep before the game
## quits). It runs on while the game is paused.

## How long falling asleep takes (the fade to black before quitting), in s.
const QUIT_TIME: float = 1.2

var _black := ColorRect.new()


func _init() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_black.color = Color(0.0, 0.0, 0.0, 0.0)
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_black)


## Fades the screen to black over `time` s, from a new fade under `parent`. Returns its tween
## (for what follows once it's black).
static func to_black(parent: Node, time: float) -> Tween:
	var fade := ScreenFade.new()
	parent.add_child(fade)
	var tween: Tween = fade.create_tween()
	tween.tween_property(fade._black, ^"color:a", 1.0, time)
	return tween


## Quits the game from `from` (a bed, the pause panel) like falling asleep: saves the progress one
## last time (not while a run is underway: what changes during one is only saved once it's over,
## so quitting loses it), fades to black, runs `then` and quits to the desktop (unless `quits` is
## off, in tests). Returns the fade's tween.
static func quit_game(from: Node, quits: bool, then: Callable = Callable()) -> Tween:
	var tree: SceneTree = from.get_tree()
	var mission := tree.get_first_node_in_group(Mission.GROUP) as Mission
	if not mission or not mission.is_underway():
		var save_game := tree.get_first_node_in_group(SaveGame.GROUP) as SaveGame
		if save_game:
			save_game.save_progress()
	var tween: Tween = to_black(from, QUIT_TIME)
	if then.is_valid():
		tween.tween_callback(then)
	if quits:
		tween.tween_callback(tree.quit)
	return tween
