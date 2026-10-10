class_name Miner
extends StaticBody3D
## Mines its ore node's ore over time and stops when full. The fill level shows in the world:
## the glass column fills up in the ore color and the lamp on top lights up when full.
## A hose connects to the nearest player within `settings.hose_range` and moves the ore to them.

## Emitted once each time the miner becomes full.
signal filled

@export var settings: MinerSettings

## Set by the ore node before the miner enters the tree.
var ore_type: OreType
## Units currently held, between 0 and `settings.capacity`.
var amount: float = 0.0
## The player the hose is connected to, or null.
var hose_target: Player

@onready var _fill_pivot: Node3D = $FillPivot
@onready var _fill: MeshInstance3D = $FillPivot/Fill
@onready var _full_lamp: MeshInstance3D = $FullLamp
@onready var _hose_outlet: Marker3D = $HoseOutlet
@onready var _hose: Hose = $Hose


func _ready() -> void:
	if ore_type:
		_fill.material_override = ore_type.get_material()
		_hose.material_override = ore_type.get_material()
	_hose.visible = false
	_update_gauge()


func _physics_process(delta: float) -> void:
	if not is_full():
		amount = minf(amount + settings.fill_rate * delta, settings.capacity)
		_update_gauge()
		if is_full():
			filled.emit()

	hose_target = Player.nearest(get_tree(), global_position, settings.hose_range)
	if hose_target:
		hose_target.add_cargo(ore_type, take(settings.transfer_rate * delta))


func _process(_delta: float) -> void:
	_hose.visible = hose_target != null
	if hose_target:
		_hose.build(
			_hose_outlet.global_position, hose_target.get_hose_port_position(), global_position.y
		)


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
