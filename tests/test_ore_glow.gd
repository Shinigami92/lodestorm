extends GutTest
## The ores' glow patterns: sane brightness, calm enough (photosensitivity), and materials that
## follow their ore type.

const ORE_NODE: PackedScene = preload("res://scenes/mining/ore_node.tscn")
## No pattern brightens more often than this per second (photosensitivity).
const MAX_PEAKS_PER_SECOND: int = 3
## A change in brightness smaller than this doesn't count as a peak.
const PROMINENCE: float = 0.03
const SAMPLES_PER_SECOND: float = 240.0
const SECONDS: float = 10.0


func test_every_pattern_stays_in_a_sane_range() -> void:
	for glow: int in OreType.Glow.values():
		var lowest: float = INF
		var highest: float = -INF
		for value: float in _samples(glow as OreType.Glow, 0.0):
			lowest = minf(lowest, value)
			highest = maxf(highest, value)
		var label: String = OreType.Glow.keys()[glow]
		assert_gte(lowest, 0.4, "%s never goes dark" % label)
		assert_lte(highest, 1.3, "%s doesn't blow out" % label)
		assert_gte(highest, 0.95, "%s reaches the full glow" % label)
		if glow not in [OreType.Glow.STEADY, OreType.Glow.SHIFTING]:
			assert_gt(highest - lowest, 0.15, "%s is visible" % label)


func test_no_pattern_flashes_more_than_three_times_a_second() -> void:
	for glow: int in OreType.Glow.values():
		for phase: float in [0.0, 3.7]:
			var peaks: Array[float] = _peaks(_samples(glow as OreType.Glow, phase))
			var label: String = "%s phase %s" % [OreType.Glow.keys()[glow], phase]
			var most: int = 0
			for i: int in peaks.size():
				var in_window: int = 0
				for later: float in peaks.slice(i):
					if later < peaks[i] + 1.0:
						in_window += 1
				most = maxi(most, in_window)
			assert_lte(most, MAX_PEAKS_PER_SECOND, "%s: %d peaks in a second" % [label, most])


func test_patterns_differ_and_move() -> void:
	assert_eq(OreGlow.intensity(OreType.Glow.STEADY, 3.0), 1.0)
	var heartbeat: Array[float] = _samples(OreType.Glow.HEARTBEAT, 0.0)
	# A double beat: two peaks per beat.
	assert_almost_eq(_peaks(heartbeat).size(), roundi(2.0 * 1.1 * SECONDS), 1)
	assert_almost_eq(_peaks(_samples(OreType.Glow.SLOW_PULSE, 0.0)).size(), 4, 1)
	assert_gt(_peaks(_samples(OreType.Glow.FLICKER, 0.0)).size(), 5, "flickers irregularly")


func test_phase_shifts_the_rhythm() -> void:
	for glow: int in OreType.Glow.values():
		assert_almost_eq(
			OreGlow.intensity(glow as OreType.Glow, 2.0, 1.5),
			OreGlow.intensity(glow as OreType.Glow, 3.5),
			0.0001
		)
	var a: float = OreGlow.phase_at(Vector3(4.0, 0.0, 9.0))
	assert_eq(OreGlow.phase_at(Vector3(4.0, 2.0, 9.0)), a, "a miner shares its deposit's phase")
	assert_between(a, 0.0, OreGlow.PHASE_SPREAD)
	var phases: Array[float] = []
	for i: int in 8:
		var phase: float = OreGlow.phase_at(Vector3(i * 6.0, 0.0, i * -3.0))
		if phase not in phases:
			phases.append(phase)
	assert_gt(phases.size(), 6, "neighboring deposits don't pulse in sync")


func test_materials_follow_the_ore_type() -> void:
	for ore_type: OreType in OreCatalog.all().ores:
		var crystal := ore_type.get_material() as ShaderMaterial
		var fill := ore_type.get_glow_material() as ShaderMaterial
		assert_not_null(crystal, ore_type.display_name)
		assert_not_null(fill, ore_type.display_name)
		assert_eq(crystal.shader, OreGlow.CRYSTAL_SHADER)
		assert_eq(fill.shader, OreGlow.FILL_SHADER)
		for material: ShaderMaterial in [crystal, fill]:
			var color: Color = material.get_shader_parameter(&"color")
			var glow: int = material.get_shader_parameter(&"glow")
			var dark_body: bool = material.get_shader_parameter(&"dark_body")
			assert_eq(color, ore_type.color, ore_type.display_name)
			assert_eq(glow, int(ore_type.glow), ore_type.display_name)
			assert_eq(dark_body, ore_type.dark_body, ore_type.display_name)
		assert_eq(ore_type.get_material(), crystal, "shared per ore type")


func test_ore_node_crystals_share_a_phase() -> void:
	var node := ORE_NODE.instantiate() as OreNode
	node.ore_type = OreCatalog.all().ores[0]
	node.position = Vector3(12.0, 0.0, -7.0)
	add_child_autofree(node)
	for crystal: MeshInstance3D in node.get_node("Crystals").get_children():
		var phase: float = crystal.get_instance_shader_parameter(&"phase")
		assert_eq(phase, OreGlow.phase_at(node.position))


## Ore icons are mipmapped, so they scale down cleanly on the cards.
func test_ore_icons_have_mipmaps() -> void:
	for ore_type: OreType in OreCatalog.all().ores:
		if not ore_type.icon:
			continue
		var config := ConfigFile.new()
		assert_eq(config.load(ore_type.icon.resource_path + ".import"), OK)
		var mipmaps: bool = config.get_value("params", "mipmaps/generate", false)
		assert_true(mipmaps, "%s: mipmaps/generate" % ore_type.icon.resource_path)


func _samples(glow: OreType.Glow, phase: float) -> Array[float]:
	var values: Array[float] = []
	for i: int in roundi(SECONDS * SAMPLES_PER_SECOND):
		values.append(OreGlow.intensity(glow, i / SAMPLES_PER_SECOND, phase))
	return values


## Times (seconds) of the peaks in `values`: highs that rise and fall by at least `PROMINENCE`.
func _peaks(values: Array[float]) -> Array[float]:
	var peaks: Array[float] = []
	var low: float = values[0]
	var high: float = values[0]
	var high_at: int = 0
	var rising: bool = true
	for i: int in values.size():
		var value: float = values[i]
		if rising:
			if value > high:
				high = value
				high_at = i
			elif value < low:
				low = value
				high = value
				high_at = i
			elif high - value >= PROMINENCE and high - low >= PROMINENCE:
				peaks.append(high_at / SAMPLES_PER_SECOND)
				rising = false
				low = value
		elif value < low:
			low = value
		elif value - low >= PROMINENCE:
			rising = true
			high = value
			high_at = i
	return peaks
