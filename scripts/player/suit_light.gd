class_name SuitLight
extends MeshInstance3D
## A light band around the suit's collar that shows the player's health: green, amber below
## half, red and blinking below a quarter, dark once dead. Flashes white on damage, pulsing
## under steady damage (e.g. the storm).

const COLOR_HEALTHY := Color(0.3, 1.0, 0.45)
const COLOR_HURT := Color(1.0, 0.7, 0.15)
const COLOR_CRITICAL := Color(1.0, 0.2, 0.15)
const COLOR_DEAD := Color(0.12, 0.12, 0.12)
const COLOR_FLASH := Color(1.0, 1.0, 1.0)
## Blinks per second while critical.
const BLINK_RATE: float = 3.0
## Seconds a damage flash lasts.
const FLASH_DURATION: float = 0.12
## Seconds from one flash to the next under steady damage.
const FLASH_INTERVAL: float = 0.5

## The color for the health shown, without blinking and flashes.
var color: Color = COLOR_HEALTHY

var _ratio: float = 1.0
var _flash_left: float = 0.0
var _next_flash: float = 0.0
var _time: float = 0.0
var _material := StandardMaterial3D.new()


func _ready() -> void:
	_material.emission_enabled = true
	_material.emission_energy_multiplier = 2.0
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	show_health(_ratio)


func _process(delta: float) -> void:
	_time += delta
	_flash_left = maxf(_flash_left - delta, 0.0)
	_next_flash = maxf(_next_flash - delta, 0.0)
	var brightness: float = 1.0
	if color == COLOR_CRITICAL:
		brightness = 0.25 + 0.75 * absf(cos(_time * PI * BLINK_RATE))
	var shown: Color = COLOR_FLASH if _flash_left > 0.0 else color
	_material.albedo_color = shown
	_material.emission = shown * brightness if color != COLOR_DEAD else Color.BLACK


## Shows health as a ratio from 0 (dead) to 1 (unhurt).
func show_health(ratio: float) -> void:
	_ratio = ratio
	if ratio <= 0.0:
		color = COLOR_DEAD
		_flash_left = 0.0
	elif ratio <= 0.25:
		color = COLOR_CRITICAL
	elif ratio <= 0.5:
		color = COLOR_HURT
	else:
		color = COLOR_HEALTHY


## Flashes once, e.g. when taking damage; at most every `FLASH_INTERVAL`.
func flash() -> void:
	if _next_flash > 0.0 or color == COLOR_DEAD:
		return
	_flash_left = FLASH_DURATION
	_next_flash = FLASH_INTERVAL
