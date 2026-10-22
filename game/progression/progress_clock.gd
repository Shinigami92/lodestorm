class_name ProgressClock
extends Node
## Lets every player's upgrade levels, skill ranks and miner builds under way take effect once done
## (see `Upgrades.update`, `Skills.update`, `MinerFleet.update`), checked every second (`TICK`) on
## the wall clock while no mission is underway, so one finishing during a run waits until everyone
## is back aboard. For a local player a soft chime plays at the station selling what finished. The
## ship has one.

## Seconds between checks.
const TICK: float = 1.0
const DONE_SOUND: Sound = preload("res://assets/audio/sfx/stations/job_done.tres")

## The mission whose runs hold finished jobs back; found in the scene tree when not set.
var mission: Mission

var _since_tick: float = 0.0


func _process(delta: float) -> void:
	_since_tick += delta
	if _since_tick < TICK:
		return
	_since_tick = 0.0
	if not mission:
		mission = get_tree().get_first_node_in_group(Mission.GROUP) as Mission
	if mission and mission.is_underway():
		return
	tick(Time.get_unix_time_from_system())


## Lets every job of every player done by `now` (Unix seconds) take effect.
func tick(now: float) -> void:
	for player: Player in get_tree().get_nodes_in_group(Player.GROUP):
		var done: Array[Resource] = []
		done.append_array(player.upgrades.update(now))
		done.append_array(player.skills.update(now))
		done.append_array(player.fleet.update(now))
		if player.local:
			for item: Resource in done:
				chime(item)


## Plays the chime at the station selling `item` (an upgrade, a skill or a crafted miner), or
## plainly without one.
func chime(item: Resource) -> void:
	for node: Node in get_tree().get_nodes_in_group(WorldMenu.GROUP):
		var station := node as Station
		if station and station.sells(item):
			Sfx.play_at(DONE_SOUND, station.global_position)
			return
	Sfx.play_ui(DONE_SOUND)
