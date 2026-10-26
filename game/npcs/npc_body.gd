class_name NpcBody
extends Node3D
## Someone standing in the world (see GAME_DESIGN.md, Spaceship: NPCs), who `profile` says: their
## own model, or the suit model in their darker tint with the collar light in their own color (for
## those without one yet), playing its "Idle" and "Walk" (`NpcAnimator`), turning towards whom
## it `faces` (else the nearest player close by, else back to where it stands facing), and their
## name plate while a player is near (not while they use a menu). While `sitting` (on a seat behind
## where it stands), it doesn't turn, and its head (the plate, a speech bubble) is as low as the
## clip has it. The crew (`Npc`, which adds talking) and the station's ambient colonists
## (`Colonist`, which adds walking and sitting) share it.

## How close (in m) a player must be for it to turn towards them.
const NOTICE_RANGE: float = 3.0
## How close (in m) a player must be to see the name plate.
const PLATE_RANGE: float = 4.0
## How fast it turns (per s, smoothed).
const TURN_SPEED: float = 5.0
## Where the top of the suit's helmet is, in m above the feet.
const SUIT_HEAD_HEIGHT: float = 1.9
## How far above the head the name plate floats, in m.
const PLATE_ABOVE_HEAD: float = 0.2

## Who it is: the name plate and the suit's look.
@export var profile: NpcProfile:
	set(value):
		profile = value
		if is_node_ready():
			_load_model()
			_dress()

## Multiplies the profile's suit tint (e.g. colonists of one role in different suits).
@export var tint: Color = Color.WHITE:
	set(value):
		tint = value
		if is_node_ready():
			_dress()

## Whom it turns towards; null: the nearest player close by.
var faces: Node3D
## Whether it sits on the seat behind where it stands (its model's "Sit" clip, see `NpcAnimator`;
## the suit has it): it sits down and gets up over `NpcAnimator.sit_blend_time`, facing ahead.
var sitting: bool = false:
	set(value):
		sitting = value
		_animator.sitting = value
## Whether the name plate may show (e.g. hidden while someone talks to them).
var plate_allowed: bool = true
## Where the top of the head is, in m above the feet (e.g. a speech bubble sits above it): the
## model's "HeadTop" marker, the suit's helmet without one.
var head_height: float = SUIT_HEAD_HEIGHT

## The suit model the scene starts with (shown while the profile has no model of its own).
var _suit_scene: PackedScene
## The model's skeleton and its hips bone (how far the hips are down while sitting).
var _skeleton: Skeleton3D
var _hips: int = -1

@onready var _model: Node3D = $Model
@onready var _animator: NpcAnimator = $Animator
@onready var _plate: Label3D = $NamePlate


func _ready() -> void:
	_suit_scene = load(_model.scene_file_path)
	_load_model()
	_dress()
	_plate.visible = false


func _process(delta: float) -> void:
	_turn(delta)
	var near: Player = Player.nearest(get_tree(), global_position, PLATE_RANGE)
	# Not while that player uses a menu (the camera moves in close: the plate would fill the view).
	_plate.visible = plate_allowed and near != null and near.menu == null
	if _plate.visible:
		_plate.text = get_plate_text()
		_plate.position.y = head_height + _sit_drop() + PLATE_ABOVE_HEAD


## Their name and role, as the name plate shows them (only the role without a name).
func get_plate_text() -> String:
	if not profile:
		return ""
	if profile.display_name.is_empty():
		return tr(profile.role)
	return "%s · %s" % [profile.display_name, tr(profile.role)]


## Plays the legs walking forward at `speed` (m/s; 0: standing).
func walk(speed: float) -> void:
	_animator.speed = speed


## Whether the legs walk.
func is_walking() -> bool:
	return _animator.speed > 0.0


## Sits down or gets up at once (`sitting` without blending; e.g. someone already sitting when the
## place loads).
func settle() -> void:
	_animator.settle()


## How far it sits right now: 0 standing, 1 sitting (in between while sitting down or getting up).
func get_sit_amount() -> float:
	return _animator.sit_amount()


## Whether the name plate shows right now.
func is_plate_shown() -> bool:
	return _plate.visible


## The top of the head, in world space (lower while sitting).
func get_head_position() -> Vector3:
	return global_position + Vector3.UP * (head_height + _sit_drop())


## How far the head is down from standing because it sits (negative; 0 standing): as far as the
## hips are below their rest height.
func _sit_drop() -> float:
	if _animator.sit_amount() <= 0.0 or _hips < 0:
		return 0.0
	var pose: Vector3 = _skeleton.global_transform * _skeleton.get_bone_global_pose(_hips).origin
	var rest: Vector3 = _skeleton.global_transform * _skeleton.get_bone_global_rest(_hips).origin
	return pose.y - rest.y


## Turns towards `faces`, else the nearest player close by, else back to where it stands facing
## (its parent's forward).
func _turn(delta: float) -> void:
	var target: Node3D = faces
	if not target and not sitting:
		target = Player.nearest(get_tree(), global_position, NOTICE_RANGE)
	# Works on its activities only while nobody is close (it turns to them instead).
	_animator.may_work = target == null
	var yaw: float = 0.0
	if target and not sitting:
		var parent: Node3D = get_parent_node_3d()
		var offset: Vector3 = target.global_position - global_position
		var local: Vector3 = parent.global_basis.inverse() * offset if parent else offset
		if Vector2(local.x, local.z).length() > 0.1:
			yaw = atan2(local.x, local.z)
	rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-TURN_SPEED * delta))


## Puts in the profile's own model (else the suit) in place of the one there, sets up its clips
## (with the profile's activities and props, on its own model) and measures where its head is.
func _load_model() -> void:
	var own_model: bool = profile != null and not profile.model.is_empty()
	var scene: PackedScene = load(profile.model) as PackedScene if own_model else _suit_scene
	if _model.scene_file_path != scene.resource_path:
		var model := scene.instantiate() as Node3D
		remove_child(_model)
		_model.queue_free()
		model.name = "Model"
		add_child(model)
		move_child(model, 0)
		_model = model
	var activities: Array[StringName] = []
	if own_model:
		activities = profile.activities
	_animator.setup(_model, activities)
	_skeleton = _model.find_child("Skeleton3D") as Skeleton3D
	_hips = _skeleton.find_bone("Hips") if _skeleton else -1
	if own_model:
		for prop: StringName in profile.props:
			var grip := _model.find_child(String(prop) + "Grip", true, false) as Node3D
			if not grip:
				push_error('NpcBody: the model has no "%sGrip"' % prop)
				continue
			grip.add_child(profile.props[prop].instantiate())
	var top := _model.find_child("HeadTop", true, false) as Node3D
	head_height = (
		(global_transform.affine_inverse() * top.global_position).y if top else SUIT_HEAD_HEIGHT
	)
	_plate.position.y = head_height + PLATE_ABOVE_HEAD


## The suit in their darker tint, the collar light in their own color (not on an own model).
func _dress() -> void:
	if not profile:
		return
	var suit := _model.find_child("Suit") as MeshInstance3D
	if suit and suit.mesh:
		for surface: int in suit.mesh.get_surface_count():
			var material := suit.mesh.surface_get_material(surface) as BaseMaterial3D
			if not material:
				continue
			var tinted := material.duplicate() as BaseMaterial3D
			tinted.albedo_color *= profile.suit_tint * tint
			suit.set_surface_override_material(surface, tinted)
	var band := _model.find_child("SuitLight") as GeometryInstance3D
	if band:
		var light := StandardMaterial3D.new()
		light.albedo_color = profile.accent_color
		light.emission_enabled = true
		light.emission = profile.accent_color
		light.emission_energy_multiplier = 2.0
		band.material_override = light
		band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
