class_name FleshHook
extends Node3D
## A stalker's hook on its sinew line (`AlienHook`): it flies straight from the stalker's chest
## towards where its target was, catching the first player in its way (see `AlienHook`); rock stops
## it. A caught player keeps it in them while the snare holds, then it's pulled back, as it is when
## it misses or flies its full length. The line runs from the stalker to the hook all the time and
## goes when the stalker dies. A shield's field it flies into stops it (see
## `ShieldField.stopping`). Greybox look, TBD (playtest).

## Where on a player it aims and holds (m above their feet).
const CHEST_HEIGHT: float = 1.2
## How far beyond its range it flies (m).
const OVERSHOOT: float = 2.0
## Seconds it takes to pull back.
const RETRACT_TIME: float = 0.25
const LINE_RADIUS: float = 0.03
const HEAD_RADIUS: float = 0.09
const COLOR_LINE := Color(0.28, 0.08, 0.1)

## The stalker on the other end, and its attack.
var alien: Alien
var hook: AlienHook
## Unit vector it flies along.
var direction := Vector3.FORWARD

var _travelled: float = 0.0
var _caught: Player
var _hold_left: float = 0.0
## Where it was when it started pulling back, and how far back it is (0 to 1); -1: not yet.
var _retract_from := Vector3.ZERO
var _retracted: float = -1.0
var _line: MeshInstance3D
var _head: MeshInstance3D


## Shoots a hook of `of_hook` from `start` (global) towards `at` (global), in `from_alien`'s parent.
static func launch(from_alien: Alien, of_hook: AlienHook, start: Vector3, at: Vector3) -> FleshHook:
	var flesh_hook := FleshHook.new()
	flesh_hook.alien = from_alien
	flesh_hook.hook = of_hook
	var offset: Vector3 = at - start
	flesh_hook.direction = offset.normalized() if offset.length() > 0.01 else Vector3.FORWARD
	from_alien.get_parent().add_child(flesh_hook)
	flesh_hook.global_position = start
	return flesh_hook


## Whether it holds a player.
func is_holding() -> bool:
	return is_instance_valid(_caught) and _retracted < 0.0


func _ready() -> void:
	var sinew := StandardMaterial3D.new()
	sinew.albedo_color = COLOR_LINE
	sinew.roughness = 0.6
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = LINE_RADIUS
	cylinder.bottom_radius = LINE_RADIUS
	cylinder.height = 1.0
	cylinder.radial_segments = 6
	cylinder.rings = 1
	cylinder.material = sinew
	_line = MeshInstance3D.new()
	_line.name = "Line"
	_line.mesh = cylinder
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_line.top_level = true
	add_child(_line)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Alien.COLOR_GLOW
	glow.emission_enabled = true
	glow.emission = Alien.COLOR_GLOW
	glow.emission_energy_multiplier = 2.0
	var sphere := SphereMesh.new()
	sphere.radius = HEAD_RADIUS
	sphere.height = HEAD_RADIUS * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	sphere.material = glow
	_head = MeshInstance3D.new()
	_head.name = "Head"
	_head.mesh = sphere
	_head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_head)
	RenderLayers.put(self, RenderLayers.EFFECTS)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(alien) or alien.dead:
		queue_free()
		return
	if _retracted >= 0.0:
		_retracted = minf(_retracted + delta / RETRACT_TIME, 1.0)
		global_position = _retract_from.lerp(_start(), _retracted)
		if _retracted >= 1.0:
			queue_free()
	elif is_instance_valid(_caught):
		_hold_left -= delta
		global_position = _caught.global_position + Vector3.UP * CHEST_HEIGHT
		if _hold_left <= 0.0 or _caught.dead:
			_pull_back()
	else:
		_fly(delta)


func _process(_delta: float) -> void:
	if not is_instance_valid(alien):
		return
	var from: Vector3 = _start()
	var to: Vector3 = global_position
	var length: float = from.distance_to(to)
	_line.visible = length > 0.05
	if not _line.visible:
		return
	var along: Vector3 = (to - from) / length
	var side: Vector3 = Vector3.UP if absf(along.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var x: Vector3 = side.cross(along).normalized()
	var z: Vector3 = x.cross(along)
	_line.global_transform = Transform3D(Basis(x, along * length, z), (from + to) * 0.5)


## Where the line leaves the stalker (global).
func _start() -> Vector3:
	return alien.global_transform * hook.mouth


## Flies on for `delta` seconds: catches a player in its way, stops at rock.
func _fly(delta: float) -> void:
	var step: Vector3 = direction * hook.hook_speed * delta
	var amount: float = hook.damage * alien.damage_factor
	if ShieldField.stopping(get_tree(), global_position, global_position + step, amount):
		global_position += step * 0.5
		_pull_back()
		return
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position, global_position + step, PhysicsLayers.SHOTS
	)
	var skipped: Array[RID] = [alien.get_rid()]
	query.exclude = skipped
	for attempt: int in 4:
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			break
		var collider: Object = hit["collider"]
		if collider is Player and Alien.is_prey(get_tree(), collider as Player):
			_catch(collider as Player)
			return
		if collider is Alien or collider is Player:
			skipped.append(hit["rid"] as RID)
			query.exclude = skipped
			continue
		global_position = hit["position"] as Vector3
		_pull_back()
		return
	global_position += step
	_travelled += step.length()
	if _travelled >= hook.max_range + OVERSHOOT:
		_pull_back()


func _catch(player: Player) -> void:
	_caught = player
	_hold_left = hook.snare_time
	Alien.hurt(player, hook.damage * alien.damage_factor, alien.global_position, null, false, alien)
	player.ground_contact.snare(hook.snare, hook.snare_time)
	global_position = player.global_position + Vector3.UP * CHEST_HEIGHT


func _pull_back() -> void:
	_retract_from = global_position
	_retracted = 0.0
