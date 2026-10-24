class_name NpcBody
extends Node3D
## Someone standing in the world (see GAME_DESIGN.md, Spaceship: NPCs), who `profile` says: the
## suit model in their darker tint with the collar light in their own color, turning towards whom
## it `faces` (else the nearest player close by, else back to where it stands facing), and their
## name plate while a player is near (not while they use a menu). The profile's `accessory` goes on
## over the suit, each part following its bone. The crew (`Npc`, which adds
## talking) and the station's ambient colonists (`Colonist`, which adds walking) share it.

## How close (in m) a player must be for it to turn towards them.
const NOTICE_RANGE: float = 3.0
## How close (in m) a player must be to see the name plate.
const PLATE_RANGE: float = 4.0
## How fast it turns (per s, smoothed).
const TURN_SPEED: float = 5.0
## Where the top of the head is, in m above the feet (e.g. a speech bubble sits above it).
const HEAD_HEIGHT: float = 1.9

## Who it is: the name plate and the suit's look.
@export var profile: NpcProfile:
	set(value):
		profile = value
		if is_node_ready():
			_dress()
			_wear()

## Multiplies the profile's suit tint (e.g. colonists of one role in different suits).
@export var tint: Color = Color.WHITE:
	set(value):
		tint = value
		if is_node_ready():
			_dress()

## Whom it turns towards; null: the nearest player close by.
var faces: Node3D
## Whether the name plate may show (e.g. hidden while someone talks to them).
var plate_allowed: bool = true

## The bone attachments holding the accessory's parts.
var _worn: Array[BoneAttachment3D] = []

@onready var _model: Node3D = $Model
@onready var _animator: PlayerAnimator = $Animator
@onready var _plate: Label3D = $NamePlate


func _ready() -> void:
	_animator.aiming = false
	_animator.walks = true
	_animator.setup(_model)
	_dress()
	_wear()
	_plate.visible = false


func _process(delta: float) -> void:
	_turn(delta)
	var near: Player = Player.nearest(get_tree(), global_position, PLATE_RANGE)
	# Not while that player uses a menu (the camera moves in close: the plate would fill the view).
	_plate.visible = plate_allowed and near != null and near.menu == null
	if _plate.visible:
		_plate.text = get_plate_text()


## Their name and role, as the name plate shows them (only the role without a name).
func get_plate_text() -> String:
	if not profile:
		return ""
	if profile.display_name.is_empty():
		return tr(profile.role)
	return "%s · %s" % [profile.display_name, tr(profile.role)]


## Plays the legs walking forward at `speed` (m/s; 0: standing).
func walk(speed: float) -> void:
	_animator.local_velocity = Vector2(0.0, speed)


## Whether the legs walk.
func is_walking() -> bool:
	return not _animator.local_velocity.is_zero_approx()


## Whether the name plate shows right now.
func is_plate_shown() -> bool:
	return _plate.visible


## The top of the head, in world space.
func get_head_position() -> Vector3:
	return global_position + Vector3.UP * HEAD_HEIGHT


## Turns towards `faces`, else the nearest player close by, else back to where it stands facing
## (its parent's forward).
func _turn(delta: float) -> void:
	var target: Node3D = faces
	if not target:
		target = Player.nearest(get_tree(), global_position, NOTICE_RANGE)
	var yaw: float = 0.0
	if target:
		var parent: Node3D = get_parent_node_3d()
		var offset: Vector3 = target.global_position - global_position
		var local: Vector3 = parent.global_basis.inverse() * offset if parent else offset
		if Vector2(local.x, local.z).length() > 0.1:
			yaw = atan2(local.x, local.z)
	rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-TURN_SPEED * delta))


## The suit in their darker tint, the collar light in their own color.
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


## Puts on the profile's accessory: each of its parts on the bone it's named after, where it sits
## in the model's rest pose.
func _wear() -> void:
	for worn: BoneAttachment3D in _worn:
		worn.queue_free()
	_worn.clear()
	if not profile or not profile.accessory:
		return
	var skeleton := _model.find_child("Skeleton3D") as Skeleton3D
	var outfit := profile.accessory.instantiate() as Node3D
	# Its parts move under the skeleton, out of the outfit's scene.
	for owned: Node in outfit.find_children("*", "", true, false):
		owned.owner = null
	var skeleton_in_model: Transform3D = (
		_model.global_transform.affine_inverse() * skeleton.global_transform
	)
	for child: Node in outfit.get_children():
		var part := child as Node3D
		var bone: int = skeleton.find_bone(part.name)
		if bone < 0:
			push_error('NpcBody: "%s" is no bone of the suit model' % part.name)
			continue
		var attachment := BoneAttachment3D.new()
		attachment.name = "Worn" + part.name
		attachment.bone_name = part.name
		skeleton.add_child(attachment)
		_worn.append(attachment)
		var bone_in_model: Transform3D = skeleton_in_model * skeleton.get_bone_global_rest(bone)
		var in_model: Transform3D = part.transform
		outfit.remove_child(part)
		attachment.add_child(part)
		part.transform = bone_in_model.affine_inverse() * in_model
	outfit.free()
