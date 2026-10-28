class_name LateDeposit
extends Node3D
## The late deposit (see docs/design/missions.md, Reasons to move and to stay): once per run, at
## `at` of the timer (drawn when the location is generated, between `TIMES`), a meteor comes down
## in a far area, a streak crossing the local player's view from the sky towards it (`fall`). On
## impact a boom is heard everywhere and the view trembles, a beam in the ore's color rises from
## the impact for `BEAM_TIME` (tall, so it shows over the cliffs), the pilot calls in on the radio
## (`GameEvents.deposit_landed`) and the nest nearest to it sends a pack at once
## (`AlienNest.surge`). Its crater is carved from the start; its part (`part`, the meteorite)
## waits hidden, without collision and off the location hologram, and its ore nodes (`ore_nodes`,
## the region's signature ore, holding double) wait outside the tree until the impact. The walkable
## area is baked with the meteorite's place already left out (an obstacle per collider), so the
## ground and the navigation never change mid-run. It stands at the impact site, in the location.
## All values greybox, TBD (playtest).

enum State { WAITING, FALLING, LANDED }

const GROUP: StringName = &"late_deposits"
## When it comes, as a share of the timer (`Mission.progress`): earliest, latest.
const TIMES: Vector2 = Vector2(0.55, 0.75)
## How long the meteor takes from the sky to the ground, in s. It starts this high above the local
## player and this far ahead of them in the camera's view, in m (near the top of the screen).
const FALL_TIME: float = 2.5
const FALL_HEIGHT: float = 12.0
const FALL_AHEAD: float = 28.0
## The meteor: its radius and the length of its trail, in m; its glow.
const METEOR_RADIUS: float = 0.6
const TRAIL_LENGTH: float = 14.0
const METEOR_COLOR := Color(1.0, 0.7, 0.4)
## The beam: how long it stands, how long it takes to fade in and out (s), its height and radius,
## in m, and how bright it is at its foot (it fades out towards its top).
const BEAM_TIME: float = 30.0
const BEAM_FADE: Vector2 = Vector2(0.4, 4.0)
const BEAM_HEIGHT: float = 120.0
const BEAM_RADIUS: float = 0.35
const BEAM_ALPHA: float = 0.6
## How hard the view trembles at the impact (m at zoom 1) and how long it takes to calm, in s.
const TREMOR: float = 0.6
const TREMOR_TIME: float = 1.5
const FALL_SOUND: Sound = preload("res://assets/audio/sfx/mission/meteor_fall.tres")
const IMPACT_SOUND: Sound = preload("res://assets/audio/sfx/mission/meteor_impact.tres")

## When it comes, as a share of the timer (`Mission.progress`).
var at: float = TIMES.x
## The meteorite's part: hidden until the impact.
var part: MapPart
## Its ore nodes, outside the tree until the impact, and where they go then.
var ore_nodes: Array[OreNode] = []
var ore_holder: Node3D
var state: State = State.WAITING

var _mission: Mission
## The colliders of the part, with their layers (none until the impact).
var _layers: Dictionary[CollisionObject3D, int] = {}
var _meteor: Node3D
var _fall_from: Vector3
var _fall_left: float = 0.0
var _beam: MeshInstance3D
var _beam_material := StandardMaterial3D.new()
var _beam_time: float = 0.0
var _tremor_left: float = 0.0


func _ready() -> void:
	add_to_group(GROUP)
	if not part:
		return
	part.visible = false
	part.remove_from_group(HoloTable.LANDMARK_GROUP)
	for node: Node in part.find_children("*", "CollisionObject3D", true, false):
		var body := node as CollisionObject3D
		_layers[body] = body.collision_layer
		body.collision_layer = 0
	for node: Node in part.find_children("*", "CollisionShape3D", true, false):
		add_child(_obstacle(node as CollisionShape3D))


func _notification(what: int) -> void:
	# The ore nodes that never came down were never in the tree.
	if what == NOTIFICATION_PREDELETE:
		for node: OreNode in ore_nodes:
			if is_instance_valid(node) and not node.get_parent():
				node.free()


func _physics_process(delta: float) -> void:
	match state:
		State.WAITING:
			if _find_mission() and _mission.state == Mission.State.RUNNING:
				if _mission.progress() >= at:
					fall()
		State.FALLING:
			_fall_left -= delta
			if _fall_left <= 0.0:
				_land()


func _process(delta: float) -> void:
	match state:
		State.FALLING:
			_move_meteor()
		State.LANDED:
			_update_beam(delta)
			if _tremor_left > 0.0:
				_tremor_left = maxf(_tremor_left - delta, 0.0)
				var rig := get_tree().get_first_node_in_group(IsoCameraRig.GROUP) as IsoCameraRig
				if rig:
					rig.tremble(TREMOR * _tremor_left / TREMOR_TIME)


## Brings the meteor down now (once): the streak, then the impact after `FALL_TIME`.
func fall() -> void:
	if state != State.WAITING:
		return
	state = State.FALLING
	_fall_left = FALL_TIME
	_fall_from = _fall_start()
	_meteor = _make_meteor()
	add_child(_meteor)
	_move_meteor()
	_play(FALL_SOUND)


## Whether the meteor came down.
func has_landed() -> bool:
	return state == State.LANDED


## The beam rising from the impact, while it stands (null before the impact and after).
func get_beam() -> MeshInstance3D:
	return _beam


## The ore its nodes hold (null without any).
func get_ore() -> OreType:
	return ore_nodes[0].ore_type if not ore_nodes.is_empty() else null


func _land() -> void:
	state = State.LANDED
	if _meteor:
		_meteor.queue_free()
		_meteor = null
	if part:
		part.visible = true
		part.add_to_group(HoloTable.LANDMARK_GROUP)
		for body: CollisionObject3D in _layers:
			body.collision_layer = _layers[body]
	for node: OreNode in ore_nodes:
		if ore_holder:
			ore_holder.add_child(node)
		else:
			add_child(node)
	var ore: OreType = get_ore()
	_beam = _make_beam(ore.color if ore else METEOR_COLOR)
	add_child(_beam)
	_tremor_left = TREMOR_TIME
	_play(IMPACT_SOUND)
	GameEvents.bus.deposit_landed.emit(global_position)
	var nest: AlienNest = _nearest_nest()
	if nest:
		nest.surge()


## Where the meteor starts: high up ahead of the local player in the camera's view, so it crosses
## the screen towards the impact (showing the way); high above the impact without a viewer.
func _fall_start() -> Vector3:
	var viewer: Player = Player.first_local(get_tree())
	var rig := get_tree().get_first_node_in_group(IsoCameraRig.GROUP) as IsoCameraRig
	if not viewer or not rig:
		return global_position + Vector3(FALL_AHEAD, FALL_HEIGHT, 0.0)
	var ahead: Vector3 = rig.view_direction()
	ahead.y = 0.0
	if ahead.length() < 0.01:
		ahead = Vector3.FORWARD
	return viewer.global_position + ahead.normalized() * FALL_AHEAD + Vector3.UP * FALL_HEIGHT


func _move_meteor() -> void:
	if not _meteor:
		return
	var done: float = 1.0 - clampf(_fall_left / FALL_TIME, 0.0, 1.0)
	_meteor.global_position = _fall_from.lerp(global_position, done)
	var heading: Vector3 = (global_position - _fall_from).normalized()
	var up: Vector3 = Vector3.UP if absf(heading.y) < 0.99 else Vector3.RIGHT
	_meteor.global_basis = Basis.looking_at(heading, up)


func _make_meteor() -> Node3D:
	var meteor := Node3D.new()
	meteor.name = "Meteor"
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = METEOR_COLOR
	var core := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = METEOR_RADIUS
	sphere.height = METEOR_RADIUS * 2.0
	core.mesh = sphere
	core.material_override = glow
	meteor.add_child(core)
	# The trail behind it (+z: it looks along -z), fading out.
	var trail := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.05
	cone.bottom_radius = METEOR_RADIUS * 0.9
	cone.height = TRAIL_LENGTH
	trail.mesh = cone
	var fade := StandardMaterial3D.new()
	fade.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fade.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fade.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fade.albedo_color = Color(METEOR_COLOR, 0.8)
	fade.albedo_texture = _fade_texture()
	trail.material_override = fade
	trail.transform = Transform3D(
		Basis(Vector3.RIGHT, PI * 0.5), Vector3.BACK * (TRAIL_LENGTH * 0.5 + METEOR_RADIUS * 0.5)
	)
	meteor.add_child(trail)
	var light := OmniLight3D.new()
	light.light_color = METEOR_COLOR
	light.light_energy = 4.0
	light.omni_range = 40.0
	meteor.add_child(light)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	RenderLayers.put(meteor, RenderLayers.EFFECTS)
	return meteor


func _make_beam(color: Color) -> MeshInstance3D:
	var beam := MeshInstance3D.new()
	beam.name = "Beam"
	var mesh := CylinderMesh.new()
	mesh.top_radius = BEAM_RADIUS
	mesh.bottom_radius = BEAM_RADIUS
	mesh.height = BEAM_HEIGHT
	mesh.radial_segments = 16
	mesh.rings = 1
	mesh.cap_top = false
	mesh.cap_bottom = false
	beam.mesh = mesh
	_beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam_material.albedo_color = Color(color, 0.0)
	_beam_material.albedo_texture = _fade_texture()
	beam.material_override = _beam_material
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position = Vector3.UP * BEAM_HEIGHT * 0.5
	RenderLayers.put(beam, RenderLayers.EFFECTS)
	_beam_time = 0.0
	return beam


## Clear at a cylinder's top, full at its bottom (its v runs from the top down): the beam fading
## out upwards, the trail behind the meteor.
static func _fade_texture() -> GradientTexture2D:
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	fade.set_color(1, Color.WHITE)
	var texture := GradientTexture2D.new()
	texture.gradient = fade
	texture.fill_from = Vector2.ZERO
	texture.fill_to = Vector2.DOWN
	texture.width = 4
	texture.height = 64
	return texture


## Fades the beam in, holds it and fades it out over `BEAM_TIME`, then drops it.
func _update_beam(delta: float) -> void:
	if not _beam:
		return
	_beam_time += delta
	if _beam_time >= BEAM_TIME:
		_beam.queue_free()
		_beam = null
		return
	var fading_in: float = clampf(_beam_time / BEAM_FADE.x, 0.0, 1.0)
	var fading_out: float = clampf((BEAM_TIME - _beam_time) / BEAM_FADE.y, 0.0, 1.0)
	_beam_material.albedo_color.a = BEAM_ALPHA * minf(fading_in, fading_out)


## An obstacle in the walkable area's bake where `shape` stands (its box around it, seen from
## above), so the area is baked with the meteorite already there.
func _obstacle(shape: CollisionShape3D) -> NavigationObstacle3D:
	var obstacle := NavigationObstacle3D.new()
	obstacle.avoidance_enabled = false
	obstacle.affect_navigation_mesh = true
	var box: AABB = shape.global_transform * shape.shape.get_debug_mesh().get_aabb()
	obstacle.position = to_local(Vector3(box.get_center().x, box.position.y, box.get_center().z))
	obstacle.height = box.size.y
	var half: Vector2 = Vector2(box.size.x, box.size.z) * 0.5
	obstacle.vertices = PackedVector3Array(
		[
			Vector3(-half.x, 0.0, -half.y),
			Vector3(half.x, 0.0, -half.y),
			Vector3(half.x, 0.0, half.y),
			Vector3(-half.x, 0.0, half.y),
		]
	)
	return obstacle


func _nearest_nest() -> AlienNest:
	var nearest: AlienNest = null
	var nearest_distance: float = INF
	for nest: AlienNest in get_tree().get_nodes_in_group(AlienNest.GROUP):
		var offset: Vector3 = nest.global_position - global_position
		var distance: float = Vector2(offset.x, offset.z).length()
		if distance < nearest_distance:
			nearest = nest
			nearest_distance = distance
	return nearest


## Plays `sound` where the local player hears it (heard everywhere).
func _play(sound: Sound) -> void:
	var listener: Player = Player.first_local(get_tree())
	Sfx.play_at(sound, listener.global_position if listener else global_position)


func _find_mission() -> bool:
	if not _mission:
		_mission = get_tree().get_first_node_in_group(Mission.GROUP) as Mission
	return _mission != null
