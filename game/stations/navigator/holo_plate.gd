class_name HoloPlate
extends Node3D
## A name plate in the navigator's hologram: a name, and below it a row of danger pips and ore
## badges (each ore's icon in its color, glowing in its pattern; "?" for an ore not known yet). It
## always faces the camera and draws over the hologram, centered above its origin.

const PIP_COLOR_OFF := Color(1.0, 1.0, 1.0, 0.25)
## Size of the name's pixels and of a badge or pip, in m (at scale 1).
const PIXEL_SIZE: float = 0.0016
const BADGE_SIZE: float = 0.07
const PIP_SIZE: float = 0.03
const GAP: float = 0.012
## Draws over the hologram's see-through meshes (and the globe).
const PRIORITY: int = 20

## The pips' circle, made once.
static var _pip_texture: ImageTexture

## How see-through it is (1: fully visible), e.g. for what can't be reached yet.
var opacity: float = 1.0:
	set(value):
		opacity = value
		_apply_opacity()

var _name := Label3D.new()
var _badges: Array[Sprite3D] = []
var _badge_ores: Array[OreType] = []
var _unknown: Array[Label3D] = []
var _pips: Array[Sprite3D] = []
var _pip_colors: Array[Color] = []
var _ores: Array[OreType] = []
var _phase: float = randf() * OreGlow.PHASE_SPREAD


## A plate for `text`; `danger` (0–2, -1: none) lights that many pips plus one in `danger_color`;
## `ores` are the badges (null: "?").
func _init(
	text: String = "",
	ores: Array[OreType] = [],
	danger: int = -1,
	danger_color: Color = Color.WHITE,
	font_size: int = 32
) -> void:
	_name.text = text
	_name.uppercase = true
	_name.font_size = font_size
	_name.outline_size = 6
	_name.outline_modulate = Color(0.0, 0.02, 0.04, 0.8)
	_name.pixel_size = PIXEL_SIZE
	_name.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_setup(_name)
	add_child(_name)
	var row: Array[Node3D] = []
	if danger >= 0:
		for i: int in 3:
			var pip := Sprite3D.new()
			pip.texture = pip_texture()
			pip.pixel_size = PIP_SIZE / pip.texture.get_width()
			_pip_colors.append(danger_color if i <= danger else PIP_COLOR_OFF)
			_setup(pip)
			_pips.append(pip)
			row.append(pip)
	_ores = ores.duplicate()
	for ore_type: OreType in ores:
		if ore_type:
			var badge := Sprite3D.new()
			badge.texture = ore_type.icon if ore_type.icon else ItemBadge.fallback_icon()
			badge.pixel_size = BADGE_SIZE / badge.texture.get_height()
			_setup(badge)
			_badges.append(badge)
			_badge_ores.append(ore_type)
			row.append(badge)
		else:
			var unknown := Label3D.new()
			unknown.text = "?"
			unknown.font_size = font_size
			unknown.outline_size = 6
			unknown.pixel_size = PIXEL_SIZE
			unknown.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			_setup(unknown)
			_unknown.append(unknown)
			row.append(unknown)
	_lay_out(row)
	_apply_opacity()


func _process(_delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera:
		var at_scale: Vector3 = global_basis.get_scale()
		global_basis = camera.global_basis.orthonormalized().scaled(at_scale)
	var time: float = Time.get_ticks_msec() / 1000.0
	for i: int in _badges.size():
		var ore_type: OreType = _badge_ores[i]
		var glow: float = OreGlow.intensity(ore_type.glow, time, _phase + i)
		_badges[i].modulate = Color(ore_type.color * (0.55 + 0.45 * glow), opacity)


## The name shown (as given, before upper case).
func get_text() -> String:
	return _name.text


## The ores its badges show (null: "?"), in order.
func get_ores() -> Array[OreType]:
	return _ores.duplicate()


## How many of its pips are lit.
func get_lit_pips() -> int:
	return _pip_colors.filter(func(c: Color) -> bool: return c != PIP_COLOR_OFF).size()


## A white disc with a soft edge, for the pips.
static func pip_texture() -> ImageTexture:
	if _pip_texture:
		return _pip_texture
	var size: int = 32
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for y: int in size:
		for x: int in size:
			var distance: float = Vector2(x + 0.5, y + 0.5).distance_to(Vector2(size, size) * 0.5)
			var alpha: float = clampf(size * 0.5 - 1.0 - distance, 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	_pip_texture = ImageTexture.create_from_image(image)
	return _pip_texture


func _setup(geometry: GeometryInstance3D) -> void:
	geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if geometry is SpriteBase3D:
		var sprite := geometry as SpriteBase3D
		sprite.shaded = false
		sprite.double_sided = false
		sprite.no_depth_test = true
		sprite.render_priority = PRIORITY
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if geometry is Label3D:
		var label := geometry as Label3D
		label.shaded = false
		label.double_sided = false
		label.no_depth_test = true
		label.render_priority = PRIORITY
		label.outline_render_priority = PRIORITY - 1


## The name centered above the origin, the row centered below it.
func _lay_out(row: Array[Node3D]) -> void:
	var widths: Array[float] = []
	var total: float = 0.0
	for node: Node3D in row:
		var width: float = BADGE_SIZE
		if node is Label3D:
			# A "?".
			width = BADGE_SIZE * 0.6
		elif _pips.has(node as Sprite3D):
			width = PIP_SIZE
		widths.append(width)
		total += width
	total += GAP * maxf(row.size() - 1, 0)
	var x: float = -total * 0.5
	for i: int in row.size():
		row[i].position = Vector3(x + widths[i] * 0.5, -BADGE_SIZE * 0.5 - GAP, 0.0)
		x += widths[i] + GAP
		add_child(row[i])


func _apply_opacity() -> void:
	_name.modulate = Color(1.0, 1.0, 1.0, opacity)
	_name.outline_modulate.a = 0.8 * opacity
	for i: int in _pips.size():
		var color: Color = _pip_colors[i]
		_pips[i].modulate = Color(color, color.a * opacity)
	for unknown: Label3D in _unknown:
		unknown.modulate = Color(1.0, 1.0, 1.0, opacity)
