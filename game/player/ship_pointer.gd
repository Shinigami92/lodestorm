class_name ShipPointer
extends Node3D
## Points to the nearest ship's door once the local player is outside and farther away than
## `min_distance`: its -Z turns towards the door, and the suit ring draws it as an arrow on its
## edge in `color`, the ship's status color (blinking in the warning time). Beyond the arrow's tip,
## the ship's countdown shows the exact time left. Shows the way back and how urgent it is while
## the ship is off-screen.

## Distance to the door (horizontally, in m) below which the arrow hides. TBD (playtest).
@export var min_distance: float = 12.0

## The ship the arrow points to, or null.
var target: Ship
## The arrow's color (its alpha blinks with the ship's status light).
var color := Color.WHITE

@onready var _countdown: Label3D = $Countdown


func _ready() -> void:
	visible = false


func _physics_process(_delta: float) -> void:
	target = Ship.nearest(get_tree(), global_position)
	var to_ship := Vector3.ZERO
	var player := get_parent() as Player
	if target and player and player.local and not target.is_aboard(player):
		to_ship = target.get_boarding_position() - global_position
		to_ship.y = 0.0
	visible = to_ship.length() > min_distance
	if visible:
		# Runs after the player turned this tick, so the arrow keeps pointing at the ship.
		global_basis = Basis(Vector3.UP, atan2(-to_ship.x, -to_ship.z))


func _process(_delta: float) -> void:
	if not visible or not target:
		return
	color = Color(target.status_color, 0.3 + 0.6 * target.status_brightness)
	_countdown.text = target.countdown_text
	# Blinks less than the arrow, so the time stays readable.
	_countdown.modulate = Color(target.status_color, 0.6 + 0.4 * target.status_brightness)
	var ring := get_parent().get_node_or_null(^"SuitRing") as SuitRing
	if ring:
		var distance: float = ring.pointer_reach() + SuitRing.COUNTDOWN_GAP + _half_extent()
		_countdown.position = Vector3(0.0, _countdown.position.y, -distance)


## How far the countdown's text reaches from its center towards the player on the ground (m), so
## a long text ("No mission") beside the arrow doesn't cover the ring.
func _half_extent() -> float:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if not camera:
		return 0.0
	var font: Font = _countdown.font if _countdown.font else ThemeDB.fallback_font
	var text: String = _countdown.text.to_upper() if _countdown.uppercase else _countdown.text
	var size: Vector2 = (
		font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _countdown.font_size)
		* _countdown.pixel_size
	)
	var right: Vector3 = Vector3(camera.global_basis.x.x, 0.0, camera.global_basis.x.z).normalized()
	var up := Vector3(-camera.global_basis.z.x, 0.0, -camera.global_basis.z.z)
	# The screen's up runs along the ground foreshortened by the camera's tilt.
	var tilt: float = maxf(absf(camera.global_basis.z.y), 0.3)
	up = up.normalized()
	var direction: Vector3 = -global_basis.z
	return absf(direction.dot(right)) * size.x * 0.5 + absf(direction.dot(up)) * size.y * 0.5 / tilt
