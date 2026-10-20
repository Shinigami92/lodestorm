class_name WellOrb
extends LobbedShot
## What a `WellDelivery` fires (Nadir): a slow, dark orb flying through aliens that opens a
## `GravityWell` where it stops.

## Who fired it (one well open per player), how long its well holds, and the well's hum.
var opener: Node
var hold_time: float = 3.0
var hum_sound: Sound


func _land(point: Vector3) -> void:
	GravityWell.open(
		get_parent(), point, blast_radius, hit, hold_time, opener, blast_sound, hum_sound
	)
	queue_free()
