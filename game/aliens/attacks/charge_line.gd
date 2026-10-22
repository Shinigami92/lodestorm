class_name ChargeLine
extends Node3D
## A charge's telegraph on the ground (`AlienCharge`): the lane it will run along, `length` m along
## its -Z from where it stands and `width` to each side, as red dashed edges over a faint fill that
## grows from the alien to the end of the lane during the wind-up (`duration`), so it shows when the
## charge comes. Projected onto the ground (decals), so it follows slopes; players and aliens in it
## stay as they are (`RenderLayers.CHARACTERS`), and so do the suit's markings
## (`RenderLayers.MARKINGS`). Greybox look, TBD (playtest).

## The telegraphs' red (see `docs/planned/player-display.md`: alien telegraphs).
const COLOR := Color(1.0, 0.16, 0.1)
## How far the decals reach up and down to find the ground (m).
const DEPTH: float = 6.0
## How strongly the lane is filled in.
const FILL_ALPHA: float = 0.18
## How strongly the dashed edges show.
const EDGE_ALPHA: float = 0.85
## How strongly the dashed edges glow.
const EDGE_GLOW: float = 0.8
## Dashes per m along the edges.
const DASHES_PER_METER: float = 1.25

## Shared by all lines: the fill.
static var _fill: ImageTexture

var length: float = 10.0
var width: float = 1.3
var duration: float = 1.0

var _elapsed: float = 0.0
var _filling: Decal


func _ready() -> void:
	if not _fill:
		_fill = _texture(false)
	var outline := _decal(_texture(true), length)
	outline.name = "Edges"
	outline.texture_emission = outline.texture_albedo
	outline.emission_energy = EDGE_GLOW
	outline.albedo_mix = EDGE_ALPHA
	outline.position = Vector3(0.0, 0.0, -length * 0.5)
	add_child(outline)
	_filling = _decal(_fill, length)
	_filling.name = "Fill"
	_filling.albedo_mix = FILL_ALPHA
	add_child(_filling)
	_update_fill()


func _process(delta: float) -> void:
	_elapsed += delta
	_update_fill()


func _update_fill() -> void:
	var reach: float = maxf(length * clampf(_elapsed / duration, 0.0, 1.0), 0.05)
	_filling.size.z = reach
	_filling.position = Vector3(0.0, 0.0, -reach * 0.5)


func _decal(texture: Texture2D, along: float) -> Decal:
	var decal := Decal.new()
	decal.size = Vector3(width * 2.0, DEPTH, along)
	decal.texture_albedo = texture
	decal.modulate = COLOR
	decal.upper_fade = 0.0
	decal.lower_fade = 0.0
	decal.cull_mask = RenderLayers.WORLD
	return decal


## The dashed edges for its length, or a solid fill.
func _texture(dashed: bool) -> ImageTexture:
	var size := Vector2i(16, 128) if dashed else Vector2i(4, 4)
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var periods: int = maxi(roundi(length * DASHES_PER_METER), 1)
	for y: int in size.y:
		var on: bool = fmod(float(y) / size.y * periods, 1.0) < 0.55
		for x: int in size.x:
			var edge: bool = x < 2 or x >= size.x - 2
			# Black where it's off: the emission ignores the alpha.
			var lit: float = 1.0 if not dashed else (1.0 if edge and on else 0.0)
			image.set_pixel(x, y, Color(lit, lit, lit, lit))
	return ImageTexture.create_from_image(image)
