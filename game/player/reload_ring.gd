class_name ReloadRing
extends MeshInstance3D
## A ring on the ground around the player (a child of it) that shows a reload where it's easy to
## see while fighting, next to the gauge on the weapon: it fills clockwise from the top of the
## screen in the weapon's ammo color, with the timing window marked white (red after a press
## outside it); with single rounds it shows the round being loaded. It flashes white when a press
## hits the window and finishes the reload, red when a reload can't start (no ore), and fills
## green while the player hands a teammate ammo.

const RADIUS: float = 1.1
const FLASH_TIME: float = 0.35
const GIVE_COLOR := Color(0.35, 1.0, 0.45, 0.9)
const FUMBLE_COLOR := Color(1.0, 0.12, 0.08, 0.9)
const FILL_ALPHA: float = 0.9

var _material := ShaderMaterial.new()
var _flash_color := Color.WHITE
var _flash_left: float = 0.0

@onready var _player: Player = get_parent() as Player


func _ready() -> void:
	top_level = true
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * RADIUS * 2.0
	mesh = plane
	_material.shader = preload("res://assets/shaders/reload_ring.gdshader")
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false


## Flashes the whole ring in `color` for a moment.
func flash(color: Color) -> void:
	_flash_color = color
	_flash_left = FLASH_TIME


func _process(delta: float) -> void:
	_flash_left = maxf(_flash_left - delta, 0.0)
	var ranged := _player.weapon as RangedWeapon
	var shown: bool = true
	if _player.dead:
		shown = false
		_flash_left = 0.0
	elif ranged and ranged.reloading:
		var settings: RangedWeaponSettings = ranged.settings
		if ranged.fumbled:
			_show(ranged.reload_share(), FUMBLE_COLOR)
		else:
			_show(
				ranged.reload_share(),
				_ammo_color(ranged),
				settings.sweet_spot_start,
				settings.sweet_spot_start + settings.sweet_spot_width
			)
	elif _player.give_ammo_target:
		_show(_player.give_ammo_time / _player.settings.give_ammo_time, GIVE_COLOR)
	elif _flash_left > 0.0:
		var color := _flash_color
		color.a = FILL_ALPHA * _flash_left / FLASH_TIME
		_show(1.0, color)
	else:
		shown = false
	visible = shown
	if shown:
		global_position = _player.global_position + Vector3.UP * 0.05
		var camera: Camera3D = get_viewport().get_camera_3d()
		var forward := Vector3.FORWARD
		if camera:
			forward = -camera.global_basis.z
			forward.y = 0.0
		if forward.length() > 0.001:
			global_basis = Basis.looking_at(forward.normalized(), Vector3.UP)


func _show(
	progress: float, fill: Color, window_start: float = -1.0, window_end: float = -1.0
) -> void:
	_material.set_shader_parameter(&"progress", progress)
	_material.set_shader_parameter(&"fill_color", fill)
	_material.set_shader_parameter(&"window_start", window_start)
	_material.set_shader_parameter(&"window_end", window_end)


static func _ammo_color(weapon: RangedWeapon) -> Color:
	var gauge := weapon.get_node_or_null(^"AmmoGauge") as AmmoGauge
	var color: Color = gauge.color if gauge else Color.WHITE
	color.a = FILL_ALPHA
	return color
