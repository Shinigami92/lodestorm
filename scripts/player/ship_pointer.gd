class_name ShipPointer
extends Node3D
## An arrow on the ground around the player that points to the nearest ship's door once the
## player is outside and farther away than `min_distance`, in the ship's status color (blinking
## in the warning time). Next to its tip, the ship's countdown shows the exact time left. Shows the
## way back and how urgent it is while the ship is off-screen.

## Distance to the door (horizontally, in m) below which the arrow hides. TBD (playtest).
@export var min_distance: float = 12.0

## The ship the arrow points to, or null.
var target: Ship

var _material := StandardMaterial3D.new()

@onready var _arrow: MeshInstance3D = $Arrow
@onready var _countdown: Label3D = $Countdown


func _ready() -> void:
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# A projection on the ground: stays visible when it points behind the player's body.
	_material.no_depth_test = true
	_arrow.material_override = _material
	visible = false


func _physics_process(_delta: float) -> void:
	target = Ship.nearest(get_tree(), global_position)
	var to_ship := Vector3.ZERO
	var player := get_parent() as Player
	if target and not (player and target.is_aboard(player)):
		to_ship = target.get_boarding_position() - global_position
		to_ship.y = 0.0
	visible = to_ship.length() > min_distance
	if visible:
		# Runs after the player turned this tick, so the arrow keeps pointing at the ship.
		global_basis = Basis(Vector3.UP, atan2(-to_ship.x, -to_ship.z))


func _process(_delta: float) -> void:
	if visible and target:
		_material.albedo_color = Color(target.status_color, 0.3 + 0.6 * target.status_brightness)
		_countdown.text = target.countdown_text
		# Blinks less than the arrow, so the time stays readable.
		_countdown.modulate = Color(target.status_color, 0.6 + 0.4 * target.status_brightness)
