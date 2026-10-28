class_name Lift
extends Node3D
## A platform between the ship's decks. A player stepping on it sends it to the other deck after
## `departure_delay`; players who rode along have to step off before it leaves again. A player
## waiting at the gate on the other deck calls it over while nobody rides it. Gates close the shaft
## on every deck the platform isn't standing at, so nobody walks under it or falls down the shaft.
## The crew ride it too (`NpcWalker`): they call it to their deck while nobody rides it (`call_to`),
## hold it while they step on (`boarding`: players on it wait for them) and send it off once they
## stand on it (`send`).

enum Deck { LOWER, UPPER }

## How far the platform rides up, from the lower to the upper deck, in m.
@export var travel_height: float = 4.5
## In m/s. TBD (playtest).
@export var speed: float = 2.25
## Seconds a new rider stands on the platform before it leaves. TBD (playtest).
@export var departure_delay: float = 0.6

## The deck the platform stands at, or is riding to.
var deck: Deck = Deck.LOWER
## Whether the platform is riding.
var moving: bool = false
## Whether a crew member is stepping on: it doesn't leave until they send it.
var boarding: bool = false

## Riders who came along on the last ride; they don't send it off again until they step off.
var _arrived: Array[Player] = []
## Seconds a new rider has been waiting.
var _waited: float = 0.0

@onready var _platform: AnimatableBody3D = $Platform
@onready var _riders: Area3D = $Platform/Riders
@onready var _gates: Array[StaticBody3D] = [$LowerGate, $UpperGate]
@onready var _calls: Array[Area3D] = [$LowerCall, $UpperCall]


func _ready() -> void:
	_platform.position.y = _height(deck)
	_update_gates()


func _physics_process(delta: float) -> void:
	if moving:
		var target: float = _height(deck)
		_platform.position.y = move_toward(_platform.position.y, target, speed * delta)
		if _platform.position.y == target:
			moving = false
			_arrived = _players(_riders)
			_update_gates()
		return

	var riders: Array[Player] = _players(_riders)
	_arrived = _arrived.filter(func(player: Player) -> bool: return player in riders)
	if boarding:
		_waited = 0.0
		return
	if riders.any(func(player: Player) -> bool: return player not in _arrived):
		_waited += delta
		if _waited >= departure_delay:
			_ride(_other(deck))
		return
	_waited = 0.0
	if riders.is_empty() and not _players(_calls[_other(deck)]).is_empty():
		_ride(_other(deck))


## Whether the gate on `at` is open (the platform stands there).
func is_open(at: Deck) -> bool:
	return not moving and deck == at


## The platform's height above the lower deck right now.
func platform_height() -> float:
	return _platform.position.y


## Calls the platform to `at` (a crew member waiting at its gate there), unless it rides or someone
## stands on it.
func call_to(at: Deck) -> void:
	if not moving and deck != at and _players(_riders).is_empty():
		_ride(at)


## Sends the platform to `to` (a crew member standing on it).
func send(to: Deck) -> void:
	boarding = false
	if not moving and deck != to:
		_ride(to)


## The middle of the platform's floor right now (global).
func platform_floor() -> Vector3:
	return to_global(Vector3.UP * _platform.position.y)


## The floor in the gate's opening on `at` (global; the shaft opens towards +z).
func gate_floor(at: Deck) -> Vector3:
	return to_global(Vector3(0.0, _height(at), _gates[at].position.z))


func _ride(to: Deck) -> void:
	deck = to
	moving = true
	_waited = 0.0
	_update_gates()


func _update_gates() -> void:
	for at: Deck in [Deck.LOWER, Deck.UPPER]:
		var gate: StaticBody3D = _gates[at]
		var open: bool = is_open(at)
		gate.visible = not open
		for shape: CollisionShape3D in gate.find_children("*", "CollisionShape3D", false):
			shape.set_deferred(&"disabled", open)


func _height(at: Deck) -> float:
	return travel_height if at == Deck.UPPER else 0.0


static func _other(at: Deck) -> Deck:
	return Deck.LOWER if at == Deck.UPPER else Deck.UPPER


## Living players in `area`.
static func _players(area: Area3D) -> Array[Player]:
	var players: Array[Player] = []
	for body: Node3D in area.get_overlapping_bodies():
		var player := body as Player
		if player and not player.fallen:
			players.append(player)
	return players
