class_name QuestPack
extends Node3D
## The quest items a player carries during a run (see `RecoverFragmentsGoal`, `RecoverItemGoal`),
## shown on the back (it follows the backpack's CargoRack marker): fragments click into a row of
## slots low on the backpack, one per fragment, glowing amber; an item is strapped across the
## backpack's bottom (several stack downwards). They count once their carrier is aboard
## (`take_all`, see `QuestVisit.count_carried`) and are lost when the carrier dies (`drop`): they
## lie in a crate or at their site again on a later visit.

## Emitted when what it carries changes.
signal changed

const FRAGMENT: PackedScene = preload("res://game/quests/items/blueprint_fragment.tscn")
## Where the row of fragment slots sits (its middle, behind the tubes' feet), the slots' spacing
## and the fragments' scale there.
const FRAGMENT_ROW := Vector3(0.0, -0.03, 0.08)
const FRAGMENT_SPACING: float = 0.075
const FRAGMENT_SCALE: float = 0.45
## Where the first item hangs (strapped flat under the backpack, its long side across), how far
## each further one hangs below it, and their scale.
const ITEM_AT := Vector3(0.0, -0.17, 0.0)
const ITEM_STEP: float = 0.13
const ITEM_SCALE: float = 0.6

## What it carries: per fragment or item, the quest visit's entry it counts for.
var carried: Array[QuestVisit.Entry] = []


## Adds a fragment or an item of `entry`'s (an item if `entry` has one to recover).
func add(entry: QuestVisit.Entry) -> void:
	carried.append(entry)
	_show()


## How many fragments it carries.
func fragment_count() -> int:
	return carried.filter(func(entry: QuestVisit.Entry) -> bool: return not entry.item).size()


## How many items it carries.
func item_count() -> int:
	return carried.size() - fragment_count()


## Takes everything out (its carrier is aboard) and returns it.
func take_all() -> Array[QuestVisit.Entry]:
	var taken: Array[QuestVisit.Entry] = carried
	carried = []
	_show()
	return taken


## Loses everything (its carrier died).
func drop() -> void:
	take_all()


## Shows the fragments in their slots and the items strapped on.
func _show() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	var fragments: int = fragment_count()
	var slots: int = 0
	var items: int = 0
	for entry: QuestVisit.Entry in carried:
		var look: Node3D
		if entry.item:
			look = entry.item.instantiate() as Node3D
			look.position = ITEM_AT + Vector3.DOWN * ITEM_STEP * items
			look.scale = Vector3.ONE * ITEM_SCALE
			items += 1
		else:
			look = FRAGMENT.instantiate() as Node3D
			var across: float = (slots - (fragments - 1) * 0.5) * FRAGMENT_SPACING
			look.position = FRAGMENT_ROW + Vector3.RIGHT * across
			look.scale = Vector3.ONE * FRAGMENT_SCALE
			slots += 1
		add_child(look)
	RenderLayers.put(self, RenderLayers.CHARACTERS)
	changed.emit()
