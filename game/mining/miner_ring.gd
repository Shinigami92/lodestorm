class_name MinerRing
extends MeshInstance3D
## The ring a miner projects on the ground around itself (a child of it; see
## docs/design/mining.md), always shown: the health arc on the screen's left (green, amber below
## half, red below a quarter, and empty with a blinking red outline while broken), the tank's fill
## arc on its right in the ore's color (white when full), both filling from the bottom up, and a
## thin dashed circle at its hose range (solid while the hose is connected). While it's placed or
## picked up, a thin band inside the arcs goes around with the progress in the hologram's color;
## while that waits for its player to come back into the range, the band and the circle blink. Like
## the suit ring, its halves stay fixed to the screen and it's drawn over the ground and low plants,
## hidden by cliffs and props.

## How far the arcs reach beyond the miner's body (m), and how wide they are. TBD (playtest).
const ARC_GAP: float = 0.25
const ARC_WIDTH: float = 0.2
## The progress band: its gap inside the arcs and its width (m).
const PROGRESS_GAP: float = 0.08
const PROGRESS_WIDTH: float = 0.07
## Length of one dash of the range circle and its gap (m).
const DASH_LENGTH: float = 0.7
const FILL_ALPHA: float = 0.9
const RANGE_COLOR := Color(0.6, 0.85, 1.0, 0.45)
const RANGE_CONNECTED := Color(0.6, 0.85, 1.0, 0.75)
const COLOR_FULL := Color(1.0, 1.0, 1.0, FILL_ALPHA)
## The hologram's color (see `miner_hologram.gdshader`).
const PROGRESS_COLOR := Color(0.3, 0.85, 1.0, FILL_ALPHA)
## Brightness of a blinking line between its blinks.
const BLINK_DIM: float = 0.25

var _material := ShaderMaterial.new()

@onready var _miner: Miner = get_parent() as Miner


func _ready() -> void:
	var range_radius: float = _miner.hose_range()
	var arc_outer: float = _miner.body_radius + ARC_GAP + ARC_WIDTH
	var outer: float = maxf(range_radius, arc_outer) + 0.1
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * outer * 2.0
	mesh = plane
	_material.shader = preload("res://assets/shaders/miner_ring.gdshader")
	_material.set_shader_parameter(&"radius", outer)
	_material.set_shader_parameter(&"arc_band", Vector2(arc_outer - ARC_WIDTH, arc_outer))
	var progress_outer: float = arc_outer - ARC_WIDTH - PROGRESS_GAP
	_material.set_shader_parameter(
		&"progress_band", Vector2(progress_outer - PROGRESS_WIDTH, progress_outer)
	)
	_material.set_shader_parameter(&"progress_color", PROGRESS_COLOR)
	_material.set_shader_parameter(&"range_radius", range_radius)
	_material.set_shader_parameter(
		&"range_dashes", maxi(roundi(TAU * range_radius / DASH_LENGTH), 8)
	)
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	layers = RenderLayers.MARKINGS
	position.y = 0.05


func _process(_delta: float) -> void:
	var blink_on: bool = fmod(Time.get_ticks_msec() * 0.001 * SuitLight.BLINK_RATE, 1.0) < 0.5
	var health_share: float = _miner.health / _miner.max_health()
	var health_color: Color = SuitLight.COLOR_HEALTHY
	if _miner.broken:
		health_color = SuitLight.COLOR_CRITICAL
		if not blink_on:
			health_color = health_color.darkened(1.0 - BLINK_DIM)
	elif health_share < 0.25:
		health_color = SuitLight.COLOR_CRITICAL
	elif health_share < 0.5:
		health_color = SuitLight.COLOR_HURT
	_material.set_shader_parameter(&"health_fill", health_share)
	_material.set_shader_parameter(&"health_color", Color(health_color, FILL_ALPHA))
	_material.set_shader_parameter(&"tank_fill", _miner.amount / _miner.capacity())
	if _miner.is_full():
		_material.set_shader_parameter(&"tank_color", COLOR_FULL)
	elif _miner.ore_type:
		_material.set_shader_parameter(&"tank_color", Color(_miner.ore_type.color, FILL_ALPHA))

	var handled: bool = not _miner.is_standing()
	var waiting: bool = _miner.paused and not blink_on
	var progress_alpha: float = 0.0
	if handled:
		progress_alpha = BLINK_DIM if waiting else 1.0
	_material.set_shader_parameter(&"progress_alpha", progress_alpha)
	_material.set_shader_parameter(&"progress", _miner.built)
	var connected: bool = _miner.hose_target != null
	var range_color: Color = RANGE_CONNECTED if connected else RANGE_COLOR
	if waiting:
		range_color.a *= BLINK_DIM
	_material.set_shader_parameter(&"range_solid", 1.0 if connected else 0.0)
	_material.set_shader_parameter(&"range_color", range_color)
	_face_screen()


## The value of shader parameter `param` it shows.
func shown(param: StringName) -> Variant:
	return _material.get_shader_parameter(param)


## Its top at the top of the screen, flat on the ground.
func _face_screen() -> void:
	var forward: Vector3 = SuitRing.screen_up(get_viewport().get_camera_3d())
	global_basis = Basis.looking_at(forward, Vector3.UP)
