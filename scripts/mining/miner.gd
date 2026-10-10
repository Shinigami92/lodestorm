class_name Miner
extends StaticBody3D
## Mines its ore node's ore over time and stops when full. The fill level shows in the world:
## the glass column fills up in the ore color and the lamp on top lights up when full.

## Emitted once each time the miner becomes full.
signal filled

@export var settings: MinerSettings

## Set by the ore node before the miner enters the tree.
var ore_type: OreType
## Units currently held, between 0 and `settings.capacity`.
var amount: float = 0.0

@onready var _fill_pivot: Node3D = $FillPivot
@onready var _fill: MeshInstance3D = $FillPivot/Fill
@onready var _full_lamp: MeshInstance3D = $FullLamp


func _ready() -> void:
	if ore_type:
		_fill.material_override = ore_type.get_material()
	_update_gauge()


func _physics_process(delta: float) -> void:
	if is_full():
		return
	amount = minf(amount + settings.fill_rate * delta, settings.capacity)
	_update_gauge()
	if is_full():
		filled.emit()


func is_full() -> bool:
	return amount >= settings.capacity


## Removes up to `max_amount` units (e.g. for the hose) and returns how many were taken.
## A full miner starts mining again.
func take(max_amount: float) -> float:
	var taken: float = clampf(max_amount, 0.0, amount)
	amount -= taken
	_update_gauge()
	return taken


func _update_gauge() -> void:
	var ratio: float = amount / settings.capacity
	# A zero scale makes the basis singular, so hide the fill instead.
	_fill.visible = ratio > 0.0
	_fill_pivot.scale = Vector3(1.0, maxf(ratio, 0.001), 1.0)
	_full_lamp.visible = is_full()
