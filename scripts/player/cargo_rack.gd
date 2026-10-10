class_name CargoRack
extends Node3D
## Shows the player's cargo on their back: one column of canisters per ore type, side by side
## in the order the types were first picked up. Each canister holds `units_per_canister`; full
## canisters stack up and the top one fills in the ore color. No carry limit, so columns grow.

const CANISTER_HEIGHT: float = 0.35
const CANISTER_RADIUS: float = 0.12
const COLUMN_SPACING: float = 0.27

## Units one canister shows. Greybox: one full miner. TBD (playtest).
@export var units_per_canister: float = 180.0

## Column per ore type, in pickup order.
var _columns: Dictionary[OreType, Node3D] = {}
var _glass_mesh: CylinderMesh
var _fill_mesh: CylinderMesh


func _ready() -> void:
	var glass_material := StandardMaterial3D.new()
	glass_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_material.albedo_color = Color(0.75, 0.85, 0.95, 0.25)
	glass_material.roughness = 0.1
	_glass_mesh = _cylinder(CANISTER_RADIUS, CANISTER_HEIGHT * 0.95)
	_glass_mesh.material = glass_material
	_fill_mesh = _cylinder(CANISTER_RADIUS * 0.8, CANISTER_HEIGHT * 0.9)


## Shows `amount` units of `ore_type` (connect to `Player.cargo_changed`).
func show_cargo(ore_type: OreType, amount: float) -> void:
	var column: Node3D = _columns.get(ore_type)
	if not column:
		column = Node3D.new()
		column.name = ore_type.display_name.to_pascal_case()
		add_child(column)
		_columns[ore_type] = column
		_arrange_columns()

	var count: int = ceili(maxf(amount, 0.0) / units_per_canister)
	while column.get_child_count() < count:
		_add_canister(column, ore_type)
	while column.get_child_count() > count:
		var last: Node = column.get_child(-1)
		column.remove_child(last)
		last.queue_free()

	for i: int in count:
		var ratio: float = clampf(amount / units_per_canister - i, 0.001, 1.0)
		var fill_pivot: Node3D = column.get_child(i).get_child(1)
		fill_pivot.scale = Vector3(1.0, ratio, 1.0)


## Number of canisters shown for `ore_type`.
func canister_count(ore_type: OreType) -> int:
	var column: Node3D = _columns.get(ore_type)
	return column.get_child_count() if column else 0


## Fill level (0–1) of the topmost canister for `ore_type`, or 0 without one.
func top_fill(ore_type: OreType) -> float:
	var column: Node3D = _columns.get(ore_type)
	if not column or column.get_child_count() == 0:
		return 0.0
	return (column.get_child(-1).get_child(1) as Node3D).scale.y


func _add_canister(column: Node3D, ore_type: OreType) -> void:
	var canister := Node3D.new()
	canister.position.y = column.get_child_count() * CANISTER_HEIGHT
	column.add_child(canister)

	var glass := MeshInstance3D.new()
	glass.mesh = _glass_mesh
	glass.position.y = CANISTER_HEIGHT * 0.5
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	canister.add_child(glass)

	# Scaled from the canister's bottom; a zero scale would make the basis singular.
	var fill_pivot := Node3D.new()
	fill_pivot.position.y = CANISTER_HEIGHT * 0.05
	fill_pivot.scale = Vector3(1.0, 0.001, 1.0)
	canister.add_child(fill_pivot)
	var fill := MeshInstance3D.new()
	fill.mesh = _fill_mesh
	fill.material_override = ore_type.get_material()
	fill.position.y = CANISTER_HEIGHT * 0.45
	fill_pivot.add_child(fill)


## Centers the columns across the back.
func _arrange_columns() -> void:
	var i: int = 0
	for column: Node3D in _columns.values():
		column.position.x = (i - (_columns.size() - 1) * 0.5) * COLUMN_SPACING
		i += 1


static func _cylinder(radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 1
	return mesh
