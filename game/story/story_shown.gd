class_name StoryShown
extends Node3D
## Scenery that shows once a story `flag` is set (the nearest ship's `Story`), or, with `until`,
## until then: e.g. Dace's stall at Ostra with its shutter down once he's aboard, Hollis' old miner
## in the cargo bay. Hidden, it's switched off too, so its colliders don't block anyone.

## The story flag it follows (e.g. `crew.gunsmith.joined`).
@export var flag: StringName
## Whether it shows until `flag` is set instead of once it is.
@export var until: bool = false

var _story: Story


func _ready() -> void:
	# The ship joins its group after its rooms are ready: its story is found a frame later.
	_watch.call_deferred()


func _watch() -> void:
	var ship: Ship = Ship.nearest(get_tree(), global_position)
	_story = ship.story if ship else Story.new()
	_story.changed.connect(_update)
	_update()


func _update() -> void:
	visible = _story.is_set(flag) != until
	process_mode = PROCESS_MODE_INHERIT if visible else PROCESS_MODE_DISABLED
