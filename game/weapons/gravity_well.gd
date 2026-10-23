class_name GravityWell
extends Node3D
## A gravity well (Nadir's, see `WellDelivery`): every alien within its radius, with no rock in
## between, is pulled to its middle (lighter strains faster: `AlienStrain.knockback`) and held
## there for `hold_time` seconds (see `AlienStatus.hold`: no walking, no leaps, charges or dives,
## fliers sink low; the apex is only slowed). Then it bursts (`Blast`: the weapon's hit, nests in
## reach too, no push, so the clump stays together a moment). Players and miners are never
## affected. One per player: a new one bursts their last one. Shows a dark core with a warm glow,
## rings drawn inwards and its edge on the ground, flickering faster before it bursts, and hums.
## Greybox look, values TBD (playtest).

const GROUP: StringName = &"gravity_wells"
## How fast an alien is pulled per m from the middle (1/s), and at most (m/s); within `CORE` m of
## the middle it isn't pulled any more.
const PULL_GAIN: float = 4.0
const MAX_PULL: float = 12.0
const CORE: float = 0.6
## Seconds before the burst it starts flickering faster.
const WARNING: float = 1.0
## Seconds a ring takes to be drawn from the edge to the middle; how many there are.
const RING_TIME: float = 0.7
const RINGS: int = 3
const COLOR := Color(1.0, 0.72, 0.3)

## Its radius (m), its hit when it bursts, and how long it holds (s).
var radius: float = 5.0
var hit: Hit
var hold_time: float = 3.0
## Who opened it.
var opener: Node
var burst_sound: Sound
var hum_sound: Sound

var _elapsed: float = 0.0
var _burst: bool = false
var _hum: AudioStreamPlayer3D
var _core_material := StandardMaterial3D.new()
var _glow_material := StandardMaterial3D.new()
var _ring_material := StandardMaterial3D.new()
var _glow: MeshInstance3D
var _edge: MeshInstance3D
var _rings: Array[MeshInstance3D] = []
var _light: OmniLight3D


## A well of `well_radius` m at `center` (global) in `parent`, opened by `who` (their last one
## bursts), holding for `seconds` and bursting with `burst_hit`.
static func open(
	parent: Node,
	center: Vector3,
	well_radius: float,
	burst_hit: Hit,
	seconds: float,
	who: Node,
	sound: Sound = null,
	hum: Sound = null
) -> GravityWell:
	for well: GravityWell in opened_by(who):
		well.burst()
	var well := GravityWell.new()
	well.radius = well_radius
	well.hit = burst_hit
	well.hold_time = seconds
	well.opener = who
	well.burst_sound = sound
	well.hum_sound = hum
	parent.add_child(well)
	well.global_transform = Transform3D(Basis.IDENTITY, center)
	return well


## The wells `who` has open.
static func opened_by(who: Node) -> Array[GravityWell]:
	var wells: Array[GravityWell] = []
	if not who or not who.is_inside_tree():
		return wells
	for node: Node in who.get_tree().get_nodes_in_group(GROUP):
		var well := node as GravityWell
		if well.opener == who and not well._burst:
			wells.append(well)
	return wells


func _ready() -> void:
	add_to_group(GROUP)
	for material: StandardMaterial3D in [_core_material, _glow_material, _ring_material]:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_core_material.albedo_color = Color(0.02, 0.015, 0.01, 0.95)
	_glow_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_ring_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_add_sphere(0.35, _core_material)
	_glow = _add_sphere(0.6, _glow_material)
	_edge = _add_ring(1.0)
	for i: int in RINGS:
		_rings.append(_add_ring(1.0))
	_light = OmniLight3D.new()
	_light.light_color = COLOR
	_light.omni_range = radius * 1.5
	_light.position = Vector3.UP * 0.8
	add_child(_light)
	if hum_sound:
		_hum = Sfx.play_loop_at(hum_sound, self)
	_update()
	RenderLayers.put(self, RenderLayers.EFFECTS)


func _physics_process(delta: float) -> void:
	if _burst:
		return
	_elapsed += delta
	if _elapsed >= hold_time:
		burst()
		return
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var middle: Vector3 = global_position + Vector3.UP * 0.5
	for node: Node in get_tree().get_nodes_in_group(Alien.GROUP):
		var alien := node as Alien
		if not alien.is_hittable():
			continue
		var offset: Vector3 = global_position - alien.global_position
		if absf(offset.y) > radius:
			continue
		offset.y = 0.0
		var distance: float = offset.length()
		if distance > radius:
			continue
		if not WeaponDelivery.is_clear(space, middle, alien.get_aim_point(), []):
			continue
		var pull := Vector3.ZERO
		if alien.strain.held_by_wells and distance > CORE:
			var speed: float = minf(distance * PULL_GAIN, MAX_PULL)
			pull = offset / distance * speed * clampf(alien.strain.knockback, 0.0, 1.0)
		alien.status.hold(pull)


func _process(_delta: float) -> void:
	if not _burst:
		_update()


## Bursts now: the blast, and it's gone.
func burst() -> void:
	if _burst:
		return
	_burst = true
	remove_from_group(GROUP)
	Sfx.stop_loop(_hum)
	_hum = null
	if is_inside_tree():
		Blast.explode(get_parent(), global_position, radius, hit, burst_sound)
	queue_free()


func _update() -> void:
	var left: float = hold_time - _elapsed
	var rate: float = 18.0 if left < WARNING else 5.0
	var flicker: float = 0.75 + 0.25 * sin(_elapsed * rate)
	var glow: Color = COLOR * 2.0
	glow.a = 0.45 * flicker
	_glow_material.albedo_color = glow
	_glow.scale = Vector3.ONE * lerpf(0.9, 1.15, flicker)
	_light.light_energy = 2.0 * flicker
	_edge.scale = Vector3(radius, 0.15, radius)
	_ring_material.albedo_color = Color(COLOR * 1.6, 0.6)
	for i: int in RINGS:
		var t: float = fmod(_elapsed / RING_TIME + float(i) / RINGS, 1.0)
		var size: float = lerpf(radius, CORE, t)
		_rings[i].scale = Vector3(size, 0.15, size)
		_rings[i].transparency = t * t


func _add_sphere(size: float, material: StandardMaterial3D) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = size
	sphere.height = size * 2.0
	sphere.radial_segments = 16
	sphere.rings = 8
	sphere.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = sphere
	instance.position = Vector3.UP * 0.8
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance


## A thin ring of radius 1 on the ground, scaled to its size.
func _add_ring(size: float) -> MeshInstance3D:
	var torus := TorusMesh.new()
	torus.outer_radius = size
	torus.inner_radius = size - 0.03
	torus.rings = 40
	torus.ring_segments = 4
	torus.material = _ring_material
	var instance := MeshInstance3D.new()
	instance.mesh = torus
	instance.position = Vector3.UP * 0.08
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance
