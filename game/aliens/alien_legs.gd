class_name AlienLegs
extends SkeletonModifier3D
## Procedural legs for four- and six-legged aliens (a child of the model's Skeleton3D): each foot
## stays planted on the ground until the body has moved too far from it, then steps to where the
## body will be shortly, the legs taking turns in two sets: four legs trot (the diagonal pairs step
## together), six walk in tripods (front and hind of one side with the middle of the other).
## Two-bone IK bends each leg to its planted foot after the animation played: the upper and lower
## leg reach the ankle (the foot bone's head) and the foot keeps its animated angle. The ground
## under a new step is found by a ray; without one the feet stay level with the alien's origin. It
## works with the interpolated transform, so the feet stay put between physics ticks.
## Leg bones are named `<Front|Mid|Hind><Left|Right><UpperLeg|LowerLeg|Foot>` (see
## tools/blender/creature.py); a row without bones is left out. Values TBD (playtest).

## The rows of legs from the front, and the sides.
const ROWS: PackedStringArray = ["Front", "Mid", "Hind"]
const SIDES: PackedStringArray = ["Left", "Right"]
## Rays for the ground start this high above the foot and reach this far below it (m).
const RAY_UP: float = 1.0
const RAY_DOWN: float = 1.5

## A foot steps once the spot under its hip is this far away while standing (m).
@export var step_distance: float = 0.3
## Added to the step distance per m/s of speed, so running takes longer strides.
@export var step_distance_per_speed: float = 0.06
## How long a step takes while standing (s); shorter when running.
@export var step_duration: float = 0.25
## Shortest step, at full speed (s).
@export var min_step_duration: float = 0.11
## How high a foot lifts in the middle of a step (m).
@export var step_height: float = 0.12
## Physics layers the feet stand on.
@export_flags_3d_physics var ground_mask: int = 1

## Where each foot stands (world space), by leg name.
var feet: Dictionary[String, Vector3] = {}

var _legs: Array[Leg] = []
## The legs of each set that steps together.
var _groups: Array[Array] = [[], []]
var _last_origin: Vector3
var _velocity: Vector3 = Vector3.ZERO
var _started: bool = false


## One leg: its bones, rest measures (skeleton space) and step state (world space).
class Leg:
	var name: String
	## 0 or 1: the set it steps with.
	var group: int
	## The bone the leg hangs from (hips or chest).
	var parent: int
	var upper: int
	var lower: int
	var foot: int
	var upper_length: float
	var lower_length: float
	## Rest position of the ankle on the ground (y = 0) and its height above it, skeleton space.
	var home: Vector3
	var ankle_height: float
	## Side the knee or elbow bends to, skeleton space.
	var pole: Vector3
	var planted: Vector3
	var from: Vector3
	var to: Vector3
	## Progress of the current step (0–1), or -1 while planted.
	var step: float = -1.0

	func stepping() -> bool:
		return step >= 0.0


## Whether any foot is in the air.
func is_stepping() -> bool:
	for leg: Leg in _legs:
		if leg.stepping():
			return true
	return false


## Puts every foot on the ground under its hip at once (after a teleport).
func plant_all() -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if not skeleton:
		return
	for leg: Leg in _legs:
		leg.planted = _ground(skeleton.get_global_transform_interpolated() * leg.home)
		leg.step = -1.0
		feet[leg.name] = leg.planted
	_last_origin = skeleton.get_global_transform_interpolated().origin
	_velocity = Vector3.ZERO
	_started = true


func _setup() -> void:
	_legs.clear()
	_groups = [[], []]
	_started = false
	var skeleton: Skeleton3D = get_skeleton()
	var row: int = 0
	for row_name: String in ROWS:
		if skeleton.find_bone(row_name + "LeftUpperLeg") < 0:
			continue
		for side: int in SIDES.size():
			_add_leg(skeleton, row_name + SIDES[side], (row + side) % 2)
		row += 1


## Adds the leg `leg_name` stepping with set `group`.
func _add_leg(skeleton: Skeleton3D, leg_name: String, group: int) -> void:
	var leg := Leg.new()
	leg.name = leg_name
	leg.group = group
	leg.upper = skeleton.find_bone(leg_name + "UpperLeg")
	leg.lower = skeleton.find_bone(leg_name + "LowerLeg")
	leg.foot = skeleton.find_bone(leg_name + "Foot")
	if leg.upper < 0 or leg.lower < 0 or leg.foot < 0:
		push_error("AlienLegs: missing bones for %s" % leg_name)
		return
	leg.parent = skeleton.get_bone_parent(leg.upper)
	var hip: Vector3 = skeleton.get_bone_global_rest(leg.upper).origin
	var knee: Vector3 = skeleton.get_bone_global_rest(leg.lower).origin
	var ankle: Vector3 = skeleton.get_bone_global_rest(leg.foot).origin
	leg.upper_length = hip.distance_to(knee)
	leg.lower_length = knee.distance_to(ankle)
	leg.home = Vector3(ankle.x, 0.0, ankle.z)
	leg.ankle_height = ankle.y
	var axis: Vector3 = (ankle - hip).normalized()
	var off: Vector3 = knee - hip
	leg.pole = (off - axis * off.dot(axis)).normalized()
	_legs.append(leg)
	_groups[leg.group].append(leg)


func _process_modification_with_delta(delta: float) -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if not skeleton:
		return
	if _legs.is_empty():
		_setup()
	if not _started:
		plant_all()
	var xform: Transform3D = skeleton.get_global_transform_interpolated()
	var size: float = xform.basis.get_scale().x
	if delta > 0.0:
		var moved: Vector3 = (xform.origin - _last_origin) / delta
		_velocity = _velocity.lerp(Vector3(moved.x, 0.0, moved.z), minf(delta * 12.0, 1.0))
	_last_origin = xform.origin
	var speed: float = _velocity.length()
	var reach: float = (step_distance + step_distance_per_speed * speed) * size
	var duration: float = clampf(step_duration - speed * 0.03, min_step_duration, step_duration)
	for group: int in 2:
		_update_set(_groups[group], xform, reach, duration, _group_stepping(1 - group), delta)
	var to_skeleton: Transform3D = xform.affine_inverse()
	# Read every animated pose first: reading one after a write would update the whole skeleton.
	var poses: Array[Transform3D] = []
	for leg: Leg in _legs:
		for bone: int in [leg.parent, leg.upper, leg.lower, leg.foot]:
			poses.append(skeleton.get_bone_global_pose(bone))
	for i: int in _legs.size():
		var leg: Leg = _legs[i]
		feet[leg.name] = leg.planted
		_solve(skeleton, leg, to_skeleton * leg.planted, poses.slice(i * 4, i * 4 + 4))


## Moves the feet of one set: steps in progress go on; once a planted foot is too far from its
## spot, the whole set steps, so its feet lift and land together.
func _update_set(
	legs: Array, xform: Transform3D, reach: float, duration: float, others_up: bool, delta: float
) -> void:
	var homes: Array[Vector3] = []
	var step: bool = false
	for leg: Leg in legs:
		# Aim a bit ahead: half a step's travel, so the foot lands under the body, not behind it.
		var home: Vector3 = xform * leg.home + _velocity * duration
		homes.append(home)
		if leg.stepping():
			leg.step = minf(leg.step + delta / duration, 1.0)
			var s: float = smoothstep(0.0, 1.0, leg.step)
			var lift: float = sin(PI * leg.step) * step_height * xform.basis.get_scale().x
			leg.planted = leg.from.lerp(leg.to, s) + Vector3.UP * lift
			if leg.step >= 1.0:
				leg.planted = leg.to
				leg.step = -1.0
			continue
		var off: Vector3 = home - leg.planted
		var distance: float = Vector2(off.x, off.z).length()
		# Far behind (a teleport or a fall): plant it right away.
		if distance > reach * 6.0:
			leg.planted = _ground(home)
		# Too far: step, once the other set stands (or at once when it lags far behind).
		elif distance > reach and (not others_up or distance > reach * 2.0):
			step = true
	if not step:
		return
	for i: int in legs.size():
		var leg: Leg = legs[i]
		if not leg.stepping():
			leg.from = leg.planted
			leg.to = _ground(homes[i])
			leg.step = 0.0


func _group_stepping(group: int) -> bool:
	for leg: Leg in _groups[group]:
		if leg.stepping():
			return true
	return false


## The ground under `point` (the closest static surface along a vertical ray), or `point` at the
## height of the alien's origin when there is none. Other characters are skipped.
func _ground(point: Vector3) -> Vector3:
	var skeleton: Skeleton3D = get_skeleton()
	var fallback := Vector3(point.x, skeleton.get_global_transform_interpolated().origin.y, point.z)
	if not skeleton.is_inside_tree():
		return fallback
	var space: PhysicsDirectSpaceState3D = skeleton.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		fallback + Vector3.UP * RAY_UP, fallback + Vector3.DOWN * RAY_DOWN, ground_mask
	)
	query.collide_with_areas = false
	var skipped: Array[RID] = []
	for attempt: int in 4:
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			return fallback
		if hit["collider"] is CharacterBody3D:
			skipped.append(hit["rid"] as RID)
			query.exclude = skipped
			continue
		return hit["position"] as Vector3
	return fallback


## Bends `leg` so its ankle sits above `foot` (skeleton space): the upper and lower leg turn to
## reach it, bending towards the pole; the foot keeps its animated orientation.
## `poses` are the animated global poses of the leg's parent, upper and lower leg and foot. The
## new poses are written as local ones, so the skeleton updates once after all legs.
func _solve(skeleton: Skeleton3D, leg: Leg, foot: Vector3, poses: Array[Transform3D]) -> void:
	var parent: Transform3D = poses[0]
	var upper: Transform3D = poses[1]
	var lower: Transform3D = poses[2]
	var hip: Vector3 = upper.origin
	var target: Vector3 = foot + Vector3.UP * leg.ankle_height
	var knee_ankle: Array[Vector3] = two_bone(
		hip, target, leg.upper_length, leg.lower_length, leg.pole
	)
	var knee: Vector3 = knee_ankle[0]
	var ankle: Vector3 = knee_ankle[1]
	# Turning the upper leg turns the lower one with it; then the lower leg turns to the ankle.
	var turn_upper := Basis(_arc(upper.basis.y, knee - hip))
	var new_upper := Transform3D(turn_upper * upper.basis, hip)
	var lower_basis: Basis = turn_upper * lower.basis
	var new_lower := Transform3D(Basis(_arc(lower_basis.y, ankle - knee)) * lower_basis, knee)
	var new_foot := Transform3D(poses[3].basis, ankle)
	skeleton.set_bone_pose(leg.upper, parent.affine_inverse() * new_upper)
	skeleton.set_bone_pose(leg.lower, new_upper.affine_inverse() * new_lower)
	skeleton.set_bone_pose(leg.foot, new_lower.affine_inverse() * new_foot)


## Knee (joint) and end positions of a two-bone chain from `root` reaching for `target` with
## bone lengths `a` and `b`, bending towards `pole`. Out of reach, it stretches towards it.
static func two_bone(
	root: Vector3, target: Vector3, a: float, b: float, pole: Vector3
) -> Array[Vector3]:
	var offset: Vector3 = target - root
	var distance: float = clampf(offset.length(), absf(a - b) + 0.001, (a + b) * 0.999)
	var dir: Vector3 = offset.normalized() if offset.length() > 0.0001 else Vector3.DOWN
	var side: Vector3 = pole - dir * pole.dot(dir)
	if side.length() < 0.0001:
		side = dir.cross(Vector3.RIGHT)
	side = side.normalized()
	var cos_a: float = (a * a + distance * distance - b * b) / (2.0 * a * distance)
	var sin_a: float = sqrt(maxf(0.0, 1.0 - cos_a * cos_a))
	var joint: Vector3 = root + (dir * cos_a + side * sin_a) * a
	return [joint, root + dir * distance]


## The shortest rotation from direction `from` to direction `to`.
static func _arc(from: Vector3, to: Vector3) -> Quaternion:
	var a: Vector3 = from.normalized()
	var b: Vector3 = to.normalized()
	if a.dot(b) > 0.99999:
		return Quaternion.IDENTITY
	return Quaternion(a, b)
