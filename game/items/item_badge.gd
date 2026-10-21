class_name ItemBadge
extends HBoxContainer
## An item (an ore, later an alloy) on a holo card: its icon tinted in its color and glowing in its
## pattern (`assets/shaders/ore_badge.gdshader`), optionally followed by its translated name. An
## item without an icon yet gets a faceted crystal drawn in code instead.

const SHADER: Shader = preload("res://assets/shaders/ore_badge.gdshader")
## Edge length of the icon, in the card's pixels (a bit taller than the body text).
const ICON_SIZE: float = 32.0
## Edge length of the drawn fallback icon's texture.
const FALLBACK_SIZE: int = 96

## The fallback icon, made once.
static var _fallback: ImageTexture

## The item shown, or null.
var item: ItemType:
	set(value):
		item = value
		_update()
## Shows its name next to the icon.
var show_name: bool = true:
	set(value):
		show_name = value
		_update()

var _icon := TextureRect.new()
var _name := Label.new()
var _material := ShaderMaterial.new()


func _init(shown: ItemType = null, with_name: bool = true) -> void:
	add_theme_constant_override(&"separation", 4)
	_material.shader = SHADER
	_icon.material = _material
	_icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# The icons are big; mipmaps keep them clean this small.
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_icon)
	# Translated in `_update` (also when the language changes).
	_name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(_name)
	show_name = with_name
	item = shown


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_update()


## The icon's material (tint and glow pattern of the shown ore).
func get_icon_material() -> ShaderMaterial:
	return _material


## The texture the icon shows: the ore's icon, or the drawn fallback.
func get_icon_texture() -> Texture2D:
	return _icon.texture


## The name shown ("" without one).
func get_shown_name() -> String:
	return _name.text if _name.visible else ""


func _update() -> void:
	visible = item != null
	if not item:
		return
	_icon.texture = item.icon if item.icon else fallback_icon()
	_material.set_shader_parameter(&"color", item.color)
	_material.set_shader_parameter(&"glow", int(item.glow))
	_material.set_shader_parameter(&"dark_body", item.dark_body)
	_name.visible = show_name
	_name.text = item.get_display_name()


## A crystal for ores without an icon: a kite of four grey facets on transparent, like the icons
## (white silhouette, grey facets), so the shader tints it the same way.
static func fallback_icon() -> Texture2D:
	if _fallback:
		return _fallback
	var image := Image.create_empty(FALLBACK_SIZE, FALLBACK_SIZE, false, Image.FORMAT_RGBA8)
	for y: int in FALLBACK_SIZE:
		for x: int in FALLBACK_SIZE:
			# 4x4 samples per pixel for smooth edges.
			var covered: int = 0
			var shade: float = 0.0
			for sample: int in 16:
				@warning_ignore("integer_division")
				var at := Vector2(x + (sample % 4 + 0.5) / 4.0, y + (sample / 4 + 0.5) / 4.0)
				var facet: float = _facet_shade(at / FALLBACK_SIZE * 2.2 - Vector2(1.1, 1.1))
				if facet > 0.0:
					covered += 1
					shade += facet
			if covered > 0:
				shade /= covered
				image.set_pixel(x, y, Color(shade, shade, shade, covered / 16.0))
	image.generate_mipmaps()
	_fallback = ImageTexture.create_from_image(image)
	return _fallback


## Grey of the fallback crystal's facet at `p` (-1.1..1.1 both ways), 0 outside: corners top
## (0, -1), sides (+-0.55, -0.2), bottom (0, 1); lit from the upper left.
static func _facet_shade(p: Vector2) -> float:
	var waist: float = -0.2
	var upper: bool = p.y < waist
	var span: float = (waist + 1.0) if upper else (1.0 - waist)
	var tip_distance: float = (p.y + 1.0) if upper else (1.0 - p.y)
	if tip_distance < 0.0 or absf(p.x) > 0.55 * tip_distance / span:
		return 0.0
	if upper:
		return 1.0 if p.x < 0.0 else 0.78
	return 0.62 if p.x < 0.0 else 0.45
