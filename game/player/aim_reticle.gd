class_name AimReticle
extends Node3D
## The in-game cursor (see docs/design/ui.md): a reticle projected onto the ground or a rock's top
## where the local player's mouse really points (`PlayerAim.cursor_point`), in the player's color,
## so it follows slopes; it leaves out what isn't ground (players, aliens, markings, effects: see
## `RenderLayers`).
## While it shows, the hardware cursor is hidden; it comes back while a menu or station is open, the
## game is paused, the player is down, the mouse is over a developer tool or points at no ground.
## Only with the mouse: a stick or a VR hand aims by a direction. With something locked on, it
## stays under the cursor, dimmed (or, with `follows_lock`, moves under the locked target). A child
## of the player. Greybox look, TBD (playtest).

## Its width on the ground (m).
const SIZE: float = 1.5
## How far up and down it reaches to find the ground (m).
const DEPTH: float = 4.0
## How strongly it shows, and how much while something is locked on.
const ALPHA: float = 1.0
const LOCKED_ALPHA: float = 0.3
## How strongly it glows.
const GLOW: float = 2.0
## Fades it out on steep surfaces (the side of a table, a cliff), where it would smear down: from
## 0.5 (walls hidden) to 1 (only flat ground). Slopes of 45° keep about 70 %.
const NORMAL_FADE: float = 0.6

## Shared by every reticle: the crosshair ring.
static var _texture: ImageTexture

## Whether it moves under the locked target instead of staying under the cursor.
@export var follows_lock: bool = false

var holder: Player

var _decal: Decal


func _ready() -> void:
	top_level = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not _texture:
		_texture = make_texture()
	_decal = Decal.new()
	_decal.name = "Decal"
	_decal.size = Vector3(SIZE, DEPTH, SIZE)
	_decal.texture_albedo = _texture
	_decal.texture_emission = _texture
	_decal.emission_energy = GLOW
	_decal.upper_fade = 0.0
	_decal.lower_fade = 0.0
	_decal.normal_fade = NORMAL_FADE
	_decal.cull_mask = RenderLayers.WORLD | RenderLayers.INTERIOR
	add_child(_decal)
	visible = false


func _process(_delta: float) -> void:
	var shown: bool = is_shown()
	visible = shown
	if holder and holder.local:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if shown else Input.MOUSE_MODE_VISIBLE
	if not shown:
		return
	var aim: PlayerAim = holder.aim
	var locked: bool = aim.target != null
	var point: Vector3 = aim.cursor_point
	if locked and follows_lock:
		point = aim.target.global_position
	_decal.modulate = holder.color()
	_decal.albedo_mix = LOCKED_ALPHA if locked and not follows_lock else ALPHA
	global_transform = Transform3D(Basis.IDENTITY, point)


func _exit_tree() -> void:
	if holder and holder.local:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Whether it shows (and the hardware cursor hides): the local player aims with the mouse at the
## ground, outside menus and pauses, alive and not over a developer tool.
func is_shown() -> bool:
	if not holder or not holder.local or holder.fallen or holder.menu or get_tree().paused:
		return false
	var aim: PlayerAim = holder.aim
	return aim.aims_with_mouse() and not aim.is_mouse_over_ui() and aim.cursor_point.is_finite()


## The crosshair ring: a thin ring with four ticks pointing in and a gap at each, and a dot in the
## middle, white on clear (the decal tints it).
static func make_texture() -> ImageTexture:
	var size: int = 128
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var middle: float = (size - 1) * 0.5
	for y: int in size:
		for x: int in size:
			var offset := Vector2(x - middle, y - middle) / middle
			var radius: float = offset.length()
			var axis: float = minf(absf(offset.x), absf(offset.y))
			var on_ring: bool = absf(radius - 0.82) < 0.08 and axis > 0.2
			var on_tick: bool = axis < 0.06 and radius > 0.4 and radius < 0.74
			var on_dot: bool = radius < 0.1
			if on_ring or on_tick or on_dot:
				image.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(image)
