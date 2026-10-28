class_name ShipPointer
extends RingPointer
## Points to the nearest ship's door once the local player is outside and farther away than
## `min_distance`: the suit ring draws it as the largest arrow on its edge in `color`, the ship's
## status color (blinking in the warning time). Beyond the arrow's tip, the ship's countdown shows
## the exact time left, shrinking as the camera moves in (e.g. to frame the pause panel), so it
## keeps its size on screen. Shows the way back and how urgent it is while the ship is off-screen.
## Docked at a station there's no time to show: only the arrow.

## Distance to the door (horizontally, in m) below which the arrow hides. TBD (playtest).
@export var min_distance: float = 12.0

## The ship the arrow points to, or null.
var target: Ship

@onready var _countdown: Label3D = $Countdown


func _init() -> void:
	arrow = Vector2(SuitRing.MAX_ARROW, 0.38)
	priority = 0


func _ready() -> void:
	visible = false
	# Runs on while the pause panel stops the world, which frames the countdown beside the ring.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _physics_process(_delta: float) -> void:
	target = Ship.nearest(get_tree(), global_position)
	var to_ship := Vector3.ZERO
	if target and holder and holder.local and not target.is_aboard(holder):
		to_ship = target.get_boarding_position() - global_position
		to_ship.y = 0.0
	visible = to_ship.length() > min_distance
	if visible:
		# Runs after the player turned this tick, so the arrow keeps pointing at the ship.
		point_along(to_ship)


func _process(_delta: float) -> void:
	if not visible or not target:
		return
	# Its alpha blinks with the ship's status light.
	color = Color(target.status_color, 0.3 + 0.6 * target.status_brightness)
	_countdown.text = target.countdown_text
	_countdown.visible = not target.flight.is_docked()
	_countdown.scale = Vector3.ONE * _zoom()
	# Blinks less than the arrow, so the time stays readable.
	_countdown.modulate = Color(target.status_color, 0.6 + 0.4 * target.status_brightness)
	var ring := holder.get_node_or_null(^"SuitRing") as SuitRing if holder else null
	if ring:
		var distance: float = ring.pointer_reach(arrow.x) + SuitRing.COUNTDOWN_GAP + _half_extent()
		_countdown.position = Vector3(0.0, _countdown.position.y, -distance)


## The corners of the countdown's text as the camera sees it (global), none while it hides.
func countdown_corners() -> PackedVector3Array:
	var corners := PackedVector3Array()
	var camera: Camera3D = get_viewport().get_camera_3d()
	if not camera or not is_visible_in_tree():
		return corners
	var view: Basis = camera.global_basis.orthonormalized()
	var half: Vector2 = _countdown_size() * 0.5
	for side: Vector2 in [Vector2(-1.0, -1.0), Vector2(1.0, -1.0), Vector2(-1.0, 1.0), Vector2.ONE]:
		corners.append(
			_countdown.global_position + view.x * side.x * half.x + view.y * side.y * half.y
		)
	return corners


## How far the countdown's text reaches from its center towards the player on the ground (m), so
## a long text ("No mission") beside the arrow doesn't cover the ring.
func _half_extent() -> float:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if not camera:
		return 0.0
	var size: Vector2 = _countdown_size()
	var right: Vector3 = Vector3(camera.global_basis.x.x, 0.0, camera.global_basis.x.z).normalized()
	var up := Vector3(-camera.global_basis.z.x, 0.0, -camera.global_basis.z.z)
	# The screen's up runs along the ground foreshortened by the camera's tilt.
	var tilt: float = maxf(absf(camera.global_basis.z.y), 0.3)
	up = up.normalized()
	var direction: Vector3 = -global_basis.z
	return absf(direction.dot(right)) * size.x * 0.5 + absf(direction.dot(up)) * size.y * 0.5 / tilt


## How close the camera following its player is (`IsoCameraRig.zoom`; 1 without one).
func _zoom() -> float:
	for rig: IsoCameraRig in get_tree().get_nodes_in_group(IsoCameraRig.GROUP):
		if rig.target == holder:
			return rig.zoom
	return 1.0


## The countdown's text size (m).
func _countdown_size() -> Vector2:
	var font: Font = _countdown.font if _countdown.font else ThemeDB.fallback_font
	var text: String = _countdown.text.to_upper() if _countdown.uppercase else _countdown.text
	return (
		font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _countdown.font_size)
		* _countdown.pixel_size
		* _countdown.scale.x
	)
