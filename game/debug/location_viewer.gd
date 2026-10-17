extends Control
## Developer tool (2D): plans generated locations and draws them from above, to check layouts
## faster than in the game. Light ground is walkable from the ship, dark ground isn't; magenta
## marks spots a player could fall to without a way back (should be none). Yellow lines are the
## passes, rings the areas (with their kind and the walking distance from the ship), dots the ore
## nodes in their ore's color, red rings the nests, faint stripes the lanes kept free. Amber
## rings are map parts (their footprint, the props' circle and their name; a set piece's name in
## capitals), amber squares their crates, amber diamonds their quest sites.
## The white arrow shows where the camera looks (the rock on its side stays low to see over).
## Keys: Left/Right seed, Up/Down number of areas, B next biome, G next region (its biome and set
## pieces; none: only the biome's points of interest), V camera view on and off, R random seed,
## S save a picture (`user://location_viewer/`).
## From the command line it saves one picture and quits:
## `"$GODOT4_EDITOR" --path . game/debug/location_viewer.tscn -- --seed=3 --areas=11
## --biome=1 --region=0 --view=1 --shot=tmp/layout.png` (`--biome`: index into `BIOMES`,
## `--region`: index into the star system's regions (-1: none), `--view=0`: no camera view).

const LOCATION: PackedScene = preload("res://game/locations/generated_location.tscn")
const BIOMES: Array[LocationBiome] = [
	preload("res://game/locations/biomes/dust.tres"),
	preload("res://game/locations/biomes/overgrowth.tres"),
]
const STAR_SYSTEM: StarSystem = preload("res://game/world/star_system.tres")
const PART_COLOR := Color(1.0, 0.75, 0.3)
## Where the camera looks in the game when the ship's nose points along -x (the isometric view).
const VIEW := Vector3(-0.577, -0.577, -0.577)
## Player speed on foot, in m/s (`PlayerSettings.move_speed`), to show distances as walking time.
const WALK_SPEED: float = 6.0
const KIND_COLORS: Dictionary[LocationLayout.Kind, Color] = {
	LocationLayout.Kind.LANDING: Color(0.35, 0.8, 1.0),
	LocationLayout.Kind.BASIN: Color(0.85, 0.85, 0.85),
	LocationLayout.Kind.CROSSROADS: Color(0.85, 0.85, 0.85),
	LocationLayout.Kind.ORE_POCKET: Color(0.75, 0.5, 1.0),
	LocationLayout.Kind.NEST_HOLLOW: Color(1.0, 0.3, 0.3),
	LocationLayout.Kind.PLATEAU: Color(0.45, 0.95, 0.8),
	LocationLayout.Kind.CRATER: Color(1.0, 0.6, 0.25),
}

var world_seed: int = 1
var area_count: int = 11
var biome_index: int = 0
var with_view: bool = true
## Index into `_regions`, or -1.
var region_index: int = -1

var _location: GeneratedLocation
var _picture: ImageTexture
var _took: int = 0
var _stuck: PackedVector2Array
## Screen pixels per m, and where the location's origin is on the screen.
var _zoom: float = 1.0
var _offset: Vector2 = Vector2.ZERO

@onready var _info: Label = $Info
@onready var _regions: Array[Region] = _all_regions()


func _ready() -> void:
	var shot: String = ""
	for argument: String in OS.get_cmdline_user_args():
		var value: String = argument.get_slice("=", 1)
		match argument.get_slice("=", 0):
			"--seed":
				world_seed = value.to_int()
			"--areas":
				area_count = value.to_int()
			"--biome":
				biome_index = clampi(value.to_int(), 0, BIOMES.size() - 1)
			"--view":
				with_view = value.to_int() != 0
			"--region":
				region_index = clampi(value.to_int(), -1, _regions.size() - 1)
			"--shot":
				shot = value
	_generate()
	resized.connect(queue_redraw)
	if not shot.is_empty():
		await get_tree().create_timer(0.5).timeout
		var image: Image = get_viewport().get_texture().get_image()
		image.save_png(ProjectSettings.globalize_path("res://").path_join(shot))
		get_tree().quit()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if not key or not key.pressed:
		return
	match key.keycode:
		KEY_RIGHT:
			world_seed += 1
		KEY_LEFT:
			world_seed = maxi(world_seed - 1, 1)
		KEY_UP:
			area_count += 1
		KEY_DOWN:
			area_count = maxi(area_count - 1, 2)
		KEY_B:
			biome_index = (biome_index + 1) % BIOMES.size()
		KEY_V:
			with_view = not with_view
		KEY_G:
			region_index = (region_index + 2) % (_regions.size() + 1) - 1
		KEY_R:
			world_seed = randi_range(1, 99999)
		KEY_S:
			_save()
			return
		_:
			return
	_generate()


func _exit_tree() -> void:
	if _location:
		_location.free()


func _generate() -> void:
	if _location:
		_location.free()
	_location = LOCATION.instantiate() as GeneratedLocation
	_location.biome = BIOMES[biome_index]
	var region: Region = _regions[region_index] if region_index >= 0 else null
	if region:
		_location.biome = region.biome
		_location.set_pieces = region.set_pieces
	_location.world_seed = world_seed
	_location.area_count = area_count
	_location.view_direction = VIEW if with_view else Vector3.ZERO
	var started: int = Time.get_ticks_msec()
	_location.plan()
	_took = Time.get_ticks_msec() - started
	_stuck = _location.stuck_spots()
	_picture = ImageTexture.create_from_image(_draw_ground())
	var layout: LocationLayout = _location.layout
	_info.text = (
		(
			"Seed %d · %s · %s · %d areas (%d asked) · %d passes, %d loops · %d m wide\n"
			+ "Farthest %d m along the passes (%d s on foot) · %d ore nodes · %d nests · "
			+ "%d parts · %d stuck spots · planned in %d ms\n"
			+ "Left/Right seed · Up/Down areas · B biome · G region · V view (%s) · R random · "
			+ "S save"
		)
		% [
			world_seed,
			region.display_name if region else "No region",
			_location.biome.display_name,
			layout.areas.size(),
			area_count,
			layout.passes.size(),
			layout.loops(),
			_location.size,
			layout.farthest(),
			layout.farthest() / WALK_SPEED,
			_location.planned_ore_sites().size(),
			_location.planned_nest_sites().size(),
			_location.parts.placed.size(),
			_stuck.size(),
			_took,
			"on" if with_view else "off",
		]
	)
	queue_redraw()


## The ground from above: shaded by its slope, light where it's walkable from the ship.
func _draw_ground() -> Image:
	var terrain: LocationTerrain = _location.terrain
	var side: int = terrain.cells + 1
	var image := Image.create(side, side, false, Image.FORMAT_RGB8)
	var light := Vector3(-0.6, 0.55, -0.6).normalized()
	var top: float = _location.biome.wall_height + _location.biome.rock_relief
	for z: int in side:
		for x: int in side:
			var at: Vector3 = terrain.point(x, z)
			var shade: float = clampf(terrain.normal(x, z).dot(light), 0.0, 1.0)
			var color: Color
			if _location.is_reachable(at.x, at.z):
				color = Color(0.78, 0.68, 0.52)
				if _location.is_on_lane(at.x, at.z):
					color = color.lerp(Color(0.95, 0.85, 0.55), 0.25)
			else:
				color = Color(0.3, 0.3, 0.33).lerp(
					Color(0.55, 0.55, 0.6), clampf(at.y / top, 0.0, 1.0)
				)
			image.set_pixel(x, z, color * (0.45 + 0.7 * shade))
	return image


func _draw() -> void:
	if not _picture:
		return
	var terrain: LocationTerrain = _location.terrain
	_zoom = minf(size.x, size.y) / terrain.size()
	_offset = (size - Vector2.ONE * terrain.size() * _zoom) * 0.5 - terrain.origin * _zoom
	draw_texture_rect(
		_picture, Rect2(_to_screen(terrain.origin), Vector2.ONE * terrain.size() * _zoom), false
	)
	var font: Font = get_theme_default_font()
	var site: Rect2 = _location.landing_site
	draw_rect(
		Rect2(_to_screen(site.position), site.size * _zoom), Color(0.35, 0.8, 1.0), false, 2.0
	)
	for way: LocationLayout.Pass in _location.layout.passes:
		var points := PackedVector2Array()
		for point: Vector2 in way.points:
			points.append(_to_screen(point))
		draw_polyline(points, Color(1.0, 0.85, 0.3, 0.8), 2.0)
	for area: LocationLayout.Area in _location.layout.areas:
		var color: Color = KIND_COLORS[area.kind]
		var center: Vector2 = _to_screen(area.center)
		draw_arc(center, area.radius * _zoom, 0.0, TAU, 48, color, 1.5)
		draw_circle(center, 5.0, color)
		if area.kind == LocationLayout.Kind.PLATEAU:
			draw_arc(
				_to_screen(Vector2(area.mesa.x, area.mesa.y)),
				area.mesa.z * _zoom,
				0.0,
				TAU,
				32,
				color,
				2.0
			)
			draw_line(
				_to_screen(area.ramp_start),
				_to_screen(area.ramp_start + area.ramp_direction * area.ramp_length),
				color,
				LocationLayout.RAMP_WIDTH * _zoom
			)
		var kind_name: String = LocationLayout.Kind.keys()[area.kind]
		var label: String = kind_name.capitalize()
		if area.kind != LocationLayout.Kind.LANDING:
			label += " %d m" % area.distance
		draw_string_outline(
			font, center + Vector2(8, -6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color.BLACK
		)
		draw_string(
			font, center + Vector2(8, -6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE
		)
	var ore_sites: Array[Vector3] = _location.planned_ore_sites()
	var ore_types: Array[OreType] = _location.planned_ore_types()
	for i: int in ore_sites.size():
		draw_circle(_to_screen(Vector2(ore_sites[i].x, ore_sites[i].z)), 4.0, ore_types[i].color)
	for nest: Vector3 in _location.planned_nest_sites():
		draw_arc(_to_screen(Vector2(nest.x, nest.z)), 6.0, 0.0, TAU, 16, Color(1.0, 0.2, 0.2), 2.5)
	_draw_parts(font)
	for spot: Vector2 in _stuck:
		draw_circle(_to_screen(spot), 3.0, Color(1.0, 0.0, 1.0))
	if with_view:
		var corner: Vector2 = _to_screen(terrain.origin) + Vector2(60.0, 60.0)
		var forward := Vector2(VIEW.x, VIEW.z).normalized()
		draw_line(corner - forward * 30.0, corner + forward * 30.0, Color.WHITE, 3.0)
		draw_circle(corner + forward * 30.0, 6.0, Color.WHITE)


## The map parts: footprint, props, name, crates and quest sites.
func _draw_parts(font: Font) -> void:
	for part: LocationParts.Placed in _location.parts.placed:
		var center: Vector2 = _to_screen(Vector2(part.origin.x, part.origin.z))
		draw_arc(center, part.info.footprint * _zoom, 0.0, TAU, 48, PART_COLOR, 2.0)
		draw_circle(center, part.info.prop_radius * _zoom, Color(PART_COLOR, 0.35))
		var front := Vector2(-sin(part.turn), -cos(part.turn))
		draw_line(center, center + front * part.info.footprint * _zoom, PART_COLOR, 2.0)
		for crate: Vector3 in part.markers(PartMarker.Kind.CRATE):
			var at: Vector2 = _to_screen(Vector2(crate.x, crate.z))
			draw_rect(Rect2(at - Vector2.ONE * 4.0, Vector2.ONE * 8.0), PART_COLOR)
		for anchor: Vector3 in part.markers(PartMarker.Kind.QUEST_ANCHOR):
			var at: Vector2 = _to_screen(Vector2(anchor.x, anchor.z))
			var diamond := PackedVector2Array(
				[at + Vector2(0, -6), at + Vector2(6, 0), at + Vector2(0, 6), at + Vector2(-6, 0)]
			)
			draw_colored_polygon(diamond, PART_COLOR)
		var label: String = part.info.display_name
		if part.set_piece:
			label = label.to_upper()
		var text_at: Vector2 = center + Vector2(8, 14)
		draw_string_outline(font, text_at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color.BLACK)
		draw_string(font, text_at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, PART_COLOR)


func _all_regions() -> Array[Region]:
	var regions: Array[Region] = []
	for body: CelestialBody in STAR_SYSTEM.bodies:
		regions.append_array(body.regions)
	return regions


## Location-local `at` (x, z) on the screen.
func _to_screen(at: Vector2) -> Vector2:
	return _offset + at * _zoom


func _save() -> void:
	DirAccess.make_dir_recursive_absolute("user://location_viewer")
	var path: String = (
		"user://location_viewer/%s_%d_%d.png"
		% [BIOMES[biome_index].resource_path.get_file().get_basename(), area_count, world_seed]
	)
	get_viewport().get_texture().get_image().save_png(path)
	print("Saved ", ProjectSettings.globalize_path(path))
