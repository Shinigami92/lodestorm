class_name ShieldField
extends MeshInstance3D
## A shield's field (Mantle, see `WeaponGuard`), made by its weapon (`Weapon.field`): a curved pane
## of warm light standing `radius` m in front of the holder across the guard's arc, turned with
## the holder. While it's up (the weapon drawn and held, its charge not broken, not right after a
## bash) it blocks an alien's blow coming from within its arc (`block`, see `Player.take_damage`)
## and alien shots crossing it (`stopping`: globs, bolts, hooks), whoever they were aimed at,
## draining its charge (`FieldAmmo`); a stopped heavy blow shoves the holder back and stops a
## charge (`AlienStatus.blocked`). It dims as its charge runs down, flares and sends a ring out
## where it's hit, and hums while it stands. Players' own shots pass it. Greybox look, TBD
## (playtest).

const GROUP: StringName = &"shield_fields"
const SHADER: Shader = preload("res://game/weapons/shield_field.gdshader")
## Columns of the pane's mesh across its arc.
const SEGMENTS: int = 20
## Hits whose rings show at once.
const RINGS: int = 4
## Seconds a block's flash fades over.
const FLARE_TIME: float = 0.25
## Shots this far below the holder's feet still cross it (m).
const BELOW: float = 0.3
## Where on the pane a blow lands, above the holder's feet (m).
const BLOW_HEIGHT: float = 1.0

## The weapon it belongs to, and its guard.
var weapon: Weapon
var guard: WeaponGuard

var _material := ShaderMaterial.new()
## The arc (radians) the mesh was built for.
var _built_arc: float = -1.0
## The latest hits for the rings: where on the pane (m), seconds since, how hard.
var _rings: Array[Vector4] = []
var _next_ring: int = 0
var _flare: float = 0.0
var _hum: AudioStreamPlayer3D


func _ready() -> void:
	top_level = true
	layers = RenderLayers.EFFECTS
	add_to_group(GROUP)
	_material.shader = SHADER
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i: int in RINGS:
		_rings.append(Vector4(0.0, 0.0, -1.0, 0.0))
	visible = false


func _process(delta: float) -> void:
	var up: bool = is_up()
	visible = up
	if not up:
		_stop_hum()
		return
	global_transform = Transform3D(Basis.looking_at(facing()), weapon.holder.global_position)
	var arc: float = arc_width()
	if not is_equal_approx(arc, _built_arc):
		_build(arc)
	for i: int in RINGS:
		if _rings[i].z >= 0.0:
			_rings[i].z += delta
	_flare = maxf(_flare - delta / FLARE_TIME, 0.0)
	_material.set_shader_parameter(&"hits", _rings)
	_material.set_shader_parameter(&"flare", _flare)
	_material.set_shader_parameter(&"strength", (weapon.ammo as FieldAmmo).share())
	if not is_instance_valid(_hum) and guard.hum_sound:
		_hum = Sfx.play_loop_at(guard.hum_sound, self)


func _exit_tree() -> void:
	_stop_hum()


## Whether it stands and blocks: its weapon drawn and held by a living player, its charge not
## broken, and not right after a bash.
func is_up() -> bool:
	if not weapon or not weapon.holder or not weapon.is_visible_in_tree() or not weapon.is_drawn():
		return false
	if weapon.holder is Player and (weapon.holder as Player).dead:
		return false
	var ammo := weapon.ammo as FieldAmmo
	if not ammo or ammo.is_broken():
		return false
	var since: float = weapon.since_attack - guard.open_after
	return since < 0.0 or since > guard.open_time


## The horizontal unit vector it faces: where the holder's body faces.
func facing() -> Vector3:
	var forward: Vector3 = -weapon.holder.global_basis.z
	forward.y = 0.0
	return forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD


## Its width around where it faces, with the MK level of the weapon's arc (radians).
func arc_width() -> float:
	return deg_to_rad(minf(guard.arc * weapon.multiplier(WeaponPart.Stat.ARC), 360.0))


## Whether `point` lies within its arc, seen from the holder (horizontally).
func covers(point: Vector3) -> bool:
	var offset: Vector3 = point - weapon.holder.global_position
	offset.y = 0.0
	return offset.length() < 0.01 or offset.angle_to(facing()) <= arc_width() * 0.5


## Blocks a blow of `attacker` for `amount` damage on the holder, if it's up and the attacker within
## its arc. Returns the damage that gets through. A `heavy` blow it stops shoves the holder back and
## stops the attacker's charge.
func block(amount: float, attacker: Node3D, heavy: bool) -> float:
	if not is_up() or not covers(attacker.global_position):
		return amount
	var toward: Vector3 = attacker.global_position - weapon.holder.global_position
	toward.y = 0.0
	toward = toward.normalized() if toward.length() > 0.01 else facing()
	var point: Vector3 = weapon.holder.global_position + toward * guard.radius
	var through: float = _absorb(amount, point + Vector3.UP * BLOW_HEIGHT, heavy)
	if heavy and through <= 0.0:
		if weapon.holder is Player and guard.shove > 0.0:
			var holder := weapon.holder as Player
			holder.suit_dash.shove(-toward * guard.shove / guard.shove_time, guard.shove_time)
		if attacker is Alien:
			(attacker as Alien).status.blocked = true
	return through


## Whether a field that is up stops an alien shot moving from `from` to `to` (an acid glob or bolt,
## a flesh hook) for `amount` damage: it crosses the field from outside, within its arc and height.
## A field it breaks lets it pass.
static func stopping(tree: SceneTree, from: Vector3, to: Vector3, amount: float) -> bool:
	for node: Node in tree.get_nodes_in_group(GROUP):
		var field := node as ShieldField
		if not field.is_up():
			continue
		var point: Vector3 = field._crossing(from, to)
		if point != Vector3.INF:
			return field._absorb(amount, point, false) <= 0.0
	return false


## Where a shot moving from `from` to `to` crosses into it, or `Vector3.INF`.
func _crossing(from: Vector3, to: Vector3) -> Vector3:
	var middle: Vector3 = weapon.holder.global_position
	var before: float = Vector2(from.x - middle.x, from.z - middle.z).length()
	var after: float = Vector2(to.x - middle.x, to.z - middle.z).length()
	if before < guard.radius or after >= guard.radius:
		return Vector3.INF
	var point: Vector3 = from.lerp(to, (before - guard.radius) / maxf(before - after, 0.0001))
	var height: float = point.y - middle.y
	if height < -BELOW or height > guard.height or not covers(point):
		return Vector3.INF
	return point


## Drains its charge by `amount`, flaring at `point`; returns the damage that gets through.
func _absorb(amount: float, point: Vector3, heavy: bool) -> float:
	var through: float = (weapon.ammo as FieldAmmo).absorb(amount)
	if through >= amount:
		return through
	GameEvents.bus.shield_blocked.emit(
		GameEvents.player_of(weapon.holder), weapon.type, amount - through
	)
	_flare = 1.0
	_ring_at(point, 1.0 if heavy else clampf(amount / 15.0, 0.4, 1.0))
	Sfx.play_at(guard.heavy_sound if heavy else guard.block_sound, point)
	return through


## Starts a ring where `point` lies on the pane.
func _ring_at(point: Vector3, strength: float) -> void:
	var local: Vector3 = global_transform.affine_inverse() * point
	var angle: float = atan2(local.x, -local.z)
	var across: float = (angle + arc_width() * 0.5) * guard.radius
	_rings[_next_ring] = Vector4(across, clampf(local.y, 0.0, guard.height), 0.0, strength)
	_next_ring = (_next_ring + 1) % RINGS


## The pane across `arc` radians: a part of a cylinder around the holder.
func _build(arc: float) -> void:
	_built_arc = arc
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for i: int in SEGMENTS + 1:
		var share: float = float(i) / SEGMENTS
		var angle: float = (share - 0.5) * arc
		var at := Vector3(sin(angle) * guard.radius, 0.0, -cos(angle) * guard.radius)
		vertices.append(at)
		vertices.append(at + Vector3.UP * guard.height)
		uvs.append(Vector2(share, 0.0))
		uvs.append(Vector2(share, 1.0))
		if i > 0:
			var a: int = (i - 1) * 2
			indices.append_array(PackedInt32Array([a, a + 1, a + 2, a + 1, a + 3, a + 2]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var pane := ArrayMesh.new()
	pane.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = pane
	_material.set_shader_parameter(&"size", Vector2(arc * guard.radius, guard.height))


func _stop_hum() -> void:
	if is_instance_valid(_hum):
		Sfx.stop_loop(_hum)
	_hum = null
