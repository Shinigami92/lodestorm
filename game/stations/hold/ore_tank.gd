class_name OreTank
extends StationPart
## One ore's silo in the hold (`OreHold`), greybox until the cargo bay's art pass: an
## opaque metal silo on a base ring, with bands, a conical top with a hatch and, facing the
## camera's side (+Z), a display at the top of its body and a window strip below it, where the ore
## glows up to `amount` of `capacity` (full beyond it). The display shows the exact amount in the
## ore's color, big enough to read from the normal camera (it sits high enough to show over the
## silo in front of it), with the ore's name small below. Rarer ores get smaller silos. Until the
## ore was first brought aboard its window stays dark and its display shows a grey "?" without a
## name, so the hold doesn't give away what's still to find. Players can't walk through it;
## `interact` next to it uses it (`use_point`, its base outlined amber while it's the target).

const BASE_HEIGHT: float = 0.22
## The window strip: its width relative to the silo's diameter, and how much of the body's height it
## spans.
const WINDOW_WIDTH: float = 0.34
## Gaps between the window and the body's bottom, and between the window and the display, in m.
const WINDOW_MARGIN: float = 0.2
const WINDOW_GAP: float = 0.12
## The display: its width relative to the silo's diameter, its height and its gap to the body's top
## (m; the top 0.8 m of a far row's silo show over the near row from the camera).
const DISPLAY_WIDTH: float = 0.72
const DISPLAY_HEIGHT: float = 0.66
const DISPLAY_MARGIN: float = 0.1
## The amount's text fits this many digits at its full size (more get smaller).
const DISPLAY_DIGITS: int = 4
## Height of the amount's and the name's text (em, m), and how bright the amount glows.
const AMOUNT_TEXT: float = 0.52
const NAME_TEXT: float = 0.1
const AMOUNT_GLOW: float = 1.4
const UNKNOWN_COLOR := Color(0.36, 0.39, 0.43)
const METAL_COLOR := Color(0.36, 0.38, 0.41)
const TRIM_COLOR := Color(0.17, 0.18, 0.2)
const WINDOW_COLOR := Color(0.02, 0.025, 0.03)
const FONT_SIZE: int = 128

static var _metal: StandardMaterial3D
static var _trim: StandardMaterial3D
static var _window: StandardMaterial3D
static var _font: FontVariation

## Its ore (also `item`).
var ore_type: OreType
## Radius and height of the silo (base to the top of its cone), in m.
var radius: float = 0.5
var height: float = 3.0
## Units shown as full. TBD (playtest).
var capacity: float = 1000.0
## Units in the hold.
var amount: float = 0.0
## Whether the ore was ever brought aboard (else it shows as unknown).
var found: bool = false

## Where players use it (anywhere around it within `interact_range`).
var use_point := Interactable.new()

var _fill := MeshInstance3D.new()
var _fill_pivot := Node3D.new()
var _amount := Label3D.new()
var _name := Label3D.new()
## Width the amount's text may take, in m.
var _amount_width: float = 1.0


## Builds the silo for `of_ore` (call before adding it to the tree).
func setup(of_ore: OreType, silo_radius: float, silo_height: float, full_at: float) -> void:
	ore_type = of_ore
	item = of_ore
	radius = silo_radius
	height = silo_height
	capacity = full_at
	name = "Tank" + of_ore.display_name.to_pascal_case()
	pick_radius = maxf(radius * 1.6, height * 0.4)
	# Left of the silo: the ramp's countdown hangs to the right, by the door.
	card_offset = Vector2(-(radius + 1.6), 0.0)


func _ready() -> void:
	_make_materials()
	var bottom: float = -height * 0.5
	var cone: float = radius * 0.45
	var body_height: float = height - BASE_HEIGHT - cone

	# The shell (outlined while selected): base ring, body, bands, cone and hatch.
	var shell := Node3D.new()
	shell.name = "Shell"
	add_child(shell)
	outline = shell
	_cylinder(shell, radius + 0.1, radius + 0.14, BASE_HEIGHT, bottom + BASE_HEIGHT * 0.5, _trim)
	var body_bottom: float = bottom + BASE_HEIGHT
	_cylinder(shell, radius, radius, body_height, body_bottom + body_height * 0.5, _metal)
	for band: float in [0.18, 0.5, 0.82]:
		_cylinder(
			shell, radius + 0.025, radius + 0.025, 0.07, body_bottom + body_height * band, _trim
		)
	_cylinder(shell, radius * 0.18, radius, cone, body_bottom + body_height + cone * 0.5, _metal)
	var hatch := MeshInstance3D.new()
	var hatch_mesh := BoxMesh.new()
	hatch_mesh.size = Vector3(radius * 0.4, 0.08, radius * 0.4)
	hatch_mesh.material = _trim
	hatch.mesh = hatch_mesh
	hatch.position.y = height * 0.5 + 0.02
	shell.add_child(hatch)

	# The display at the top of the body on the camera's side: a frame and a dark screen with the
	# amount and the name.
	var display_width: float = radius * 2.0 * DISPLAY_WIDTH
	var display_center: float = body_bottom + body_height - DISPLAY_MARGIN - DISPLAY_HEIGHT * 0.5
	_frame(display_width, DISPLAY_HEIGHT, display_center, DISPLAY_WIDTH)
	_box(
		Vector3(display_width, DISPLAY_HEIGHT, 0.01),
		Vector3(0.0, display_center, radius + 0.065),
		_window
	)
	_amount_width = display_width - 0.12
	_amount.name = "Amount"
	_amount.position = Vector3(0.0, display_center + 0.06, radius + 0.075)
	_name.name = "Name"
	_name.pixel_size = NAME_TEXT / FONT_SIZE
	_name.modulate = Color(0.7, 0.76, 0.84)
	_name.position = Vector3(0.0, display_center - DISPLAY_HEIGHT * 0.5 + 0.1, radius + 0.075)
	for label: Label3D in [_amount, _name]:
		label.font = _font
		label.font_size = FONT_SIZE
		label.outline_size = 0
		# Names and numbers: the name is translated by `OreType.get_display_name`.
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		label.layers = RenderLayers.EFFECTS
		add_child(label)

	# The window strip below it: a frame, dark glass and the glowing ore behind it.
	var window_width: float = radius * 2.0 * WINDOW_WIDTH
	var window_bottom: float = body_bottom + WINDOW_MARGIN
	var window_height: float = (
		display_center - DISPLAY_HEIGHT * 0.5 - WINDOW_GAP - 0.08 - window_bottom
	)
	_frame(window_width, window_height, window_bottom + window_height * 0.5, WINDOW_WIDTH)
	_box(
		Vector3(window_width, window_height, 0.01),
		Vector3(0.0, window_bottom + window_height * 0.5, radius + 0.065),
		_window
	)
	_fill_pivot.name = "Fill"
	_fill_pivot.position = Vector3(0.0, window_bottom, radius + 0.075)
	add_child(_fill_pivot)
	var fill_mesh := BoxMesh.new()
	fill_mesh.size = Vector3(window_width - 0.04, window_height, 0.01)
	_fill.mesh = fill_mesh
	_fill.position.y = window_height * 0.5
	_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fill_pivot.add_child(_fill)

	var body := StaticBody3D.new()
	body.name = "Body"
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius + 0.12
	cylinder.height = height
	shape.shape = cylinder
	body.add_child(shape)
	add_child(body)

	use_point.name = "Use"
	use_point.position.y = -height * 0.5
	use_point.interact_range = radius + 1.1
	var ring := MeshInstance3D.new()
	ring.name = "Highlight"
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = radius + 0.2
	ring_mesh.outer_radius = radius + 0.32
	ring_mesh.rings = 32
	ring_mesh.ring_segments = 4
	var ring_material := StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.albedo_color = StationPart.SELECTED_COLOR
	ring_mesh.material = ring_material
	ring.mesh = ring_mesh
	ring.scale = Vector3(1.0, 0.1, 1.0)
	ring.position.y = 0.02
	ring.visible = false
	use_point.add_child(ring)
	add_child(use_point)
	_update()


## Shows `units` in the silo; `was_found`: the ore was ever brought aboard.
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
	if found:
		_amount.text = str(floori(amount))
		var glow: Color = ore_type.color * AMOUNT_GLOW
		glow.a = 1.0
		_amount.modulate = glow
		_name.text = ore_type.get_display_name().to_upper()
	else:
		_amount.text = "?"
		_amount.modulate = UNKNOWN_COLOR
		_name.text = ""
	_amount.pixel_size = amount_text_height() / FONT_SIZE


## Height (em, m) of the amount's text: `AMOUNT_TEXT` for up to `DISPLAY_DIGITS` digits, smaller
## where the silo's display is too narrow for that, and for longer amounts.
func amount_text_height() -> float:
	var digits: int = maxi(_amount.text.length(), DISPLAY_DIGITS)
	var text_width: float = (
		_font.get_string_size("0".repeat(digits), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		/ FONT_SIZE
	)
	return minf(AMOUNT_TEXT, _amount_width / text_width)


## A frame `width` × `frame_height` around a flat panel centered at `at` on the camera's side,
## reaching back to where the round body meets its edges (`relative_width`: of the diameter).
func _frame(width: float, frame_height: float, at: float, relative_width: float) -> void:
	var edge: float = radius * cos(asin(relative_width))
	var frame_depth: float = radius - edge + 0.06
	_box(
		Vector3(width + 0.08, frame_height + 0.08, frame_depth),
		Vector3(0.0, at, edge + frame_depth * 0.5),
		_trim
	)


func _cylinder(
	parent: Node3D, top: float, bottom: float, length: float, at: float, material: Material
) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = length
	mesh.radial_segments = 20
	mesh.rings = 1
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position.y = at
	parent.add_child(instance)


func _box(box_size: Vector3, at: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = box_size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	add_child(instance)


## The silos' shared materials and font.
static func _make_materials() -> void:
	if _metal:
		return
	_metal = StandardMaterial3D.new()
	_metal.albedo_color = METAL_COLOR
	_metal.metallic = 0.3
	_metal.roughness = 0.5
	_trim = StandardMaterial3D.new()
	_trim.albedo_color = TRIM_COLOR
	_trim.metallic = 0.3
	_trim.roughness = 0.6
	_window = StandardMaterial3D.new()
	_window.albedo_color = WINDOW_COLOR
	_window.metallic = 0.2
	_window.roughness = 0.08
	# Bold, so the digits read from afar.
	_font = FontVariation.new()
	_font.base_font = ThemeDB.fallback_font
	_font.variation_embolden = 0.6
