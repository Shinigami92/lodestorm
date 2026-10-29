class_name MinerRadar
extends Node3D
## The miner radar (a skill): while the local `holder` is outside, an arrow on its suit ring's edge
## points to each of its own miners that needs it: amber when full or on a dry node, blinking red
## while it's under attack (hit within `ATTACK_TIME`) or broken. Working ones don't show, nor ones
## within `min_distance` (in view anyway). Without the skill, players keep an eye on their miners
## themselves.

## Seconds after a hit that a miner counts as under attack.
const ATTACK_TIME: float = 3.0
## The arrows' length beyond the ring and half their width (m; smaller than the ore scanner's).
const ARROW := Vector2(0.66, 0.22)
const ALPHA: float = 0.85
## Pointer priorities (see `RingPointer.priority`): under attack before the ore scanner, full or
## dry after it.
const ATTACKED_PRIORITY: int = 2
const WAITING_PRIORITY: int = 4

## How close (m) a miner may be before its arrow hides. TBD (playtest).
@export var min_distance: float = 10.0

## The player whose miners it watches.
var holder: Player

var _pointers: Array[RingPointer] = []


func _ready() -> void:
	for index: int in MinerFleet.SLOTS:
		var pointer := RingPointer.new()
		pointer.name = "Pointer%d" % (index + 1)
		pointer.arrow = ARROW
		pointer.visible = false
		add_child(pointer)
		_pointers.append(pointer)


## The arrows shown (for tests and probes).
func shown() -> Array[RingPointer]:
	var visible_ones: Array[RingPointer] = []
	for pointer: RingPointer in _pointers:
		if pointer.visible:
			visible_ones.append(pointer)
	return visible_ones


func _physics_process(_delta: float) -> void:
	var count: int = 0
	if _active():
		var blink_on: bool = fmod(Time.get_ticks_msec() * 0.001 * Miner.BLINK_RATE, 1.0) < 0.5
		for node: Node in get_tree().get_nodes_in_group(Miner.GROUP):
			var miner := node as Miner
			if count >= _pointers.size() or miner.owned_by != holder or not miner.is_standing():
				continue
			var offset: Vector3 = miner.global_position - global_position
			offset.y = 0.0
			if offset.length() <= min_distance:
				continue
			var attacked: bool = miner.broken or miner.since_hit <= ATTACK_TIME
			if not attacked and not miner.is_full() and not miner.is_dry():
				continue
			var pointer: RingPointer = _pointers[count]
			# Runs after the player turned this tick, so the arrow keeps pointing at the miner.
			pointer.point_along(offset)
			pointer.priority = ATTACKED_PRIORITY if attacked else WAITING_PRIORITY
			pointer.color = Color(Miner.COLOR_DRY, ALPHA)
			if attacked:
				pointer.color = Color(Miner.COLOR_ALARM, ALPHA if blink_on else ALPHA * 0.35)
			pointer.visible = true
			count += 1
	for index: int in range(count, _pointers.size()):
		_pointers[index].visible = false


func _active() -> bool:
	if not holder.local or holder.fallen or not holder.skills.has(Skill.Effect.MINER_RADAR):
		return false
	var ship: Ship = Ship.nearest(get_tree(), global_position)
	return not ship or not ship.is_aboard(holder)
