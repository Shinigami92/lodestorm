class_name RackShelf
extends StationPart
## One alloy's shelf in the ingot rack (`IngotRack`), greybox until the cargo bay's art pass: a
## plank with the bars stacked on it, metal glowing softly in the alloy's color (up to `SHOWN_BARS`,
## in layers of four across and two deep; steady, so a full shelf doesn't flash), and a plate on its
## front edge with the alloy's name and the exact count. Until the alloy's recipe is known (or one
## was in the hold) the shelf stays dark and its plate shows "?", so the rack doesn't give away
## what's still to find.

## Bars shown at most; the plate counts the rest.
const SHOWN_BARS: int = 24
const BAR_SIZE := Vector3(0.17, 0.06, 0.1)
## Bars per layer across (x) and deep (z), and their spacing, in m.
const ACROSS: int = 4
const DEEP: int = 2
const SPACING := Vector3(0.21, 0.07, 0.14)
## How strongly the bars glow (the silos' fill glows far brighter).
const BAR_GLOW: float = 0.7
const PLANK_COLOR := Color(0.3, 0.31, 0.33)
const DARK_COLOR := Color(0.1, 0.1, 0.11)
## Height of the plate's text, in m.
const PLATE_TEXT: float = 0.085

static var _bar_mesh: BoxMesh
## The bars' material per alloy.
static var _bar_materials: Dictionary[AlloyType, StandardMaterial3D] = {}

## Its alloy (also `item`).
var alloy: AlloyType
## Width and depth of the plank, in m.
var width: float = 0.9
var depth: float = 0.45
## Bars in the hold.
var count: int = 0
## Whether the alloy shows (its recipe known or one was in the hold), else it shows as unknown.
var known: bool = false

var _bars := MultiMeshInstance3D.new()
var _plank_material := StandardMaterial3D.new()
var _plate := Label3D.new()


## Builds the shelf for `of_alloy` (call before adding it to the tree).
func setup(of_alloy: AlloyType, plank_width: float, plank_depth: float) -> void:
	alloy = of_alloy
	item = of_alloy
	width = plank_width
	depth = plank_depth
	name = "Shelf" + of_alloy.display_name.to_pascal_case()
	pick_radius = width * 0.5
	card_offset = Vector2(-1.9, 0.0)


func _ready() -> void:
	if not _bar_mesh:
		_bar_mesh = BoxMesh.new()
		_bar_mesh.size = BAR_SIZE
	_plank_material.metallic = 0.3
	_plank_material.roughness = 0.6
	var plank := MeshInstance3D.new()
	plank.name = "Plank"
	var plank_mesh := BoxMesh.new()
	plank_mesh.size = Vector3(width, 0.04, depth)
	plank_mesh.material = _plank_material
	plank.mesh = plank_mesh
	plank.position.y = -0.02
	add_child(plank)
	outline = plank

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _bar_mesh
	multimesh.instance_count = SHOWN_BARS
	multimesh.visible_instance_count = 0
	for index: int in SHOWN_BARS:
		multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, bar_position(index)))
	_bars.name = "Bars"
	_bars.multimesh = multimesh
	_bars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bars)

	_plate.name = "Plate"
	_plate.pixel_size = PLATE_TEXT / 64.0
	_plate.font_size = 64
	_plate.outline_size = 12
	_plate.modulate = Color(0.85, 0.92, 1.0)
	_plate.position = Vector3(0.0, -0.075, depth * 0.5 + 0.01)
	# Names and numbers: the name is translated by `ItemType.get_display_name`.
	_plate.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_plate.layers = RenderLayers.EFFECTS
	add_child(_plate)
	_update()


## Shows `bars` bars; `shown`: the alloy is known.
func show_count(bars: int, shown: bool) -> void:
	count = maxi(bars, 0)
	known = shown or count > 0
	if is_node_ready():
		_update()


## How many bars it shows stacked.
func shown_bars() -> int:
	return mini(count, SHOWN_BARS) if known else 0


## The bars' material for `of_alloy`: metal in its color, glowing a little (a dark body darker,
## with a stronger glow).
static func bar_material(of_alloy: AlloyType) -> StandardMaterial3D:
	if not _bar_materials.has(of_alloy):
		var material := StandardMaterial3D.new()
		material.albedo_color = of_alloy.color * (0.15 if of_alloy.dark_body else 0.55)
		material.metallic = 0.8
		material.roughness = 0.35
		material.emission_enabled = true
		material.emission = of_alloy.color
		material.emission_energy_multiplier = BAR_GLOW * (0.6 if of_alloy.dark_body else 0.4)
		_bar_materials[of_alloy] = material
	return _bar_materials[of_alloy]


## Where the `index`th bar lies on the plank: layers from the bottom, each four across and two
## deep, back row first.
static func bar_position(index: int) -> Vector3:
	@warning_ignore("integer_division")
	var layer: int = index / (ACROSS * DEEP)
	var in_layer: int = index % (ACROSS * DEEP)
	var x: int = in_layer % ACROSS
	@warning_ignore("integer_division")
	var z: int = in_layer / ACROSS
	return Vector3(
		(x - (ACROSS - 1) * 0.5) * SPACING.x,
		BAR_SIZE.y * 0.5 + layer * SPACING.y,
		(z - (DEEP - 1) * 0.5) * SPACING.z
	)


func _update() -> void:
	_plank_material.albedo_color = PLANK_COLOR if known else DARK_COLOR
	_bars.multimesh.visible_instance_count = shown_bars()
	_bars.material_override = bar_material(alloy) if known else null
	if known:
		_plate.text = "%s  %d" % [alloy.get_display_name().to_upper(), count]
	else:
		_plate.text = "?"
