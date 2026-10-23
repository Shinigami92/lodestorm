class_name Blast
extends Node3D
## A blast (Tremor's shells, Wick's charges, see `LobDelivery`): every alien within its radius
## takes a hit, the full one at the middle and less towards the edge (`EDGE_SHARE`), pushed away
## from the middle, unless rock is in between; so does a destructible (a nest) whose edge is
## within it. What a shell hit directly takes the full blast. Players and miners are never hurt
## (no friendly fire). It flashes, throws up dust and shakes the view of players close to it.
## Greybox look, values TBD (playtest).

## Share of the hit an alien at the blast's edge takes.
const EDGE_SHARE: float = 0.5
## Seconds the flash takes to swell and fade.
const DURATION: float = 0.45
## How strongly the view shakes right at a blast (m), and how far away it's still felt (m).
const SHAKE: float = 0.12
const SHAKE_REACH: float = 25.0
## The flash's color, warm like the shots.
const COLOR := Color(1.0, 0.62, 0.28)

## Its radius in m.
var radius: float = 3.0

var _elapsed: float = 0.0
var _material := StandardMaterial3D.new()
var _flash: MeshInstance3D
var _light: OmniLight3D


## A blast of `radius` m at `center` (global) in `parent`, striking with `hit` (its damage, stagger,
## push and attacker; each alien's direction and share are worked out here), playing `sound`.
## `direct`, the alien or destructible a shell hit, takes the full blast.
static func explode(
	parent: Node,
	center: Vector3,
	blast_radius: float,
	hit: Hit,
	sound: Sound = null,
	direct: Node3D = null
) -> Blast:
	var blast := Blast.new()
	blast.radius = blast_radius
	parent.add_child(blast)
	blast.global_transform = Transform3D(Basis.IDENTITY, center)
	blast.strike(hit, direct)
	DustPuff.spawn(parent, center, blast_radius * 0.6)
	if sound:
		Sfx.play_at(sound, center)
	return blast


## Share of a blast's hit something `distance` m from its middle takes, 0 beyond `blast_radius`.
static func share_at(distance: float, blast_radius: float) -> float:
	if distance > blast_radius:
		return 0.0
	return lerpf(1.0, EDGE_SHARE, distance / maxf(blast_radius, 0.01))


func _ready() -> void:
	_material.albedo_color = COLOR
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 20
	sphere.rings = 8
	sphere.material = _material
	_flash = MeshInstance3D.new()
	_flash.name = "Flash"
	_flash.mesh = sphere
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flash)
	_light = OmniLight3D.new()
	_light.name = "Light"
	_light.light_color = COLOR
	_light.omni_range = radius * 2.5
	_light.position = Vector3.UP
	add_child(_light)
	_update()
	RenderLayers.put(self, RenderLayers.EFFECTS)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= DURATION:
		queue_free()
		return
	_update()
	var fade: float = 1.0 - _elapsed / DURATION
	for rig: IsoCameraRig in get_tree().get_nodes_in_group(IsoCameraRig.GROUP):
		if is_instance_valid(rig.target):
			var away: float = rig.target.global_position.distance_to(global_position)
			var near: float = clampf(1.0 - away / SHAKE_REACH, 0.0, 1.0)
			rig.tremble(SHAKE * fade * near * near)


## Hits every alien and destructible within its radius with nothing solid in between, each by its
## share of `hit`; `direct` (hit by a shell) takes all of it.
func strike(hit: Hit, direct: Node3D = null) -> void:
	var exclude: Array[RID] = []
	var aliens: Array[Alien] = []
	for node: Node in get_tree().get_nodes_in_group(Alien.GROUP):
		var alien := node as Alien
		if alien.is_hittable():
			exclude.append(alien.get_rid())
			if alien == direct or _distance_to(alien) <= radius:
				aliens.append(alien)
	for group: StringName in [Player.GROUP, Miner.GROUP]:
		for node: Node in get_tree().get_nodes_in_group(group):
			if node is CollisionObject3D:
				exclude.append((node as CollisionObject3D).get_rid())
	for alien: Alien in aliens:
		if alien == direct:
			_hit(alien, hit, 0.0)
		elif _reaches(alien.get_aim_point(), exclude, null):
			_hit(alien, hit, _distance_to(alien))
	for node: Node in get_tree().get_nodes_in_group(Destructible.GROUP):
		var body := node as Destructible
		if not body.is_hittable():
			continue
		var offset: Vector3 = body.global_position - global_position
		if absf(body.get_aim_point().y - global_position.y) > radius + body.aim_height:
			continue
		var distance: float = maxf(Vector2(offset.x, offset.z).length() - body.radius(), 0.0)
		if body == direct:
			_hit(body, hit, 0.0)
		elif distance <= radius and _reaches(body.get_aim_point(), exclude, body):
			_hit(body, hit, distance)


## How far `alien` is from the middle: to the nearer of its feet and its body's middle.
func _distance_to(alien: Alien) -> float:
	return minf(
		global_position.distance_to(alien.global_position),
		global_position.distance_to(alien.get_aim_point())
	)


## Whether nothing solid but `body` is between the middle and `point`.
func _reaches(point: Vector3, exclude: Array[RID], body: Destructible) -> bool:
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.3, point, PhysicsLayers.SHOTS
	)
	query.exclude = exclude
	var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	return result.is_empty() or (body != null and result["collider"] == body)


func _hit(target: Node3D, hit: Hit, distance: float) -> void:
	var share: float = share_at(distance, radius)
	var away: Vector3 = target.global_position - global_position
	away.y = 0.0
	var direction: Vector3 = away if away.length() > 0.01 else hit.direction
	var point: Vector3 = (
		(target as Alien).get_aim_point()
		if target is Alien
		else (target as Destructible).get_aim_point()
	)
	var struck := Hit.new(
		hit.damage * share,
		hit.stagger * share,
		hit.push * share,
		direction,
		point,
		hit.attacker,
		hit.weapon_type
	)
	var dealt: float = 0.0
	if target is Alien:
		dealt = (target as Alien).take_hit(struck)
	else:
		dealt = (target as Destructible).take_hit(struck)
	DamageNumber.show_hit(hit.attacker, target, dealt)


func _update() -> void:
	var t: float = _elapsed / DURATION
	var size: float = lerpf(0.3, 1.0, 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t)) * radius
	_flash.scale = Vector3(size, size * 0.6, size)
	_material.albedo_color.a = 0.55 * (1.0 - t)
	_light.light_energy = 6.0 * (1.0 - t) * (1.0 - t)
