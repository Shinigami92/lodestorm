class_name WellDelivery
extends LobDelivery
## Fires a slow orb (Nadir, see `WellOrb`) that opens a gravity well where it stops (see
## `GravityWell`): it aims where a `LobDelivery` lands (the locked target, the cursor's spot, along
## the aim), flying almost straight through aliens; rock, a nest or the ground stop it. The well
## pulls aliens within its radius (`blast_radius`, wider with the MK level of the weapon's blast)
## to its middle, holds them for `hold_time` seconds and bursts with the weapon's hit. A player has
## one well open at a time: the next shot bursts the last one at once. The landing ring shows where
## it opens and how far it pulls. All values TBD (playtest).

## Seconds a well holds before it bursts.
@export var hold_time: float = 3.0

@export_group("Sounds")
## While a well is open (a loop).
@export var hum_sound: Sound


func attack(weapon: Weapon) -> void:
	for well: GravityWell in GravityWell.opened_by(weapon.holder):
		well.burst()
	super(weapon)


func _prepare(shot: LobbedShot, weapon: Weapon) -> void:
	var orb := shot as WellOrb
	orb.through_aliens = true
	orb.opener = weapon.holder
	orb.hold_time = hold_time
	orb.hum_sound = hum_sound
