class_name Mission
extends Node
## The mission loop around the ship. The ramp starts closed; the ramp button inside the ship resets
## the outside world (`location`), resets the timer and lowers the ramp (later it also locks the
## selected mission). The mission starts when the first player steps out; the timer then counts
## down from `settings.duration`, and at zero the storm hits (`time_up`). It's over (`returned`)
## once every player is back aboard, in time or during the storm; the ramp goes up and the button
## starts the next run. With player death (M2), dead players won't have to be aboard, and if
## nobody is left the mission is lost.

## Emitted when the ramp button starts a new run: outside world and timer are reset.
signal opened
## Emitted once per run when the first player steps out of the ship.
signal started
## Emitted once per run when the timer runs out.
signal time_up
## Emitted once per run when every player is back aboard; the run is over.
signal returned

enum State { CLOSED, OPEN, RUNNING, STORM, RETURNED }

@export var settings: MissionSettings
## The ship players start from and return to; it shows the mission time.
@export var ship: Ship
## The outside world; replaced by a fresh instance of its scene for every run.
@export var location: Node3D

var state: State = State.CLOSED
## Seconds until the storm hits, 0 afterwards.
var time_left: float


func _ready() -> void:
	time_left = settings.duration
	ship.mission = self
	ship.player_left.connect(_on_player_left)
	ship.ramp_button.used.connect(_on_ramp_button_used)


func _physics_process(delta: float) -> void:
	ship.ramp_button.enabled = state in [State.CLOSED, State.OPEN, State.RETURNED]
	if state != State.RUNNING and state != State.STORM:
		return
	if state == State.RUNNING:
		time_left = maxf(time_left - delta, 0.0)
		if time_left == 0.0:
			state = State.STORM
			time_up.emit()
	if _everyone_aboard():
		state = State.RETURNED
		ship.ramp_open = false
		returned.emit()


## Replaces the outside world with a fresh instance of its scene.
func reset_location() -> void:
	var parent: Node = location.get_parent()
	var index: int = location.get_index()
	var fresh: Node3D = (load(location.scene_file_path) as PackedScene).instantiate() as Node3D
	fresh.name = location.name
	fresh.transform = location.transform
	parent.remove_child(location)
	location.queue_free()
	parent.add_child(fresh)
	parent.move_child(fresh, index)
	location = fresh


func _everyone_aboard() -> bool:
	var players: Array[Node] = get_tree().get_nodes_in_group(Player.GROUP)
	if players.is_empty():
		return false
	for player: Player in players:
		if not ship.is_aboard(player):
			return false
	return true


func _on_ramp_button_used(_player: Player) -> void:
	match state:
		State.CLOSED, State.RETURNED:
			reset_location()
			time_left = settings.duration
			state = State.OPEN
			ship.ramp_open = true
			opened.emit()
		State.OPEN:
			state = State.CLOSED
			ship.ramp_open = false


func _on_player_left(_player: Player) -> void:
	if state == State.OPEN:
		state = State.RUNNING
		started.emit()
