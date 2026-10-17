extends GutTest
## The layout graph of generated locations, over many seeds and sizes (it's quick without the
## ground).

const DUST: LocationBiome = preload("res://game/locations/biomes/dust.tres")
const OVERGROWTH: LocationBiome = preload("res://game/locations/biomes/overgrowth.tres")
const LANDING := Vector3(66.0, 0.0, 36.0)
const KEEP_CLEAR := Rect2(-104.0, -34.0, 162.0, 68.0)
const SIZES: Array[int] = [6, 11, 16, 24]


func _layout(world_seed: int, count: int, biome: LocationBiome = DUST) -> LocationLayout:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	return LocationLayout.generate(rng, count, biome, LANDING, KEEP_CLEAR)


func _sweep(check: Callable) -> void:
	for biome: LocationBiome in [DUST, OVERGROWTH]:
		for count: int in SIZES:
			for world_seed: int in range(1, 11):
				check.call(
					_layout(world_seed, count, biome),
					"%s, %d areas, seed %d" % [biome.display_name, count, world_seed]
				)


func test_same_seed_same_layout() -> void:
	var first: LocationLayout = _layout(4, 11)
	var second: LocationLayout = _layout(4, 11)
	assert_eq(first.areas.size(), second.areas.size())
	for i: int in first.areas.size():
		assert_eq(first.areas[i].center, second.areas[i].center)
		assert_eq(first.areas[i].kind, second.areas[i].kind)
	assert_eq(first.passes.size(), second.passes.size())


## Every area can be walked to from the landing yard, which comes first.
func test_every_area_is_joined() -> void:
	_sweep(
		func(layout: LocationLayout, label: String) -> void:
			assert_eq(layout.areas[0].kind, LocationLayout.Kind.LANDING, label)
			assert_gte(layout.passes.size(), layout.areas.size() - 1, label)
			for area: LocationLayout.Area in layout.areas:
				assert_true(is_finite(area.distance), label)
	)


## Bigger locations get more areas (as many as asked for, in these sizes) and more loops.
func test_size_grows_with_the_area_count() -> void:
	_sweep(
		func(layout: LocationLayout, label: String) -> void:
			var asked: int = int(label.get_slice(", ", 1).to_int())
			assert_eq(layout.areas.size(), asked, label)
			if asked >= 11:
				assert_gte(layout.loops(), 1, label)
	)
	assert_gt(_layout(1, 24).farthest(), _layout(1, 6).farthest())


func test_areas_keep_apart_and_passes_never_cross() -> void:
	_sweep(
		func(layout: LocationLayout, label: String) -> void:
			for a: int in layout.areas.size():
				for b: int in range(a + 1, layout.areas.size()):
					var gap: float = layout.areas[a].center.distance_to(layout.areas[b].center)
					assert_gt(gap, layout.areas[a].radius + layout.areas[b].radius, label)
			for a: int in layout.passes.size():
				for b: int in range(a + 1, layout.passes.size()):
					var first: LocationLayout.Pass = layout.passes[a]
					var second: LocationLayout.Pass = layout.passes[b]
					if (
						first.from in [second.from, second.to]
						or first.to in [second.from, second.to]
					):
						continue
					assert_false(
						_cross(first.points, second.points), "%s: passes %d and %d" % [label, a, b]
					)
	)


## The farthest dead ends hold the rich ore, the next ones nests; their number grows with the
## layout.
func test_dead_ends_hold_ore_pockets_and_nest_hollows() -> void:
	_sweep(
		func(layout: LocationLayout, label: String) -> void:
			var pockets: int = 0
			var hollows: int = 0
			for area: LocationLayout.Area in layout.areas:
				if area.kind == LocationLayout.Kind.ORE_POCKET:
					pockets += 1
					assert_eq(area.passes.size(), 1, label)
					assert_gte(area.distance, _median_distance(layout), label)
				elif area.kind == LocationLayout.Kind.NEST_HOLLOW:
					hollows += 1
					assert_eq(area.passes.size(), 1, label)
			assert_gte(pockets, 1, label)
			if layout.areas.size() >= 20:
				assert_gte(pockets + hollows, 3, label)
	)


## A plateau's mesa and ramp lie inside its area.
func test_plateaus_fit_their_area() -> void:
	# A lambda can't change a captured int, but it can fill a captured array.
	var plateaus: Array[int] = []
	_sweep(
		func(layout: LocationLayout, label: String) -> void:
			for area: LocationLayout.Area in layout.areas:
				if area.kind != LocationLayout.Kind.PLATEAU:
					continue
				plateaus.append(1)
				var mesa := Vector2(area.mesa.x, area.mesa.y)
				assert_lt(mesa.distance_to(area.center) + area.mesa.z, area.radius, label)
				assert_lt(area.ramp_start.distance_to(area.center), area.radius, label)
	)
	assert_gt(plateaus.size(), 0)


## The areas every way out goes through are known (nests avoid them).
func test_cut_areas() -> void:
	var layout: LocationLayout = _layout(2, 11)
	var cut: PackedInt32Array = layout.cut_areas()
	for i: int in range(1, layout.areas.size()):
		var area: LocationLayout.Area = layout.areas[i]
		if area.passes.size() == 1:
			assert_does_not_have(cut, i, "a dead end cuts nothing off")


func _cross(first: PackedVector2Array, second: PackedVector2Array) -> bool:
	for i: int in range(1, first.size()):
		for j: int in range(1, second.size()):
			if (
				Geometry2D.segment_intersects_segment(
					first[i - 1], first[i], second[j - 1], second[j]
				)
				!= null
			):
				return true
	return false


func _median_distance(layout: LocationLayout) -> float:
	var distances: Array[float] = []
	for area: LocationLayout.Area in layout.areas:
		distances.append(area.distance)
	distances.sort()
	return distances[floori(distances.size() / 2.0)]
