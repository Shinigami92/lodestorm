class_name PaletteViewer
extends Control
## Developer tool (2D): every color the game uses side by side, read from where the game keeps
## them (the ores, the players, the suit ring, the menus, ...), normal and as seen with the three
## common color blindnesses (see `ColorVision`). Check a new color here before using it, against
## the ones it will be seen with. Colors' alpha and glow are left out: the tiles show the hue.
## The list on the right (one vision at a time) names the pairs that look closest: colors of the
## same group, or of two groups seen together during a run (`Group.on_ground`), that look nearly
## the same with that vision; with a color blindness only the ones that look apart normally (what
## that vision loses). Ores also differ by crystal shape and glow pattern, players by their number,
## so a close pair there is a hint, not an error.
## Keys: 0 all four visions, 1–4 one vision with names and the close pairs, S save a picture
## (`user://palette_viewer/`). The mouse over a tile names it.
## From the command line it saves one picture and quits:
## `"$GODOT4_EDITOR" --path . game/debug/palette_viewer.tscn -- --vision=2 --shot=tmp/palette.png`
## (`--vision`: 0 all four, 1 normal, 2 protanopia, 3 deuteranopia, 4 tritanopia).

## Pairs closer than this (OKLab distance) are listed. TBD (playtest).
const CLOSE: float = 0.08
## Pairs closer than this with normal vision are the same color used twice, on purpose.
const SAME: float = 0.02
## Most pairs listed.
const PAIRS_SHOWN: int = 24
const BACKGROUND := Color(0.08, 0.08, 0.1)
const TEXT := Color(0.85, 0.85, 0.88)
const DIM_TEXT := Color(0.55, 0.55, 0.6)
const MARGIN: float = 16.0
const INFO_HEIGHT: float = 36.0
const LABEL_WIDTH: float = 180.0
const GAP: float = 4.0
const STAR_SYSTEM: String = "res://game/world/star_system.tres"
const SKILL_TREE: String = "res://game/progression/skills/tree/skill_tree.tres"
const ARSENAL: String = "res://game/weapons/all_weapons.tres"
const CREW: String = "res://game/npcs/crew"


## A color and what it's for.
class Swatch:
	var label: String
	var color: Color
	## The title of its group.
	var group: String

	func _init(p_label: String, p_color: Color, p_group: String) -> void:
		label = p_label
		color = Color(p_color, 1.0)
		group = p_group


## Colors that belong together. Groups seen together on the ground during a run are compared with
## each other; the others (menus, the map) only within themselves.
class Group:
	var title: String
	var on_ground: bool
	var swatches: Array[Swatch] = []

	func _init(p_title: String, p_on_ground: bool) -> void:
		title = p_title
		on_ground = p_on_ground

	func add(label: String, color: Color) -> Group:
		swatches.append(Swatch.new(label, color, title))
		return self


## Two colors that look nearly the same with one vision.
class Pair:
	var a: Swatch
	var b: Swatch
	var distance: float

	func _init(p_a: Swatch, p_b: Swatch, p_distance: float) -> void:
		a = p_a
		b = p_b
		distance = p_distance


## -1: all four side by side, else the `ColorVision.Vision` shown alone.
var vision: int = -1

var _groups: Array[Group] = []
## Where each tile was drawn last (for the mouse), and the swatch under the mouse.
var _tiles: Array[Rect2] = []
var _tile_swatches: Array[Swatch] = []
var _hovered: Swatch


func _ready() -> void:
	_groups = groups()
	var shot: String = ""
	for argument: String in OS.get_cmdline_user_args():
		var value: String = argument.get_slice("=", 1)
		match argument.get_slice("=", 0):
			"--vision":
				vision = clampi(value.to_int(), 0, ColorVision.Vision.size()) - 1
			"--shot":
				shot = value
	resized.connect(queue_redraw)
	if not shot.is_empty():
		await get_tree().create_timer(0.5).timeout
		var image: Image = get_viewport().get_texture().get_image()
		image.save_png(ProjectSettings.globalize_path("res://").path_join(shot))
		get_tree().quit()


## Every color the game uses, by group.
static func groups() -> Array[Group]:
	var result: Array[Group] = []
	var players := Group.new("Players", true)
	for i: int in Player.COLORS.size():
		players.add("Player %d" % (i + 1), Player.COLORS[i])
	result.append(players)
	var ores := Group.new("Ores", true)
	for ore_type: OreType in OreCatalog.all().ores:
		ores.add(ore_type.display_name, ore_type.color)
	result.append(ores)
	result.append(
		(
			Group
			. new("The hive", true)
			. add("Eyes, nest glow, ichor", AlienNest.COLOR_GLOW)
			. add("Sparks off armor", HitSpray.COLOR_SPARK)
			. add("Armor chips", HitSpray.COLOR_CHIP)
		)
	)
	result.append(
		(
			Group
			. new("Silhouettes", true)
			. add("Player", OccludedSilhouette.PLAYER_COLOR)
			. add("Alien", OccludedSilhouette.ALIEN_COLOR)
			. add("Miner", OccludedSilhouette.MINER_COLOR)
			. add("Crate", OccludedSilhouette.CRATE_COLOR)
		)
	)
	result.append(
		(
			Group
			. new("Health", true)
			. add("Healthy", SuitLight.COLOR_HEALTHY)
			. add("Below half", SuitLight.COLOR_HURT)
			. add("Critical", SuitLight.COLOR_CRITICAL)
		)
	)
	var ammo := Group.new("Ammo", true)
	for weapon: WeaponType in (load(ARSENAL) as Arsenal).weapons:
		var color: Variant = _ammo_color(weapon)
		if color is Color:
			ammo.add(weapon.display_name, color as Color)
	ammo.add("Nearly empty", AmmoGauge.WARNING)
	ammo.add("Empty", AmmoGauge.EMPTY)
	ammo.add("Timing window", AmmoGauge.TIMING)
	result.append(ammo)
	result.append(
		(
			Group
			. new("Suit ring", true)
			. add("Dash", SuitRing.DASH_COLOR)
			. add("Giving ammo", SuitRing.GIVE_COLOR)
			. add("Misses, hit marks", SuitRing.FUMBLE_COLOR)
		)
	)
	result.append(
		(
			Group
			. new("Ship status", true)
			. add("Calm", Ship.COLOR_CALM)
			. add("Half time", Ship.COLOR_HALF)
			. add("Last minute", Ship.COLOR_WARNING)
			. add("Returned", Ship.COLOR_RETURNED)
			. add("Lost", Ship.COLOR_LOST)
		)
	)
	result.append(
		Group.new("Mission", true).add("Miner alarm", Miner.COLOR_ALARM).add(
			"Damage numbers", DamageNumber.COLOR
		)
	)
	result.append(
		(
			Group
			. new("Menus", false)
			. add("Frames, text", SkillStation.FRAME_COLOR)
			. add("Highlight", StationPart.SELECTED_COLOR)
			. add("Missing, warning", OreCost.MISSING_COLOR)
			. add("MK pips", MkPips.COLOR_LIT)
			. add("Heat", HeatShieldStation.HEAT_COLOR)
			. add("Plate installed", HeatShieldCard.INSTALLED_COLOR)
			. add("Ship on the map", NavigatorStation.SHIP_COLOR)
			. add("Landmarks", HoloTable.LANDMARK_COLOR)
		)
	)
	var danger := Group.new("Danger", false)
	for i: int in NavigatorCard.DANGER_COLORS.size():
		danger.add("Danger %d" % (i + 1), NavigatorCard.DANGER_COLORS[i])
	result.append(danger)
	var clusters := Group.new("Skill clusters", false)
	for cluster: SkillCluster in (load(SKILL_TREE) as SkillTree).clusters:
		clusters.add(cluster.display_name, cluster.color)
	result.append(clusters)
	var star_system := load(STAR_SYSTEM) as StarSystem
	var biomes := Group.new("Biomes on the map", false)
	var seen: Array[LocationBiome] = []
	var bodies := Group.new("Star, bodies", false).add("Star", star_system.star_color)
	for body: CelestialBody in star_system.bodies:
		bodies.add(body.display_name, body.color)
		for region: Region in body.regions:
			if region.biome and region.biome not in seen:
				seen.append(region.biome)
				biomes.add(region.biome.display_name, region.biome.map_color)
	result.append(biomes)
	result.append(bodies)
	var crew := Group.new("Crew", false)
	for file: String in ResourceLoader.list_directory(CREW):
		if not file.ends_with(".tres"):
			continue
		var profile := load(CREW.path_join(file)) as NpcProfile
		if profile:
			crew.add(profile.display_name, profile.accent_color)
	result.append(crew)
	return result


## The pairs of `all` that look closest with `seen_with` (see `CLOSE`; with a color blindness only
## the ones that look apart normally), closest first.
static func close_pairs(all: Array[Group], seen_with: ColorVision.Vision) -> Array[Pair]:
	var pairs: Array[Pair] = []
	for i: int in all.size():
		for j: int in range(i, all.size()):
			if i != j and not (all[i].on_ground and all[j].on_ground):
				continue
			var first: Array[Swatch] = all[i].swatches
			var second: Array[Swatch] = all[j].swatches
			for k: int in first.size():
				for l: int in range(k + 1 if i == j else 0, second.size()):
					var a: Swatch = first[k]
					var b: Swatch = second[l]
					var normally: float = ColorVision.distance(a.color, b.color)
					if (
						normally < SAME
						or seen_with != ColorVision.Vision.NORMAL and normally < CLOSE
					):
						continue
					var apart: float = ColorVision.distance(a.color, b.color, seen_with)
					if apart < CLOSE:
						pairs.append(Pair.new(a, b, apart))
	pairs.sort_custom(func(p: Pair, q: Pair) -> bool: return p.distance < q.distance)
	return pairs


## The ammo color of a ranged weapon's gauge (its scene's `AmmoGauge`), or null.
static func _ammo_color(weapon: WeaponType) -> Variant:
	if weapon.kind != WeaponType.Kind.RANGED or not weapon.scene:
		return null
	var state: SceneState = weapon.scene.get_state()
	for node: int in state.get_node_count():
		if state.get_node_name(node) != &"AmmoGauge":
			continue
		var script: Script = null
		for property: int in state.get_node_property_count(node):
			match state.get_node_property_name(node, property):
				&"color":
					return state.get_node_property_value(node, property)
				&"script":
					script = state.get_node_property_value(node, property) as Script
		if script:
			return script.get_property_default_value(&"color")
	return null


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if not key or not key.pressed:
		return
	match key.keycode:
		KEY_0:
			vision = -1
		KEY_1, KEY_2, KEY_3, KEY_4:
			vision = key.keycode - KEY_1
		KEY_S:
			_save()
			return
		_:
			return
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if not motion:
		return
	var hovered: Swatch = null
	for i: int in _tiles.size():
		if _tiles[i].has_point(motion.position):
			hovered = _tile_swatches[i]
	if hovered != _hovered:
		_hovered = hovered
		queue_redraw()


func _draw() -> void:
	_tiles.clear()
	_tile_swatches.clear()
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)
	var area := Rect2(
		Vector2(MARGIN, MARGIN + INFO_HEIGHT),
		size - Vector2(2.0 * MARGIN, 2.0 * MARGIN + INFO_HEIGHT)
	)
	if vision < 0:
		var half: Vector2 = (area.size - Vector2(MARGIN, MARGIN)) * 0.5
		for v: int in ColorVision.Vision.size():
			var corner := Vector2(v % 2, floorf(v / 2.0))
			var rect := Rect2(area.position + corner * (half + Vector2(MARGIN, MARGIN)), half)
			_draw_palette(rect, v as ColorVision.Vision, Vector2(26.0, 22.0), false)
	else:
		var list_width: float = 560.0
		var left := Rect2(area.position, area.size - Vector2(list_width + MARGIN, 0.0))
		_draw_palette(left, vision as ColorVision.Vision, Vector2(120.0, 30.0), true)
		var right := Rect2(
			Vector2(area.end.x - list_width, area.position.y), Vector2(list_width, area.size.y)
		)
		_draw_pairs(right, vision as ColorVision.Vision)
	_draw_info()


func _draw_info() -> void:
	var font: Font = get_theme_default_font()
	var text: String = "0: all four  1–4: one vision with names and close pairs  S: save picture"
	if _hovered:
		text = "%s: %s  #%s" % [_hovered.group, _hovered.label, _hovered.color.to_html(false)]
		for v: int in range(1, ColorVision.Vision.size()):
			var seen: Color = ColorVision.simulate(_hovered.color, v as ColorVision.Vision)
			text += (
				"  %s #%s"
				% [
					ColorVision.NAMES[v as ColorVision.Vision].get_slice(" ", 0),
					seen.to_html(false)
				]
			)
	draw_string(font, Vector2(MARGIN, MARGIN + 18.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, TEXT)


## The groups in rows inside `rect`, with tiles of `tile` size (wrapping when a row is full).
func _draw_palette(rect: Rect2, seen_with: ColorVision.Vision, tile: Vector2, named: bool) -> void:
	var font: Font = get_theme_default_font()
	draw_string(
		font,
		rect.position + Vector2(0.0, 18.0),
		ColorVision.NAMES[seen_with],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		18,
		TEXT
	)
	var at := Vector2(rect.position.x, rect.position.y + 30.0)
	for group: Group in _groups:
		draw_string(
			font,
			at + Vector2(0.0, tile.y * 0.5 + 5.0),
			group.title,
			HORIZONTAL_ALIGNMENT_LEFT,
			LABEL_WIDTH - GAP,
			14,
			TEXT if group.on_ground else DIM_TEXT
		)
		var x: float = rect.position.x + LABEL_WIDTH
		for swatch: Swatch in group.swatches:
			if x + tile.x > rect.end.x:
				x = rect.position.x + LABEL_WIDTH
				at.y += tile.y + GAP
			var box := Rect2(Vector2(x, at.y), tile)
			_draw_tile(box, swatch, seen_with, named)
			x += tile.x + GAP
		at.y += tile.y + GAP * 2.0


func _draw_tile(box: Rect2, swatch: Swatch, seen_with: ColorVision.Vision, named: bool) -> void:
	var seen: Color = ColorVision.simulate(swatch.color, seen_with)
	draw_rect(box, seen)
	if swatch == _hovered:
		draw_rect(box.grow(2.0), Color.WHITE, false, 2.0)
	_tiles.append(box)
	_tile_swatches.append(swatch)
	if named:
		var ink: Color = Color.BLACK if ColorVision.oklab(seen).x > 0.65 else Color.WHITE
		draw_string(
			get_theme_default_font(),
			box.position + Vector2(4.0, box.size.y * 0.5 + 4.0),
			swatch.label,
			HORIZONTAL_ALIGNMENT_LEFT,
			box.size.x - 8.0,
			12,
			ink
		)


func _draw_pairs(rect: Rect2, seen_with: ColorVision.Vision) -> void:
	var font: Font = get_theme_default_font()
	var pairs: Array[Pair] = close_pairs(_groups, seen_with)
	var title: String = "Look closest (under %.2f): %d" % [CLOSE, pairs.size()]
	draw_string(
		font, rect.position + Vector2(0.0, 18.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, TEXT
	)
	var at := Vector2(rect.position.x, rect.position.y + 30.0)
	var tile := Vector2(28.0, 22.0)
	for i: int in mini(pairs.size(), PAIRS_SHOWN):
		var pair: Pair = pairs[i]
		draw_rect(Rect2(at, tile), ColorVision.simulate(pair.a.color, seen_with))
		draw_rect(
			Rect2(at + Vector2(tile.x, 0.0), tile), ColorVision.simulate(pair.b.color, seen_with)
		)
		var text: String = "%.3f  %s / %s" % [pair.distance, _named(pair.a), _named(pair.b)]
		draw_string(
			font,
			at + Vector2(2.0 * tile.x + 10.0, tile.y * 0.5 + 5.0),
			text,
			HORIZONTAL_ALIGNMENT_LEFT,
			rect.size.x - 2.0 * tile.x - 10.0,
			14,
			TEXT
		)
		at.y += tile.y + GAP
	if pairs.size() > PAIRS_SHOWN:
		draw_string(
			font,
			at + Vector2(0.0, 16.0),
			"and %d more" % (pairs.size() - PAIRS_SHOWN),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			14,
			DIM_TEXT
		)


func _named(swatch: Swatch) -> String:
	return "%s (%s)" % [swatch.label, swatch.group]


func _save() -> void:
	var directory: String = "user://palette_viewer"
	DirAccess.make_dir_recursive_absolute(directory)
	var image: Image = get_viewport().get_texture().get_image()
	var file: String = directory.path_join("vision_%d.png" % (vision + 1))
	image.save_png(file)
	print("Saved ", ProjectSettings.globalize_path(file))
