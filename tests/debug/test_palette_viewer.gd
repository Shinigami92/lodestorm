extends GutTest
## The palette viewer: every color the game uses, read from where the game keeps them, normal and
## as seen with the three common color blindnesses, with the pairs that look closest.

const VIEWER: PackedScene = preload("res://game/debug/palette_viewer.tscn")
const VISIONS: Array[ColorVision.Vision] = [
	ColorVision.Vision.PROTANOPIA, ColorVision.Vision.DEUTERANOPIA, ColorVision.Vision.TRITANOPIA
]


func test_greys_look_the_same_with_every_vision() -> void:
	for grey: Color in [Color.BLACK, Color(0.5, 0.5, 0.5), Color.WHITE]:
		for vision: ColorVision.Vision in VISIONS:
			var seen: Color = ColorVision.simulate(grey, vision)
			assert_almost_eq(ColorVision.distance(grey, seen), 0.0, 0.01, "%s %s" % [grey, vision])


func test_each_color_blindness_loses_its_own_contrast() -> void:
	var red := Color(0.75, 0.35, 0.15)
	var green := Color(0.3, 0.6, 0.15)
	var blue := Color(0.2, 0.45, 0.95)
	var red_green: float = ColorVision.distance(red, green)
	assert_lt(ColorVision.distance(red, green, ColorVision.Vision.PROTANOPIA), red_green * 0.6)
	assert_lt(ColorVision.distance(red, green, ColorVision.Vision.DEUTERANOPIA), red_green * 0.2)
	assert_gt(ColorVision.distance(red, green, ColorVision.Vision.TRITANOPIA), red_green * 0.9)
	var green_blue: float = ColorVision.distance(green, blue)
	assert_lt(ColorVision.distance(green, blue, ColorVision.Vision.TRITANOPIA), green_blue * 0.3)
	assert_gt(ColorVision.distance(green, blue, ColorVision.Vision.PROTANOPIA), green_blue * 0.9)
	assert_gt(ColorVision.distance(green, blue, ColorVision.Vision.DEUTERANOPIA), green_blue * 0.9)


func test_oklab_runs_from_black_to_white() -> void:
	assert_almost_eq(ColorVision.oklab(Color.BLACK).x, 0.0, 0.001)
	assert_almost_eq(ColorVision.oklab(Color.WHITE).x, 1.0, 0.001)
	assert_almost_eq(ColorVision.distance(Color.BLACK, Color.WHITE), 1.0, 0.001)


func test_lists_the_colors_from_their_sources() -> void:
	var colors: Dictionary[String, Array] = {}
	for group: PaletteViewer.Group in PaletteViewer.groups():
		var listed: Array[Color] = []
		for swatch: PaletteViewer.Swatch in group.swatches:
			listed.append(swatch.color)
			assert_eq(swatch.group, group.title)
		colors[group.title] = listed
	assert_eq(colors["Players"], Player.COLORS as Array)
	assert_eq(colors["Ores"].size(), OreCatalog.all().ores.size())
	for ore_type: OreType in OreCatalog.all().ores:
		assert_has(colors["Ores"], ore_type.color, ore_type.display_name)
	# The ranged weapons' ammo colors come from their scenes: Harl's warm white, Brask's orange.
	assert_has(colors["Ammo"], Color(1.0, 0.86, 0.66))
	assert_has(colors["Ammo"], Color(1.0, 0.55, 0.15))
	assert_false(colors["Crew"].is_empty())


func test_close_pairs_leave_out_colors_used_twice_on_purpose() -> void:
	var run := PaletteViewer.Group.new("Run", true)
	run.add("Blue", Color(0.2, 0.45, 0.95)).add("Same blue", Color(0.2, 0.45, 0.96))
	run.add("Green", Color(0.3, 0.6, 0.15)).add("Amber", Color(0.75, 0.55, 0.1))
	# Menus aren't compared with what's seen during a run.
	var menus := PaletteViewer.Group.new("Menus", false).add("Menu green", Color(0.3, 0.6, 0.15))
	var all: Array[PaletteViewer.Group] = [run, menus]
	assert_true(PaletteViewer.close_pairs(all, ColorVision.Vision.NORMAL).is_empty())
	var pairs: Array[PaletteViewer.Pair] = PaletteViewer.close_pairs(
		all, ColorVision.Vision.DEUTERANOPIA
	)
	assert_eq(pairs.size(), 1)
	assert_eq([pairs[0].a.label, pairs[0].b.label], ["Green", "Amber"])


func test_draws_every_view() -> void:
	var viewer := VIEWER.instantiate() as PaletteViewer
	add_child_autofree(viewer)
	for vision: int in range(-1, ColorVision.Vision.size()):
		viewer.vision = vision
		viewer.queue_redraw()
		await wait_process_frames(2)
	assert_engine_error_count(0)
