extends GutTest
## The map parts (points of interest and set pieces): their scenes, where generated locations put
## them, their crates and how they show in the hologram. The sweep over every region's set pieces
## is in `test_set_pieces_<part>.gd`.

const PARTS_DIR: String = "res://game/locations/parts/"
const LOCATION: PackedScene = preload("res://game/locations/generated_location.tscn")
const STAR_SYSTEM: StarSystem = preload("res://game/world/star_system.tres")
const SWEEP := preload("res://tests/support/location_sweep.gd")
const PLAYER_SCENE: PackedScene = preload("res://game/player/player.tscn")
const HOLO_TABLE: PackedScene = preload("res://game/ship/holo_table.tscn")
const SWEEP_SEEDS: Array[int] = [1, 2, 3, 4, 5]
## Seeds per biome in the sweep over every biome.
const BIOME_SEEDS: int = 3
## Width of the ring around the props that stays walkable at least, in m.
const RING: float = 2.5
## Room a player needs to pass, in m (about the capsule's radius).
const PLAYER_RADIUS: float = 0.45
## Grid the part tests check walkability on, in m.
const STEP: float = 0.25


func test_every_part_describes_its_scene() -> void:
	for scene: PackedScene in _part_scenes():
		var info: MapPart.Info = MapPart.describe(scene)
		var label: String = scene.resource_path.get_file()
		assert_false(info.display_name.is_empty(), label)
		assert_gt(info.footprint - info.prop_radius, RING, label + ": ring")
		assert_false(info.area_kinds.is_empty(), label)
		assert_does_not_have(info.area_kinds, LocationLayout.Kind.LANDING, label)
		assert_gt(info.marker_kinds.size(), 0, label + ": markers")
		# What planning reads from the file matches the scene.
		var part := scene.instantiate() as MapPart
		var markers: Array[Node] = part.find_children("*", "PartMarker", true, false)
		assert_eq(markers.size(), info.marker_spots.size(), label)
		for i: int in markers.size():
			var marker := markers[i] as PartMarker
			assert_eq(marker.kind, info.marker_kinds[i], label)
			var at: Vector3 = _relative(marker, part).origin
			assert_almost_eq(at.distance_to(info.marker_spots[i].origin), 0.0, 0.001, label)
			var flat := Vector2(at.x, at.z)
			assert_lt(flat.length(), info.footprint - 1.0, label + ": marker inside")
		part.free()


## Players walk all the way around the props, and reach every crate, quest site and ore marker.
func test_props_leave_a_walkable_ring() -> void:
	for scene: PackedScene in _part_scenes():
		var info: MapPart.Info = MapPart.describe(scene)
		var label: String = scene.resource_path.get_file()
		var part := scene.instantiate() as MapPart
		add_child_autofree(part)
		var shapes: Array[CollisionShape3D] = []
		shapes.assign(part.find_children("*", "CollisionShape3D", true, false))
		var cells: int = ceili(info.footprint / STEP)
		var side: int = cells * 2 + 1
		var blocked := PackedByteArray()
		blocked.resize(side * side)
		for z: int in side:
			for x: int in side:
				var at := Vector2(x - cells, z - cells) * STEP
				if at.length() > info.footprint:
					blocked[z * side + x] = 1
					continue
				if _blocked(shapes, at):
					blocked[z * side + x] = 1
					assert_lt(
						at.length(), info.prop_radius + PLAYER_RADIUS + STEP, label + ": prop"
					)
		# Walkable from the footprint's edge.
		var reached := PackedByteArray()
		reached.resize(side * side)
		var queue: Array[Vector2i] = []
		for z: int in side:
			for x: int in side:
				var at := Vector2(x - cells, z - cells) * STEP
				if not blocked[z * side + x] and at.length() > info.footprint - STEP * 2.0:
					reached[z * side + x] = 1
					queue.append(Vector2i(x, z))
		while not queue.is_empty():
			var cell: Vector2i = queue.pop_back()
			for next: Vector2i in [
				cell + Vector2i.LEFT,
				cell + Vector2i.RIGHT,
				cell + Vector2i.UP,
				cell + Vector2i.DOWN
			]:
				if next.x < 0 or next.y < 0 or next.x >= side or next.y >= side:
					continue
				var index: int = next.y * side + next.x
				if not blocked[index] and not reached[index]:
					reached[index] = 1
					queue.append(next)
		for z: int in side:
			for x: int in side:
				var at := Vector2(x - cells, z - cells) * STEP
				if at.length() > info.prop_radius + PLAYER_RADIUS and at.length() < info.footprint:
					assert_eq(reached[z * side + x], 1, "%s: ring at %s" % [label, at])
		for spot: Transform3D in info.marker_spots:
			var near: bool = false
			var at := Vector2(spot.origin.x, spot.origin.z)
			for z: int in side:
				for x: int in side:
					var cell := Vector2(x - cells, z - cells) * STEP
					if reached[z * side + x] and cell.distance_to(at) < 1.0:
						near = true
			assert_true(near, "%s: marker at %s" % [label, at])


## The biomes' points of interest come up about once per four areas, never two in one area, and
## their markers lead: ore nodes and nests on them.
func test_points_of_interest_and_markers_lead() -> void:
	for biome: LocationBiome in SWEEP.BIOMES:
		var parts: int = 0
		for world_seed: int in SWEEP.seeds(biome, BIOME_SEEDS):
			var location: GeneratedLocation = SWEEP.plan(world_seed, biome)
			var areas: Array[LocationLayout.Area] = []
			for part: LocationParts.Placed in location.parts.placed:
				assert_does_not_have(areas, part.area)
				areas.append(part.area)
				for ore: Vector3 in part.markers(PartMarker.Kind.ORE):
					assert_true(_has_site(location.sites.ore_positions(), ore), biome.display_name)
			parts += location.parts.placed.size()
			location.free()
		assert_gt(parts, BIOME_SEEDS, biome.display_name)


## A rich vein's markers hold the location's rarest ore.
func test_ore_markers_get_their_band() -> void:
	var vein: PackedScene = load(PARTS_DIR + "rich_vein.tscn")
	var glare: Region = _region("Glare Fields")
	var found: Array[OreType] = OreCatalog.sorted(glare.biome.ores)
	for world_seed: int in SWEEP_SEEDS:
		var location: GeneratedLocation = SWEEP.plan(world_seed, glare.biome, glare.set_pieces)
		for part: LocationParts.Placed in location.parts.placed:
			if part.placement.scene != vein:
				continue
			for ore: Vector3 in part.markers(PartMarker.Kind.ORE):
				for site: LocationSites.OreSite in location.sites.ores:
					var at := Vector2(site.position.x, site.position.z)
					if at.distance_to(Vector2(ore.x, ore.z)) < 0.01:
						assert_eq(site.ore, found[found.size() - 1])
		location.free()


## Built, the parts stand where planned with a crate on every crate marker: the given contents
## first, then supply caches.
func test_parts_and_crates_are_built() -> void:
	var outpost: Region = _region("Redscar Flats")
	var fragment := BlueprintFragment.new()
	var location := LOCATION.instantiate() as GeneratedLocation
	location.world_seed = 3
	location.area_count = SWEEP.AREAS
	location.biome = outpost.biome
	location.set_pieces = outpost.set_pieces
	location.crate_contents = [fragment]
	add_child_autofree(location)
	var built: Array[Node] = location.get_node("Parts").get_children()
	assert_eq(built.size(), location.parts.placed.size())
	for i: int in built.size():
		var part := built[i] as MapPart
		assert_not_null(part)
		assert_almost_eq(part.position, location.parts.placed[i].origin, Vector3.ONE * 0.001)
		assert_true(part.is_in_group(HoloTable.LANDMARK_GROUP))
	var crates: Array[Node] = location.find_children("*", "Crate", true, false)
	assert_gt(crates.size(), 0)
	assert_eq((crates[0] as Crate).content, fragment)
	for crate: Crate in crates.slice(1):
		assert_true(crate.content is SupplyCache)


## A crate opens once on `interact`: the opener's spare magazines fill up, its light goes dark.
func test_crate_refills_spares_once() -> void:
	var arena := Node3D.new()
	add_child_autofree(arena)
	var crate := (load(PARTS_DIR + "crate.tscn") as PackedScene).instantiate() as Crate
	arena.add_child(crate)
	var player := PLAYER_SCENE.instantiate() as Player
	player.position = Vector3(0.0, 0.0, -1.2)
	arena.add_child(player)
	await wait_physics_frames(2)
	var harl := player.get_ammo() as MagazineAmmo
	harl.spare_rounds = 0
	assert_eq(Interactable.nearest(get_tree(), player.global_position), crate)
	crate.use(player)
	assert_eq(harl.spare_rounds, player.spare_magazines * harl.capacity())
	assert_true(crate.opened)
	assert_false(crate.enabled)
	var strip := crate.get_node("Strip") as MeshInstance3D
	assert_false((strip.material_override as StandardMaterial3D).emission_enabled)
	harl.spare_rounds = 0
	crate.use(player)
	assert_eq(harl.spare_rounds, 0, "only once")
	await wait_seconds(Crate.OPEN_TIME + 0.1)
	assert_almost_eq((crate.get_node("Lid") as Node3D).rotation.x, Crate.LID_OPEN, 0.01)


## Points of interest show in the landmark color in the hologram; crates don't show.
func test_hologram_shows_parts_not_crates() -> void:
	var outpost: Region = _region("Redscar Flats")
	var location := LOCATION.instantiate() as GeneratedLocation
	location.world_seed = 3
	location.area_count = SWEEP.AREAS
	location.biome = outpost.biome
	location.set_pieces = outpost.set_pieces
	add_child_autofree(location)
	var table := HOLO_TABLE.instantiate() as HoloTable
	add_child_autofree(table)
	table.show_location(location)
	var crate_meshes: Array[Mesh] = []
	for crate: Node in location.find_children("*", "Crate", true, false):
		for mesh: MeshInstance3D in crate.find_children("*", "MeshInstance3D", true, false):
			crate_meshes.append(mesh.mesh)
	var part_meshes: Array[Mesh] = []
	for part: Node in location.get_node("Parts").get_children():
		for mesh: MeshInstance3D in part.find_children("*", "MeshInstance3D", true, false):
			if mesh.mesh not in crate_meshes:
				part_meshes.append(mesh.mesh)
	var landmarks: int = 0
	for copy: MeshInstance3D in table.get_node("Hologram/Content").get_children():
		assert_does_not_have(crate_meshes, copy.mesh)
		var color: Color = (copy.material_override as ShaderMaterial).get_shader_parameter(&"color")
		if copy.mesh in part_meshes:
			assert_eq(color, HoloTable.LANDMARK_COLOR)
			landmarks += 1
	assert_gt(landmarks, 0)
	assert_eq(table.get_landmark_markers().size(), location.parts.placed.size(), "a beam per part")


func _part_scenes() -> Array[PackedScene]:
	var scenes: Array[PackedScene] = []
	for file: String in ResourceLoader.list_directory(PARTS_DIR):
		if file.ends_with(".tscn") and file != "crate.tscn":
			scenes.append(load(PARTS_DIR + file) as PackedScene)
	assert_gt(scenes.size(), 4)
	return scenes


func _region(region_name: String) -> Region:
	for body: CelestialBody in STAR_SYSTEM.bodies:
		for region: Region in body.regions:
			if region.display_name == region_name:
				return region
	return null


func _has_site(sites: Array[Vector3], at: Vector3) -> bool:
	for site: Vector3 in sites:
		if Vector2(site.x, site.z).distance_to(Vector2(at.x, at.z)) < 0.01:
			return true
	return false


## Whether a player at part-local `at` (x, z) would touch one of `shapes` (checked at a few
## heights between the ankles and the head).
func _blocked(shapes: Array[CollisionShape3D], at: Vector2) -> bool:
	for collider: CollisionShape3D in shapes:
		var to_shape: Transform3D = collider.global_transform.affine_inverse()
		for height: float in [0.3, 0.9, 1.6]:
			var local: Vector3 = to_shape * Vector3(at.x, height, at.y)
			if _inside(collider.shape, local, PLAYER_RADIUS):
				return true
	return false


static func _inside(shape: Shape3D, local: Vector3, margin: float) -> bool:
	if shape is BoxShape3D:
		var half: Vector3 = (shape as BoxShape3D).size * 0.5 + Vector3.ONE * margin
		return absf(local.x) < half.x and absf(local.y) < half.y and absf(local.z) < half.z
	if shape is CylinderShape3D:
		var cylinder := shape as CylinderShape3D
		return (
			Vector2(local.x, local.z).length() < cylinder.radius + margin
			and absf(local.y) < cylinder.height * 0.5 + margin
		)
	if shape is SphereShape3D:
		return local.length() < (shape as SphereShape3D).radius + margin
	if shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		var reach: float = capsule.height * 0.5 - capsule.radius
		var axis: float = clampf(local.y, -reach, reach)
		return local.distance_to(Vector3(0.0, axis, 0.0)) < capsule.radius + margin
	return false


## `node`'s transform relative to `root` (one of its ancestors), also outside the tree.
static func _relative(node: Node3D, root: Node3D) -> Transform3D:
	var result: Transform3D = Transform3D.IDENTITY
	var at: Node = node
	while at and at != root:
		result = (at as Node3D).transform * result
		at = at.get_parent()
	return result
