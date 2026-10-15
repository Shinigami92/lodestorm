class_name OreTank
extends StationPart
## One ore's tank in the ship's hold (`OreHold`), greybox until the cargo bay's art pass: a glass
## column on a dark plinth, filled in the ore's glowing material up to `amount` of `capacity`
## (full beyond it), with a name plate showing the exact amount. Rarer ores get smaller tanks. Until
## the ore was first brought aboard it stays dark and its plate shows "?", so the hold doesn't give
## away what's still to find.

const PLINTH_HEIGHT: float = 0.25
const GLASS_COLOR := Color(0.7, 0.82, 0.95, 0.16)
const UNKNOWN_GLASS_COLOR := Color(0.25, 0.3, 0.36, 0.5)
const PLINTH_COLOR := Color(0.12, 0.13, 0.15)
## Height of the plate's text, in m.
const PLATE_TEXT: float = 0.2

## Its ore (also `item`).
var ore_type: OreType
## Radius and height of the glass column, in m.
var radius: float = 0.5
var height: float = 3.0
## Units shown as full. TBD (playtest).
var capacity: float = 1000.0
## Units in the hold.
var amount: float = 0.0
## Whether the ore was ever brought aboard (else it shows as unknown).
var found: bool = false

var _glass := MeshInstance3D.new()
var _fill := MeshInstance3D.new()
var _fill_pivot := Node3D.new()
var _plate := Label3D.new()
var _glass_material := StandardMaterial3D.new()


## Builds the tank for `of_ore` (call before adding it to the tree).
func setup(of_ore: OreType, tank_radius: float, tank_height: float, full_at: float) -> void:
	ore_type = of_ore
	item = of_ore
	radius = tank_radius
	height = tank_height
	capacity = full_at
	name = "Tank" + of_ore.display_name.to_pascal_case()
	pick_radius = maxf(radius * 1.6, height * 0.4)
	card_offset = Vector2(radius + 1.4, 0.0)


func _ready() -> void:
	var plinth := MeshInstance3D.new()
	plinth.name = "Plinth"
	var plinth_mesh := CylinderMesh.new()
	plinth_mesh.top_radius = radius + 0.12
	plinth_mesh.bottom_radius = radius + 0.16
	plinth_mesh.height = PLINTH_HEIGHT
	plinth_mesh.radial_segments = 16
	var plinth_material := StandardMaterial3D.new()
	plinth_material.albedo_color = PLINTH_COLOR
	plinth_material.metallic = 0.6
	plinth_material.roughness = 0.5
	plinth_mesh.material = plinth_material
	plinth.mesh = plinth_mesh
	plinth.position.y = PLINTH_HEIGHT * 0.5 - height * 0.5
	add_child(plinth)
	# Outlined while selected: the plinth (an outline over the glass would hide the ore).
	outline = plinth

	_glass_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass_material.roughness = 0.08
	_glass_material.metallic_specular = 0.8
	var glass_mesh := CylinderMesh.new()
	glass_mesh.top_radius = radius
	glass_mesh.bottom_radius = radius
	glass_mesh.height = height - PLINTH_HEIGHT
	glass_mesh.radial_segments = 20
	glass_mesh.material = _glass_material
	_glass.name = "Glass"
	_glass.mesh = glass_mesh
	_glass.position.y = PLINTH_HEIGHT * 0.5
	_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_glass)

	_fill_pivot.name = "Fill"
	_fill_pivot.position.y = PLINTH_HEIGHT - height * 0.5
	add_child(_fill_pivot)
	var fill_mesh := CylinderMesh.new()
	fill_mesh.top_radius = radius * 0.86
	fill_mesh.bottom_radius = radius * 0.86
	fill_mesh.height = height - PLINTH_HEIGHT - 0.04
	fill_mesh.radial_segments = 20
	_fill.mesh = fill_mesh
	_fill.position.y = fill_mesh.height * 0.5
	_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fill_pivot.add_child(_fill)

	_plate.name = "Plate"
	_plate.pixel_size = PLATE_TEXT / 64.0
	_plate.font_size = 64
	_plate.outline_size = 12
	_plate.modulate = Color(0.85, 0.92, 1.0)
	_plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_plate.no_depth_test = false
	_plate.position = Vector3(0.0, PLINTH_HEIGHT - height * 0.5 - 0.05, radius + 0.35)
	_plate.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	# Names and numbers: the name is translated by `OreType.get_display_name`.
	_plate.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(_plate)
	_update()


## Shows `units` in the tank; `was_found`: the ore was ever brought aboard.
func show_amount(units: float, was_found: bool) -> void:
	amount = maxf(units, 0.0)
	found = was_found or amount > 0.0
	if is_node_ready():
		_update()


## How full it shows (0–1).
func fill_level() -> float:
	return clampf(amount / capacity, 0.0, 1.0) if found else 0.0


func _update() -> void:
	var level: float = fill_level()
	_fill.visible = level > 0.0
	_fill_pivot.scale = Vector3(1.0, maxf(level, 0.001), 1.0)
	_fill.material_override = ore_type.get_glow_material() if found else null
	_glass_material.albedo_color = GLASS_COLOR if found else UNKNOWN_GLASS_COLOR
	if found:
		_plate.text = "%s\n%d" % [ore_type.get_display_name().to_upper(), floori(amount)]
	else:
		_plate.text = "?"
