class_name LocationFeatures
extends RefCounted
## The ground of a generated location's special areas (see `LocationLayout.Kind`): nest hollows
## sink, craters are bowls with a rim, plateaus have a mesa with a ramp up its side, ice shelves
## and brine flats are flat, frozen lakes lie a bit lower than their shore, a dry wash's bed winds
## along it below its banks, terrace stairs climb over two slabs by ramps. An ice shelf's cracks
## and a sinkhole field's pits are closed ground, so they become gaps, a butte field's buttes
## rise as rock; a lava island has lava all around. Plain data, planned with the location. All
## values greybox, TBD (playtest).

## A nest hollow's depth and a crater's (its rim rises around it), in m.
const HOLLOW_DEPTH: float = 2.5
const CRATER_DEPTH: float = 3.0
const CRATER_RIM: float = 2.0
## A frozen lake: how far its ice lies below the shore, over how many m the shore rises, and its
## smallest radius (an area without room for it stays a basin), in m.
const LAKE_DEPTH: float = 0.5
const LAKE_SHORE: float = 3.0
const MIN_LAKE_RADIUS: float = 7.0
## Half the width of an ice shelf's crack where it comes in and at its inner end, in m.
const CRACK_WIDTH: Vector2 = Vector2(2.8, 1.6)
## Room between a crack's edge and a lane, in m: a crack ends before it comes closer.
const CRACK_CLEARANCE: float = 4.0
## Room between a pit's edge and a lane, in m: closer pits are left out; a sinkhole field left with
## fewer than `MIN_PITS` is a basin.
const PIT_CLEARANCE: float = 3.0
const MIN_PITS: int = 3
## How far the lava around a lava island reaches beyond its edge, in m.
const ISLAND_MOAT: float = 16.0
## How high a butte rises above the open ground, in m (a flat top), and the room between its edge
## and a lane (closer buttes are left out; a butte field left with fewer than
## `LocationLayout.BUTTES.x` is a basin).
const BUTTE_HEIGHT: float = 5.0
const BUTTE_CLEARANCE: float = 3.0
## A dry wash's bed: half its width, how deep it lies below its banks and over how many m they
## slope, in m, and its tint (lighter sand).
const BED_HALF_WIDTH: float = 4.0
const BED_DEPTH: float = 1.5
const BED_BANK: float = 3.0
const BED_TINT := Color(1.0, 0.96, 0.88)
## Kinds of areas whose open ground has its own shape.
const SHAPED_KINDS: Array[LocationLayout.Kind] = [
	LocationLayout.Kind.NEST_HOLLOW,
	LocationLayout.Kind.CRATER,
	LocationLayout.Kind.PLATEAU,
	LocationLayout.Kind.ICE_SHELF,
	LocationLayout.Kind.FROZEN_LAKE,
	LocationLayout.Kind.BRINE_FLAT,
	LocationLayout.Kind.DRY_WASH,
	LocationLayout.Kind.TERRACE_STAIRS,
]

var _location: GeneratedLocation
## Areas whose open ground has its own shape.
var _shaped: Array[LocationLayout.Area] = []


func _init(location: GeneratedLocation) -> void:
	_location = location


## Closes the ice shelves' cracks, the sinkhole fields' pits and the butte fields' buttes in
## `openness` (see `GeneratedLocation._carve`), off the `lanes`.
func carve(openness: PackedFloat32Array, lanes: PackedByteArray) -> void:
	for area: LocationLayout.Area in _location.layout.areas:
		match area.kind:
			LocationLayout.Kind.ICE_SHELF:
				_carve_cracks(openness, lanes, area)
			LocationLayout.Kind.SINKHOLE_FIELD:
				area.pits = _carve_circles(
					openness, lanes, area, area.pits, PIT_CLEARANCE, MIN_PITS
				)
			LocationLayout.Kind.BUTTE_FIELD:
				area.buttes = _carve_circles(
					openness, lanes, area, area.buttes, BUTTE_CLEARANCE, LocationLayout.BUTTES.x
				)


## Shrinks each frozen lake until it keeps off the `lanes` and inside its area, with its shore; one
## too small for that stays a basin. Returns the lakes (x, z, radius).
func fit_lakes(lanes: PackedByteArray) -> Array[Vector3]:
	var lakes: Array[Vector3] = []
	var cell: float = _location.cell
	for area: LocationLayout.Area in _location.layout.areas:
		if area.kind != LocationLayout.Kind.FROZEN_LAKE:
			continue
		var center := Vector2(area.lake.x, area.lake.y)
		var inside: float = (
			area.radius * (1.0 - GeneratedLocation.AREA_WOBBLE) - center.distance_to(area.center)
		)
		var radius: float = minf(area.lake.z, inside - LAKE_SHORE)
		while radius >= MIN_LAKE_RADIUS and _near_lane(lanes, center, radius + LAKE_SHORE + cell):
			radius -= 1.0
		if radius < MIN_LAKE_RADIUS:
			area.kind = LocationLayout.Kind.BASIN
			area.lake = Vector3.ZERO
			continue
		area.lake.z = radius
		lakes.append(area.lake)
	return lakes


## Makes the gaps reach where these areas want them: all of a sinkhole field's pits, the lava all
## around a lava island.
func widen_gaps(gaps: LocationGaps) -> void:
	var cell: float = _location.cell
	for area: LocationLayout.Area in _location.layout.areas:
		for pit: Vector3 in area.pits:
			# Wide enough that the gap's far side (where the ground comes back up) lies beyond it.
			gaps.widen(Vector2(pit.x, pit.y), pit.z + cell, pit.z * 3.0)
		if area.kind == LocationLayout.Kind.LAVA_ISLAND:
			var reach: float = area.radius * (1.0 + GeneratedLocation.AREA_WOBBLE) + ISLAND_MOAT
			gaps.widen(area.center, reach, ISLAND_MOAT)


## Places scatter keeps away from (x, z, radius): the brine flats and the dry washes' beds stay
## empty.
func clearings() -> Array[Vector3]:
	var found: Array[Vector3] = []
	for area: LocationLayout.Area in _location.layout.areas:
		if area.kind == LocationLayout.Kind.BRINE_FLAT:
			var radius: float = area.radius * (1.0 + GeneratedLocation.AREA_WOBBLE)
			found.append(Vector3(area.center.x, area.center.y, radius))
		for i: int in range(0, area.bed.size(), 2):
			found.append(Vector3(area.bed[i].x, area.bed[i].y, BED_HALF_WIDTH + 1.0))
	return found


## How high the rock at location-local `at` rises at most above the open ground, in m: a butte's
## flat top; INF elsewhere (the biome's rock).
func rock_top(at: Vector2) -> float:
	for area: LocationLayout.Area in _location.layout.areas:
		for butte: Vector3 in area.buttes:
			if at.distance_to(Vector2(butte.x, butte.y)) < butte.z + _location.cell:
				return BUTTE_HEIGHT
	return INF


## How much location-local `at` lies on a dry wash's bed: 1 on it, fading out over its banks.
func bed(at: Vector2) -> float:
	var share: float = 0.0
	for area: LocationLayout.Area in _shaped:
		if area.kind == LocationLayout.Kind.DRY_WASH:
			share = maxf(share, _bed(area, at))
	return share


## Notes the areas whose ground has its own shape, once their kinds are final.
func collect() -> void:
	_shaped.clear()
	for area: LocationLayout.Area in _location.layout.areas:
		if area.kind in SHAPED_KINDS:
			_shaped.append(area)


## The open ground's height at location-local `at`, in m: gentle swells (`swells`), and their own
## shape in special areas.
func height(at: Vector2, swells: FastNoiseLite) -> float:
	var biome: LocationBiome = _location.biome
	var ground: float = swells.get_noise_2dv(at) * biome.floor_relief
	var offset: float = 0.0
	for area: LocationLayout.Area in _shaped:
		var distance: float = at.distance_to(area.center)
		if distance > area.radius * (1.0 + GeneratedLocation.AREA_WOBBLE):
			continue
		match area.kind:
			LocationLayout.Kind.NEST_HOLLOW:
				offset -= (
					HOLLOW_DEPTH
					* (1.0 - smoothstep(area.radius * 0.3, area.radius * 0.9, distance))
				)
			LocationLayout.Kind.CRATER:
				var bowl: float = 1.0 - smoothstep(0.0, area.radius * 0.5, distance)
				var rim: float = exp(-pow(distance - area.radius * 0.55, 2.0) / 18.0)
				offset += rim * CRATER_RIM - bowl * CRATER_DEPTH
			LocationLayout.Kind.PLATEAU:
				# A level top, `MESA_HEIGHT` above the open ground at the mesa's center.
				var mesa_center := Vector2(area.mesa.x, area.mesa.y)
				var top: float = (
					swells.get_noise_2dv(mesa_center) * biome.floor_relief
					+ LocationLayout.MESA_HEIGHT
				)
				ground = lerpf(ground, top, _mesa(area, at))
			LocationLayout.Kind.DRY_WASH:
				offset -= BED_DEPTH * _bed(area, at)
			LocationLayout.Kind.TERRACE_STAIRS:
				# Level slabs, a step apart, above the swells at the area's center.
				var level: float = swells.get_noise_2dv(area.center) * biome.floor_relief
				var tiers: float = _stairs(area, at)
				if tiers > 0.0:
					ground = lerpf(ground, level, minf(tiers, 1.0))
				offset += tiers * biome.terrace_step
			_:
				# Ice shelves, frozen lakes and brine flats: the swells pulled to their height at
				# the center.
				var level: float = swells.get_noise_2dv(area.center) * biome.floor_relief
				var flat: float = 1.0 - smoothstep(area.radius * 0.8, area.radius, distance)
				ground = lerpf(ground, level, flat)
				if area.kind == LocationLayout.Kind.FROZEN_LAKE:
					var shore: float = at.distance_to(Vector2(area.lake.x, area.lake.y))
					offset -= (
						LAKE_DEPTH
						* (1.0 - smoothstep(area.lake.z, area.lake.z + LAKE_SHORE, shore))
					)
	return ground + offset


## How smooth the ground at location-local `at` stays (no bumps): 1 on a frozen lake's ice (fading
## out over its shore), on a brine flat and on a dry wash's bed.
func smoothness(at: Vector2) -> float:
	var share: float = 0.0
	for area: LocationLayout.Area in _shaped:
		match area.kind:
			LocationLayout.Kind.FROZEN_LAKE:
				var distance: float = at.distance_to(Vector2(area.lake.x, area.lake.y))
				var lake: float = 1.0 - smoothstep(area.lake.z, area.lake.z + LAKE_SHORE, distance)
				share = maxf(share, lake)
			LocationLayout.Kind.BRINE_FLAT:
				var distance: float = at.distance_to(area.center)
				var flat: float = 1.0 - smoothstep(area.radius * 0.8, area.radius, distance)
				share = maxf(share, flat)
			LocationLayout.Kind.DRY_WASH:
				share = maxf(share, _bed(area, at))
	return share


## How far up a plateau's mesa location-local `at` is: 1 on its top, 0 off it, rising along the
## ramp.
func _mesa(area: LocationLayout.Area, at: Vector2) -> float:
	var cell: float = _location.cell
	var mesa_center := Vector2(area.mesa.x, area.mesa.y)
	var up: float = 1.0 - smoothstep(area.mesa.z - cell, area.mesa.z, at.distance_to(mesa_center))
	var along: float = (at - area.ramp_start).dot(area.ramp_direction)
	var across: float = absf((at - area.ramp_start).cross(area.ramp_direction))
	if (
		along >= 0.0
		and along <= area.ramp_length + cell
		and across <= LocationLayout.RAMP_WIDTH * 0.5
	):
		up = maxf(up, minf(along / area.ramp_length, 1.0))
	return up


## How much location-local `at` lies on `area`'s bed (a dry wash): 1 on it, fading out over its
## banks.
func _bed(area: LocationLayout.Area, at: Vector2) -> float:
	var reach: float = BED_HALF_WIDTH + BED_BANK
	if at.distance_to(area.center) > area.radius + reach:
		return 0.0
	var nearest: float = INF
	for i: int in range(1, area.bed.size()):
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(
			at, area.bed[i - 1], area.bed[i]
		)
		nearest = minf(nearest, at.distance_to(closest))
	return 1.0 - smoothstep(BED_HALF_WIDTH, reach, nearest)


## How many steps up terrace stairs location-local `at` is: 1 on the lower slab, 2 on the upper
## one, rising along their ramps, 0 off them.
func _stairs(area: LocationLayout.Area, at: Vector2) -> float:
	var cell: float = _location.cell
	var side: Vector2 = area.facing.orthogonal()
	var tiers: float = 0.0
	for slab: LocationLayout.Slab in area.slabs:
		var offset: Vector2 = at - slab.center
		var out: float = maxf(absf(offset.dot(area.facing)), absf(offset.dot(side)))
		tiers = maxf(tiers, (1.0 - smoothstep(slab.half - cell, slab.half, out)) * slab.steps)
		var along: float = (at - slab.ramp_start).dot(slab.ramp_direction)
		var across: float = absf((at - slab.ramp_start).cross(slab.ramp_direction))
		if (
			along >= 0.0
			and along <= slab.ramp_length + cell
			and across <= LocationLayout.RAMP_WIDTH * 0.5
		):
			tiers = maxf(tiers, slab.steps - 1 + minf(along / slab.ramp_length, 1.0))
	return tiers


## Closes the ice shelf's cracks in `openness`, each up to where it would come close to a lane
## (dropping the ones that wouldn't reach into the shelf), narrowing towards their inner ends.
func _carve_cracks(
	openness: PackedFloat32Array, lanes: PackedByteArray, area: LocationLayout.Area
) -> void:
	var cell: float = _location.cell
	var kept: Array[PackedVector2Array] = []
	for crack: PackedVector2Array in area.cracks:
		var points := PackedVector2Array()
		for i: int in crack.size():
			var half: float = lerpf(CRACK_WIDTH.x, CRACK_WIDTH.y, float(i) / (crack.size() - 1))
			if _near_lane(lanes, crack[i], half + CRACK_CLEARANCE + cell):
				break
			points.append(crack[i])
		var inner: Vector2 = points[points.size() - 1] if points.size() > 1 else area.center
		if points.size() < 2 or inner.distance_to(area.center) > area.radius * 0.8:
			continue
		kept.append(points)
		for i: int in points.size():
			var half: float = lerpf(CRACK_WIDTH.x, CRACK_WIDTH.y, float(i) / (crack.size() - 1))
			_close(openness, points[i], half)
	area.cracks = kept


## Closes `area`'s `circles` (pits, buttes) in `openness`, leaving out the ones within `clearance`
## of a lane; with fewer than `fewest` left, the area is a basin. Returns the ones kept.
func _carve_circles(
	openness: PackedFloat32Array,
	lanes: PackedByteArray,
	area: LocationLayout.Area,
	circles: Array[Vector3],
	clearance: float,
	fewest: int
) -> Array[Vector3]:
	var kept: Array[Vector3] = []
	for circle: Vector3 in circles:
		var center := Vector2(circle.x, circle.y)
		if not _near_lane(lanes, center, circle.z + clearance + _location.cell):
			kept.append(circle)
	if kept.size() < fewest:
		area.kind = LocationLayout.Kind.BASIN
		kept.clear()
	for circle: Vector3 in kept:
		_close(openness, Vector2(circle.x, circle.y), circle.z)
	return kept


## Lowers `openness` within `radius` of `center` below 0 (closed ground).
func _close(openness: PackedFloat32Array, center: Vector2, radius: float) -> void:
	var terrain: LocationTerrain = _location.terrain
	var low: Vector2i = Vector2i(terrain.to_grid(center - Vector2.ONE * radius).floor()).maxi(0)
	var high: Vector2i = Vector2i(terrain.to_grid(center + Vector2.ONE * radius).ceil()).mini(
		terrain.cells
	)
	for z: int in range(low.y, high.y + 1):
		for x: int in range(low.x, high.x + 1):
			var index: int = terrain.index(x, z)
			var point: Vector3 = terrain.point(x, z)
			var distance: float = Vector2(point.x, point.z).distance_to(center)
			openness[index] = minf(openness[index], distance - radius)


## Whether a grid point on one of the `lanes` lies within `reach` of `at`.
func _near_lane(lanes: PackedByteArray, at: Vector2, reach: float) -> bool:
	var terrain: LocationTerrain = _location.terrain
	var low: Vector2i = Vector2i(terrain.to_grid(at - Vector2.ONE * reach).floor()).maxi(0)
	var high: Vector2i = Vector2i(terrain.to_grid(at + Vector2.ONE * reach).ceil()).mini(
		terrain.cells
	)
	for z: int in range(low.y, high.y + 1):
		for x: int in range(low.x, high.x + 1):
			var point: Vector3 = terrain.point(x, z)
			if lanes[terrain.index(x, z)] and at.distance_to(Vector2(point.x, point.z)) <= reach:
				return true
	return false
