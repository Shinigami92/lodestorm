class_name BeaconLight
extends MeshInstance3D
## A light that blinks (the expedition camp's beacon): bright for a moment once every `period`,
## with an optional `OmniLight3D` child blinking along.

## Time between two flashes, in s (slower than 3 Hz).
@export var period: float = 1.4
## Share of the period it's lit.
@export_range(0.05, 0.95) var lit_share: float = 0.2
@export var lit_energy: float = 6.0
@export var dark_energy: float = 0.3

var _time: float = 0.0
var _material: StandardMaterial3D
var _light: OmniLight3D
var _light_energy: float = 0.0


func _ready() -> void:
	var source := get_active_material(0) as StandardMaterial3D
	if source:
		_material = source.duplicate() as StandardMaterial3D
		material_override = _material
	for child: Node in get_children():
		if child is OmniLight3D:
			_light = child as OmniLight3D
			_light_energy = _light.light_energy


func _process(delta: float) -> void:
	_time = fmod(_time + delta, period)
	var lit: bool = _time < period * lit_share
	if _material:
		_material.emission_energy_multiplier = lit_energy if lit else dark_energy
	if _light:
		_light.light_energy = _light_energy if lit else 0.0
