class_name PlacedCharge
extends LobbedShot
## A proximity charge Wick tossed (see `ChargeDelivery`): it flies past aliens, settles on the
## ground where it lands and arms after `arm_time`. Once armed, an alien within `trigger_radius`
## trips it: it blinks for `trip_time` and blasts (see `Blast`). Players and miners never trip it.
## A faint ring in its layer's color shows how far it reaches; its light is on once armed, pulsing
## slowly, and flashes fast once tripped. It stays until it blasts, the mission ends, or its layer
## places one too many (`fizzle`). Its model is its scene's children, the light a child named
## `Light`.

const GROUP: StringName = &"placed_charges"
## Who stands this much higher or lower than the charge doesn't trip it (m).
const TRIGGER_HEIGHT: float = 2.5
## Seconds between looks for aliens close to it.
const CHECK_INTERVAL: float = 0.1
## Width of the ring showing its reach (m), and how strongly it shows.
const RING_WIDTH: float = 0.06
const RING_ALPHA: float = 0.35
## Pulses per second of the light while armed and once tripped, how long each pulse lasts (s) and
## how much bigger the light is during one.
const ARMED_BLINK: float = 0.7
const TRIPPED_BLINK: float = 8.0
const FLASH: float = 0.08
const FLASH_SCALE: float = 1.8

## How many charges were placed so far: the order they were placed in (`serial`).
static var _placed: int = 0

## Who placed it (a player): its charges count towards their limit.
var layer: Node
## An alien this close trips it (horizontally, m).
var trigger_radius: float = 2.5
## Seconds from landing until it's armed, and from tripping until it blasts.
var arm_time: float = 1.0
var trip_time: float = 0.35
## Played when it's armed and when it's tripped.
var arm_sound: Sound
var trip_sound: Sound
## Its layer's color: the ring showing its reach.
var color := Color.WHITE
## The order it was placed in: lower is older.
var serial: int = 0

var _arm_left: float = 0.0
var _trip_left: float = -1.0
var _check_left: float = 0.0
var _armed: bool = false
var _settled: bool = false
var _blink_time: float = 0.0
var _ring: MeshInstance3D

@onready var _light: Node3D = get_node_or_null(^"Light") as Node3D


func _init() -> void:
	through_aliens = true
	_placed += 1
	serial = _placed


func _ready() -> void:
	add_to_group(GROUP)
	if _light:
		_light.visible = false


func _physics_process(delta: float) -> void:
	if not _settled:
		super(delta)
		return
	if _trip_left >= 0.0:
		_trip_left -= delta
		if _trip_left < 0.0:
			Blast.explode(get_parent(), global_position, blast_radius, hit, blast_sound)
			queue_free()
		return
	if not _armed:
		_arm_left -= delta
		if _arm_left <= 0.0:
			_armed = true
			Sfx.play_at(arm_sound, global_position)
		return
	_check_left -= delta
	if _check_left <= 0.0:
		_check_left = CHECK_INTERVAL
		if _alien_close():
			trip()


func _process(delta: float) -> void:
	if not _light or not _settled:
		return
	_blink_time += delta
	var rate: float = TRIPPED_BLINK if is_tripped() else ARMED_BLINK
	_light.visible = _armed or is_tripped()
	var flash: bool = fmod(_blink_time * rate, 1.0) < FLASH * rate
	_light.scale = Vector3.ONE * (FLASH_SCALE if flash else 1.0)


## Whether it's on the ground and armed (not tripped yet).
func is_armed() -> bool:
	return _armed and not is_tripped()


func is_tripped() -> bool:
	return _trip_left >= 0.0


## Trips it: it blinks for `trip_time`, then blasts.
func trip() -> void:
	if is_tripped():
		return
	_trip_left = trip_time
	_blink_time = 0.0
	Sfx.play_at(trip_sound, global_position)


## Removes it without a blast (its layer placed one too many).
func fizzle() -> void:
	remove_from_group(GROUP)
	if is_inside_tree():
		DustPuff.spawn(get_parent(), global_position, 0.4)
	queue_free()


## Settles on the ground under `point` and starts arming.
func _land(point: Vector3) -> void:
	global_position = _ground_under(point)
	_settled = true
	_arm_left = arm_time
	_ring = _make_ring()
	add_child(_ring)


## The ground under `point`: the first rock or ground a ray down from just above it hits.
func _ground_under(point: Vector3) -> Vector3:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var skip: Array[RID] = exclude.duplicate()
	for _i: int in 8:
		var query := PhysicsRayQueryParameters3D.create(
			point + Vector3.UP * 0.5, point + Vector3.DOWN * 30.0, PhysicsLayers.WORLD
		)
		query.exclude = skip
		var result: Dictionary = space.intersect_ray(query)
		if result.is_empty():
			return point
		var collider: Object = result["collider"]
		if collider is Player or collider is Alien or collider is Miner:
			skip.append((collider as CollisionObject3D).get_rid())
			continue
		return result["position"]
	return point


func _alien_close() -> bool:
	for node: Node in get_tree().get_nodes_in_group(Alien.GROUP):
		var alien := node as Alien
		if not alien.is_hittable():
			continue
		var offset: Vector3 = alien.global_position - global_position
		if (
			absf(offset.y) <= TRIGGER_HEIGHT
			and Vector2(offset.x, offset.z).length() <= trigger_radius
		):
			return true
	return false


## The ring on the ground showing how far it reaches.
func _make_ring() -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color, RING_ALPHA)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var torus := TorusMesh.new()
	torus.outer_radius = trigger_radius
	torus.inner_radius = trigger_radius - RING_WIDTH
	torus.rings = 40
	torus.ring_segments = 4
	torus.material = material
	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	ring.mesh = torus
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.transform = Transform3D(Basis.from_scale(Vector3(1.0, 0.15, 1.0)), Vector3.UP * 0.05)
	return ring
