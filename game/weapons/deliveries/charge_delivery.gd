class_name ChargeDelivery
extends LobDelivery
## Tosses a proximity charge a short way (Wick, see `PlacedCharge`): it lands where a `LobDelivery`
## would (at most `reach` m away), past the aliens in between, and stays on the ground until an
## alien comes close. A player has at most `charges` of them out at once (more with the MK level of
## the weapon's charges); one more removes their oldest. The landing ring shows the charge's reach.
## All values TBD (playtest).

## Charges one player can have out at once, at MK1.
@export var charges: int = 3
## An alien this close trips a charge (horizontally, m).
@export var trigger_radius: float = 2.5
## Seconds from landing until a charge is armed.
@export var arm_time: float = 1.0
## Seconds from tripping until it blasts.
@export var trip_time: float = 0.35

@export_group("Sounds")
## A charge armed.
@export var arm_sound: Sound
## A charge tripped.
@export var trip_sound: Sound


func attack(weapon: Weapon) -> void:
	var placed: Array[PlacedCharge] = placed_by(weapon.holder)
	while not placed.is_empty() and placed.size() >= charges_of(weapon):
		(placed.pop_front() as PlacedCharge).fizzle()
	super(weapon)


## How many charges `weapon`'s holder can have out at once, with its MK level.
func charges_of(weapon: Weapon) -> int:
	return maxi(1, roundi(charges * weapon.multiplier(WeaponPart.Stat.CHARGES)))


func ring_radius(_weapon: Weapon) -> float:
	return trigger_radius


## The charges `layer` has out (in the air or on the ground), oldest first.
static func placed_by(layer: Node) -> Array[PlacedCharge]:
	var placed: Array[PlacedCharge] = []
	if not layer or not layer.is_inside_tree():
		return placed
	for node: Node in layer.get_tree().get_nodes_in_group(PlacedCharge.GROUP):
		var charge := node as PlacedCharge
		if charge.layer == layer and not charge.is_queued_for_deletion():
			placed.append(charge)
	placed.sort_custom(func(a: PlacedCharge, b: PlacedCharge) -> bool: return a.serial < b.serial)
	return placed


func _prepare(shot: LobbedShot, weapon: Weapon) -> void:
	var charge := shot as PlacedCharge
	charge.layer = weapon.holder
	charge.trigger_radius = trigger_radius
	charge.arm_time = arm_time
	charge.trip_time = trip_time
	charge.arm_sound = arm_sound
	charge.trip_sound = trip_sound
	if weapon.holder is Player:
		charge.color = (weapon.holder as Player).color()
