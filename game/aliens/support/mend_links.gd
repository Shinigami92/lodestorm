class_name MendLinks
extends Node3D
## A tender's links (a child of an `Alien` whose strain has a `mend`): pulsing strands from the tips
## of its tendrils to up to `mend.links` aliens within `mend.link_range`, the most hurt first. A
## linked alien heals and has more armor on every side. A link breaks when either dies or goes
## under the ground, or when they're farther apart than `mend.break_range`; tenders don't link each
## other (two of them would keep each other alive), and an alien takes one link at most. While the
## tender is staggered (focus fire), the links dim and don't heal.

## Seconds between looks for aliens to link.
const PICK_INTERVAL: float = 0.5
## Width of a strand (m).
const STRAND_RADIUS: float = 0.045
## Without tendril bones the strands start this high above the tender's center (m).
const TIP_HEIGHT: float = 1.0

const SHADER := preload("res://game/aliens/support/mend_link.gdshader")

var mend: AlienMend

## The linked aliens, one per slot (null: free).
var linked: Array[Alien] = []

var _alien: Alien
var _skeleton: Skeleton3D
var _tips: Array[int] = []
var _strands: Array[MeshInstance3D] = []
var _until_pick: float = 0.0


func _ready() -> void:
	_alien = get_parent() as Alien
	_skeleton = _alien.find_child("Skeleton3D", true, false) as Skeleton3D
	var material := ShaderMaterial.new()
	material.shader = SHADER
	var strand := CylinderMesh.new()
	strand.top_radius = STRAND_RADIUS
	strand.bottom_radius = STRAND_RADIUS
	strand.height = 1.0
	strand.radial_segments = 6
	strand.rings = 1
	strand.material = material
	for i: int in mend.links:
		linked.append(null)
		var bone: int = -1
		if _skeleton and i < mend.tip_bones.size():
			bone = _skeleton.find_bone(mend.tip_bones[i])
		_tips.append(bone)
		var mesh := MeshInstance3D.new()
		mesh.name = "Strand%d" % (i + 1)
		mesh.mesh = strand
		mesh.top_level = true
		mesh.visible = false
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh)
		_strands.append(mesh)
	RenderLayers.put(self, RenderLayers.EFFECTS)


func _exit_tree() -> void:
	for i: int in linked.size():
		_unlink(i)


func _physics_process(delta: float) -> void:
	var working: bool = not _alien.dead and not _alien.underground
	for i: int in linked.size():
		if not is_instance_valid(linked[i]):
			# Freed without dying (a location reset): the slot is free again.
			linked[i] = null
		elif not working or not _holds(linked[i]):
			_unlink(i)
	if not working:
		return
	_until_pick -= delta
	if _until_pick <= 0.0:
		_until_pick = PICK_INTERVAL
		_pick()
	if _alien.is_staggered():
		return
	for alien: Alien in linked:
		if is_instance_valid(alien):
			var healed: float = mend.heal_per_second * alien.health_factor * delta
			alien.health = minf(alien.health + healed, alien.max_health())


func _process(_delta: float) -> void:
	for i: int in linked.size():
		_strands[i].visible = is_instance_valid(linked[i])
		if not _strands[i].visible:
			continue
		var alien: Alien = linked[i]
		var from: Vector3 = _tip(i)
		var to: Vector3 = alien.get_aim_point()
		var along: Vector3 = to - from
		var length: float = along.length()
		if length < 0.01:
			continue
		var up: Vector3 = along / length
		var side: Vector3 = (
			up.cross(Vector3.FORWARD if absf(up.y) > 0.9 else Vector3.UP).normalized()
		)
		var strand := Basis(side, up * length, side.cross(up))
		# The cylinder's top (UV.y = 0) at the mended alien: the pulses run towards it.
		_strands[i].global_transform = Transform3D(strand, from + along * 0.5)
		_strands[i].set_instance_shader_parameter(&"strand_length", length)
		_strands[i].set_instance_shader_parameter(
			&"strength", 0.0 if _alien.is_staggered() else 1.0
		)


## Whether the link to `alien` holds: alive, up and close enough.
func _holds(alien: Alien) -> bool:
	if not is_instance_valid(alien) or alien.dead or alien.underground:
		return false
	return _alien.horizontal_distance(alien) <= mend.break_range


## Fills free slots with the most hurt aliens in range, the nearest first among equals.
func _pick() -> void:
	var free: int = linked.count(null)
	if free == 0:
		return
	var candidates: Array[Alien] = []
	for alien: Alien in get_tree().get_nodes_in_group(Alien.GROUP):
		if alien == _alien or alien.strain.mend or alien.underground:
			continue
		if alien.status.is_mended() or alien in linked:
			continue
		if _alien.horizontal_distance(alien) <= mend.link_range:
			candidates.append(alien)
	candidates.sort_custom(_more_hurt)
	for alien: Alien in candidates.slice(0, free):
		var slot: int = linked.find(null)
		linked[slot] = alien
		alien.status.mended_by = self
		alien.status.bonus_armor += mend.armor


func _more_hurt(a: Alien, b: Alien) -> bool:
	var share_a: float = a.health / a.max_health()
	var share_b: float = b.health / b.max_health()
	if not is_equal_approx(share_a, share_b):
		return share_a < share_b
	return _alien.horizontal_distance(a) < _alien.horizontal_distance(b)


func _unlink(slot: int) -> void:
	var alien: Alien = linked[slot]
	linked[slot] = null
	if is_instance_valid(alien) and alien.status.mended_by == self:
		alien.status.mended_by = null
		alien.status.bonus_armor = maxf(alien.status.bonus_armor - mend.armor, 0.0)


## Where link `slot` starts: its tendril's tip, or above the tender.
func _tip(slot: int) -> Vector3:
	if _tips[slot] >= 0:
		return _skeleton.global_transform * _skeleton.get_bone_global_pose(_tips[slot]).origin
	return _alien.get_aim_point() + Vector3.UP * TIP_HEIGHT
