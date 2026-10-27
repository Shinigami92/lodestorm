class_name LocationHazards
extends RefCounted
## The biome's hazard in a generated location (see `LocationBiome.Hazard`): slick ice on the frozen
## lakes, vents in the vent fields, patches of shards in the shard gardens, mud in the mires' pools;
## never on a lane or in the landing yard (the lakes and pools come with their areas, see
## `LocationFeatures`). Planned with the location (plain data, safe on a worker thread); `build`
## adds the zones (`GroundHazard`). All values greybox, TBD (playtest).

## A vent's reach (its burst's circle), in m, and how many a vent field has (fewest, most).
const VENT_RADIUS: float = 3.0
const VENTS_PER_FIELD: Vector2i = Vector2i(5, 8)
## A patch of shards' radius (smallest, largest), in m, and how many a shard garden has.
const SHARD_PATCH_RADIUS: Vector2 = Vector2(2.0, 3.5)
const SHARD_PATCHES: Vector2i = Vector2i(3, 5)

## Where it lies (x, z, radius), location-local.
var spots: Array[Vector3] = []

var _location: GeneratedLocation


func _init(location: GeneratedLocation) -> void:
	_location = location


## Places it where it lies in spots: vents in every vent field, patches of shards in every shard
## garden; on gentle ground off the lanes, apart (see `GeneratedLocation.find_site`).
func place(rng: RandomNumberGenerator) -> void:
	var kind: LocationLayout.Kind
	var count: Vector2i
	var radii: Vector2
	match _location.biome.hazard:
		LocationBiome.Hazard.VENTS:
			kind = LocationLayout.Kind.VENT_FIELD
			count = VENTS_PER_FIELD
			radii = Vector2.ONE * VENT_RADIUS
		LocationBiome.Hazard.SHARDS:
			kind = LocationLayout.Kind.SHARD_GARDEN
			count = SHARD_PATCHES
			radii = SHARD_PATCH_RADIUS
		_:
			return
	for area: LocationLayout.Area in _location.layout.areas:
		if area.kind != kind:
			continue
		for spot: int in rng.randi_range(count.x, count.y):
			var radius: float = radii.x if radii.x == radii.y else rng.randf_range(radii.x, radii.y)
			var site: Vector3 = _location.find_site(
				rng,
				radius,
				func(at: Vector2) -> bool: return _location.landing_distance(at) >= 10.0,
				area.center,
				area.radius * 0.8
			)
			if site != Vector3.INF:
				_location.add_site(site, radius, 0.5)
				spots.append(Vector3(site.x, site.z, radius))


## Adds its zones to `location` (under `Hazards`): slick ice, vents, shards or mud.
func build(location: GeneratedLocation) -> void:
	if spots.is_empty():
		return
	var biome: LocationBiome = location.biome
	var holder := Node3D.new()
	holder.name = "Hazards"
	location.add_child(holder)
	for i: int in spots.size():
		var at: Vector3 = spots[i]
		var zone: GroundHazard
		match biome.hazard:
			LocationBiome.Hazard.VENTS:
				var vent := GroundVent.new()
				vent.name = "Vent%d" % (i + 1)
				vent.damage = biome.hazard_damage
				vent.radius = at.z
				zone = vent
			LocationBiome.Hazard.SHARDS:
				var shards := GroundShards.new()
				shards.name = "Shards%d" % (i + 1)
				shards.damage_per_second = biome.hazard_damage
				shards.radius = at.z
				zone = shards
			LocationBiome.Hazard.MUD:
				var mud := GroundMud.new()
				mud.name = "Mud%d" % (i + 1)
				mud.speed = biome.hazard_speed
				mud.radius = at.z
				mud.color = biome.hazard_tint
				zone = mud
			_:
				zone = GroundHazard.new()
				zone.name = "SlickIce%d" % (i + 1)
				zone.grip = biome.hazard_grip
		zone.collision_layer = 0
		zone.collision_mask = PhysicsLayers.WORLD
		var cylinder := CylinderShape3D.new()
		cylinder.radius = at.z
		cylinder.height = 3.0
		var shape := CollisionShape3D.new()
		shape.shape = cylinder
		shape.position.y = 0.5
		zone.add_child(shape)
		zone.position = Vector3(at.x, location.terrain.height_at(at.x, at.y), at.y)
		holder.add_child(zone)
