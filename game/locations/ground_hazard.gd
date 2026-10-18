class_name GroundHazard
extends Area3D
## Ground that hinders whoever walks on it, players and aliens alike (see `LocationBiome.Hazard`):
## slick ice so far. Bodies with a `ground_contact` (`GroundContact`) are told when they step in
## and out. All values greybox, TBD (playtest).

## How well feet grip here: the share of the usual acceleration (1: as usual).
@export_range(0.0, 1.0) var grip: float = 1.0

## The contacts of the bodies standing in it.
var _contacts: Array[GroundContact] = []


func _ready() -> void:
	monitorable = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _exit_tree() -> void:
	for contact: GroundContact in _contacts:
		contact.leave(self)
	_contacts.clear()


func _on_body_entered(body: Node3D) -> void:
	var contact: GroundContact = GroundContact.of(body)
	if contact and contact not in _contacts:
		_contacts.append(contact)
		contact.enter(self)


func _on_body_exited(body: Node3D) -> void:
	var contact: GroundContact = GroundContact.of(body)
	if contact:
		_contacts.erase(contact)
		contact.leave(self)
