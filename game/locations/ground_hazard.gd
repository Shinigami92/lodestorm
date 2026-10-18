class_name GroundHazard
extends Area3D
## Ground that hinders whoever walks on it, players and aliens alike (see `LocationBiome.Hazard`):
## slick ice, vents (`GroundVent`), shards (`GroundShards`), mud (`GroundMud`). Bodies with a
## `ground_contact` (`GroundContact`) are told when they step in and out. All values greybox, TBD
## (playtest).

## How well feet grip here: the share of the usual acceleration (1: as usual).
@export_range(0.0, 1.0) var grip: float = 1.0
## How fast bodies walk here: the share of their usual speed (1: as usual).
@export_range(0.0, 1.0) var speed: float = 1.0

## The bodies standing in it, and their contacts.
var _bodies: Array[Node3D] = []
var _contacts: Array[GroundContact] = []


func _ready() -> void:
	monitorable = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _exit_tree() -> void:
	for contact: GroundContact in _contacts:
		contact.leave(self)
	_contacts.clear()
	_bodies.clear()


## Hurts every player and alien standing in it by `amount` (a player sees where it came from).
func hurt(amount: float) -> void:
	for body: Node3D in _bodies.duplicate():
		if not is_instance_valid(body):
			continue
		if body is Player:
			(body as Player).take_damage(amount, global_position)
		elif body is Alien:
			(body as Alien).take_damage(amount)


func _on_body_entered(body: Node3D) -> void:
	var contact: GroundContact = GroundContact.of(body)
	if contact and contact not in _contacts:
		_contacts.append(contact)
		_bodies.append(body)
		contact.enter(self)


func _on_body_exited(body: Node3D) -> void:
	var contact: GroundContact = GroundContact.of(body)
	if contact:
		_contacts.erase(contact)
		_bodies.erase(body)
		contact.leave(self)
