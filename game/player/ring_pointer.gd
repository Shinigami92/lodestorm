class_name RingPointer
extends Node3D
## An arrow on the edge of a player's suit ring (see `SuitRing`): put one anywhere under the player
## (the way back to the ship, the tracked quest, the ore scanner, the miner radar) and the
## ring draws it while it's visible, without knowing it. Its -Z is where it points (`point_along`),
## `color` the arrow's color, `arrow` its shape. With more pointers than the ring has room for, the
## lowest `priority` wins.

const GROUP: StringName = &"ring_pointers"

## How far beyond the ring's radius its tip reaches and half its width at the base (m; the tip at
## most `SuitRing.MAX_ARROW`). TBD (playtest).
var arrow := Vector2(0.84, 0.26)
## Which pointers the ring keeps when it has too many (lower first): the ship's 0, the tracked
## quest's 1, a miner under attack 2, the ore scanner's 3, a full or dry miner 4 (see
## `MinerRadar`).
var priority: int = 0
## The arrow's color (its alpha too).
var color := Color.WHITE
## The player whose ring draws it (the nearest one above it), or null.
var holder: Player


func _enter_tree() -> void:
	add_to_group(GROUP)
	var node: Node = get_parent()
	while node and node is not Player:
		node = node.get_parent()
	holder = node as Player


## Turns it to point along `offset` (global, on the ground).
func point_along(offset: Vector3) -> void:
	global_basis = Basis(Vector3.UP, atan2(-offset.x, -offset.z))


## The direction it points (global).
func heading() -> Vector3:
	return -global_basis.z
