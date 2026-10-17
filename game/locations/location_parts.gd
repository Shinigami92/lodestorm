class_name LocationParts
extends RefCounted
## The points of interest and set pieces of a generated location (`MapPart`s, one per area): which
## areas they go into (`choose`, on the layout before the ground is shaped, so a set piece can turn
## a basin into a crater) and where exactly they stand (`settle`, on the carved ground: on gentle
## open ground, as far off the lanes as they can). The walkable ring around a part's props keeps
## every pass through its area open. A region's set pieces are always placed, in the
## biggest area that fits; about one point of interest per four areas comes from the biome's pool,
## never in the landing yard or an ore pocket. Plain data, planned on the worker thread with the
## location. All values greybox, TBD (playtest).

## How far from an area's center a part may move to find room, relative to the area's radius.
const SHIFT: float = 0.35
## How often one point of interest appears in a location at most.
const MAX_REPEATS: int = 2
## How often settling a part looks for room in an area.
const SHIFT_TRIES: int = 24
## Room beyond a part's footprint that plants and rocks keep free, in m.
const ROOM: float = 1.0
## Distances over which the ground flattened under a part may blend back, in m: the shortest that
## keeps every step as it was (a wide one fits into a crater's bowl, a short one beside a cliff).
const FALLOFFS: Array[float] = [3.0, 5.0, 8.0]
## `_lanes_under` where a part doesn't fit.
const NO_ROOM: int = 1 << 30
const CRATE: PackedScene = preload("res://game/locations/parts/crate.tscn")


## A part placed in the location.
class Placed:
	var placement: PartPlacement
	var info: MapPart.Info
	var set_piece: bool = false
	## The area it stands in (or, until it's settled, the ones it may go into, best first).
	var area: LocationLayout.Area
	var candidates: Array[LocationLayout.Area] = []
	## Where it stands, location-local, on the flattened ground; its turn around the vertical axis.
	var origin: Vector3 = Vector3.INF
	var turn: float = 0.0

	func transform() -> Transform3D:
		return Transform3D(Basis(Vector3.UP, turn), origin)

	## Location-local position of its `index`th marker.
	func marker_position(index: int) -> Vector3:
		return transform() * info.marker_spots[index].origin

	## Location-local positions of its markers of `kind`.
	func markers(kind: PartMarker.Kind) -> Array[Vector3]:
		var found: Array[Vector3] = []
		for i: int in info.marker_kinds.size():
			if info.marker_kinds[i] == kind:
				found.append(marker_position(i))
		return found


## The parts, once settled: only the ones that found room.
var placed: Array[Placed] = []


## Picks the parts and their areas: every one of `set_pieces`, then about `per_area` of the
## layout's areas from `pool`.
func choose(
	rng: RandomNumberGenerator,
	layout: LocationLayout,
	set_pieces: Array[PartPlacement],
	pool: Array[PartPlacement],
	per_area: float
) -> void:
	var free: Array[LocationLayout.Area] = layout.areas.slice(1)
	for placement: PartPlacement in set_pieces:
		var info: MapPart.Info = MapPart.describe(placement.scene)
		var areas: Array[LocationLayout.Area] = _set_piece_areas(info, placement.rule, layout, free)
		if areas.is_empty():
			push_warning("No area fits the set piece %s" % placement.scene.resource_path)
			continue
		var kind: LocationLayout.Kind = areas[0].kind
		if kind not in info.area_kinds and info.shapes_basin:
			areas[0].kind = info.area_kinds[0]
		_add(placement, info, areas, true, free)
	# Each part as often as the others: the ones used least that still fit somewhere first, each at
	# most `MAX_REPEATS` times; never one of the set pieces again.
	var uses: Dictionary[PackedScene, int] = {}
	var taken: Array[PackedScene] = []
	for part: Placed in placed:
		taken.append(part.placement.scene)
	for count: int in roundi(layout.areas.size() * per_area):
		var fitting: Dictionary[PartPlacement, Array] = {}
		var least: int = 1 << 30
		for placement: PartPlacement in pool:
			var used: int = uses.get(placement.scene, 0)
			if placement.scene in taken or used >= MAX_REPEATS:
				continue
			var areas: Array[LocationLayout.Area] = _pool_areas(placement, layout, free)
			if not areas.is_empty():
				fitting[placement] = areas
				least = mini(least, used)
		var choices: Array[PartPlacement] = []
		for placement: PartPlacement in fitting:
			var used: int = uses.get(placement.scene, 0)
			if used == least:
				choices.append(placement)
		if choices.is_empty():
			break
		var picked: PartPlacement = _weighted(rng, choices)
		var info: MapPart.Info = MapPart.describe(picked.scene)
		var options: Array = fitting[picked]
		var area: LocationLayout.Area = options[rng.randi() % options.size()]
		_add(picked, info, [area], false, free)
		uses[picked.scene] = least + 1


## Puts the chosen parts on the ground of `location` (carved, not flattened yet): in their area (a
## set piece in the next one if there's no room), on gentle open ground with their props as far off
## the lanes as they can, turned towards the way in. Flattens the ground under them; drops parts
## without room.
func settle(rng: RandomNumberGenerator, location: GeneratedLocation) -> void:
	var chosen: Array[Placed] = placed
	placed = []
	var used: Array[LocationLayout.Area] = []
	for part: Placed in chosen:
		for area: LocationLayout.Area in part.candidates:
			if area in used:
				continue
			var room: Vector3 = _room_in(rng, location, part.info, area)
			if room == Vector3.INF:
				continue
			var at := Vector2(room.x, room.y)
			location.add_site(Vector3(at.x, 0.0, at.y), part.info.footprint, ROOM, room.z)
			part.area = area
			part.origin = Vector3(at.x, location.terrain.height_at(at.x, at.y), at.y)
			var inward: Vector2 = _way_in(location.layout, area) - at
			# Its front (-z) faces the way in.
			part.turn = atan2(-inward.x, -inward.y)
			used.append(area)
			placed.append(part)
			break
		if not part.area and part.set_piece:
			push_warning("No room for the set piece %s" % part.placement.scene.resource_path)


## Adds the ore sites of the parts' ore markers to `sites` (location-local, at height 0) and their
## ores to `types`, of the band each asks for (`found`: the ores, commonest first). Returns how many
## ore fields they count as (one per part).
func ore_sites(found: Array[OreType], sites: Array[Vector3], types: Array[OreType]) -> int:
	var fields: int = 0
	for part: Placed in placed:
		for i: int in part.info.marker_kinds.size():
			if part.info.marker_kinds[i] != PartMarker.Kind.ORE:
				continue
			var site: Vector3 = part.marker_position(i)
			sites.append(Vector3(site.x, 0.0, site.z))
			match part.info.marker_bands[i]:
				PartMarker.Band.COMMON:
					types.append(found[0])
				PartMarker.Band.MID:
					types.append(found[floori(found.size() / 2.0)])
				_:
					types.append(found[found.size() - 1])
		if part.info.count(PartMarker.Kind.ORE) > 0:
			fields += 1
	return fields


## Adds the parts' scenes to `location` (under `Parts`), with a crate on every crate marker: they
## hold `contents` in turn, then supply caches.
func build(location: Node3D, contents: Array[CrateContent]) -> void:
	var holder := Node3D.new()
	holder.name = "Parts"
	location.add_child(holder)
	var left: Array[CrateContent] = contents.duplicate()
	for part: Placed in placed:
		var scene := part.placement.scene.instantiate() as Node3D
		scene.transform = part.transform()
		holder.add_child(scene)
		for marker: PartMarker in scene.find_children("*", "PartMarker", true, false):
			if marker.kind != PartMarker.Kind.CRATE:
				continue
			var crate := CRATE.instantiate() as Crate
			crate.name = "Crate"
			if not left.is_empty():
				crate.content = left.pop_front()
			marker.add_child(crate)


## The part in `area`, or null.
func part_in(area: LocationLayout.Area) -> Placed:
	for part: Placed in placed:
		if part.area == area:
			return part
	return null


## Whether something of `radius` at location-local `at` would reach into a part's footprint.
func covers(at: Vector2, radius: float) -> bool:
	for part: Placed in placed:
		if at.distance_to(Vector2(part.origin.x, part.origin.z)) < part.info.footprint + radius:
			return true
	return false


func _add(
	placement: PartPlacement,
	info: MapPart.Info,
	areas: Array[LocationLayout.Area],
	set_piece: bool,
	free: Array[LocationLayout.Area]
) -> void:
	var part := Placed.new()
	part.placement = placement
	part.info = info
	part.set_piece = set_piece
	part.candidates = areas
	free.erase(areas[0])
	placed.append(part)


## The free areas a point of interest from the pool may go into: of its kinds, where its rule
## wants it, never an ore pocket.
func _pool_areas(
	placement: PartPlacement, layout: LocationLayout, free: Array[LocationLayout.Area]
) -> Array[LocationLayout.Area]:
	var info: MapPart.Info = MapPart.describe(placement.scene)
	var areas: Array[LocationLayout.Area] = []
	for area: LocationLayout.Area in free:
		if (
			area.kind != LocationLayout.Kind.ORE_POCKET
			and area.kind in info.area_kinds
			and info.fits(area.kind, area.radius, GeneratedLocation.AREA_WOBBLE)
			and _follows(placement.rule, area, layout)
		):
			areas.append(area)
	return areas


## The areas a set piece may go into, best first: the ones that follow its rule, of its kinds
## (then basins it may shape), the biggest first.
func _set_piece_areas(
	info: MapPart.Info,
	rule: PartPlacement.Rule,
	layout: LocationLayout,
	free: Array[LocationLayout.Area]
) -> Array[LocationLayout.Area]:
	var ranked: Array[LocationLayout.Area] = []
	var scores: Dictionary[LocationLayout.Area, float] = {}
	# Smaller areas than it asks for only when none is big enough.
	var sized: bool = false
	for area: LocationLayout.Area in free:
		if info.fits(area.kind, area.radius, GeneratedLocation.AREA_WOBBLE):
			sized = true
	for area: LocationLayout.Area in free:
		if not info.fits(area.kind, area.radius, GeneratedLocation.AREA_WOBBLE, sized):
			continue
		var score: float = area.radius
		if area.kind in info.area_kinds:
			score += 1000.0
		if _follows(rule, area, layout):
			score += 2000.0
		scores[area] = score
		ranked.append(area)
	ranked.sort_custom(
		func(a: LocationLayout.Area, b: LocationLayout.Area) -> bool: return scores[a] > scores[b]
	)
	# Only the first may be shaped; the others are only there in case it has no room after all
	# (as a last resort also the ones that aren't of its kinds).
	var areas: Array[LocationLayout.Area] = ranked.slice(0, 1)
	for area: LocationLayout.Area in ranked.slice(1):
		if area.kind in info.area_kinds:
			areas.append(area)
	for area: LocationLayout.Area in ranked.slice(1):
		if area not in areas:
			areas.append(area)
	return areas


## Whether `area` lies where `rule` wants it (a dead end: in the far half, so a rich vein doesn't
## lie next to the ship).
static func _follows(
	rule: PartPlacement.Rule, area: LocationLayout.Area, layout: LocationLayout
) -> bool:
	var share: float = area.distance / maxf(layout.farthest(), 1.0)
	match rule:
		PartPlacement.Rule.NEAR:
			return share <= 1.0 / 3.0
		PartPlacement.Rule.MID:
			return share > 1.0 / 3.0 and share <= 2.0 / 3.0
		PartPlacement.Rule.FAR:
			return share > 2.0 / 3.0
		PartPlacement.Rule.DEAD_END:
			return area.passes.size() == 1 and share > 0.5
	return true


static func _weighted(rng: RandomNumberGenerator, choices: Array[PartPlacement]) -> PartPlacement:
	var total: float = 0.0
	for choice: PartPlacement in choices:
		total += maxf(choice.weight, 0.0)
	var pick: float = rng.randf() * total
	for choice: PartPlacement in choices:
		pick -= maxf(choice.weight, 0.0)
		if pick <= 0.0:
			return choice
	return choices[choices.size() - 1]


## A spot in `area` where the part has room: location-local x, z and the falloff to flatten it
## with (see `FALLOFFS`). The one with the fewest lane points under its props, the area's center
## if that's free of them; `Vector3.INF` when there's none.
func _room_in(
	rng: RandomNumberGenerator,
	location: GeneratedLocation,
	info: MapPart.Info,
	area: LocationLayout.Area
) -> Vector3:
	var best: Vector3 = Vector3.INF
	var fewest: int = NO_ROOM
	for attempt: int in SHIFT_TRIES:
		var at: Vector2 = area.center
		if attempt > 0:
			at += Vector2.from_angle(rng.randf() * TAU) * rng.randf() * area.radius * SHIFT
		var lanes: int = _lanes_under(location, info, at)
		if lanes >= fewest:
			continue
		for falloff: float in FALLOFFS:
			if location.flattening_keeps_steps(at, info.footprint, falloff):
				best = Vector3(at.x, at.y, falloff)
				fewest = lanes
				break
		if fewest == 0:
			break
	return best


## How many lane points lie under the part's props at `at` (location-local), or `NO_ROOM` when it
## doesn't fit there: its footprint must be reachable open ground, out of other parts' footprints.
func _lanes_under(location: GeneratedLocation, info: MapPart.Info, at: Vector2) -> int:
	if covers(at, info.footprint):
		return NO_ROOM
	var lanes: int = 0
	var terrain: LocationTerrain = location.terrain
	var reach: float = info.footprint + terrain.cell
	var low: Vector2i = Vector2i(terrain.to_grid(at - Vector2.ONE * reach).floor())
	var high: Vector2i = Vector2i(terrain.to_grid(at + Vector2.ONE * reach).ceil())
	for z: int in range(low.y, high.y + 1):
		for x: int in range(low.x, high.x + 1):
			var point: Vector3 = terrain.point(x, z)
			var distance: float = Vector2(point.x, point.z).distance_to(at)
			if distance > info.footprint:
				continue
			if not location.is_reachable(point.x, point.z):
				return NO_ROOM
			if distance <= info.prop_radius and location.is_on_lane(point.x, point.z):
				lanes += 1
	return lanes


## Where the way into `area` from the ship comes in: a bit along the pass from the nearer area.
static func _way_in(layout: LocationLayout, area: LocationLayout.Area) -> Vector2:
	var index: int = layout.areas.find(area)
	var best: Vector2 = area.center + Vector2.RIGHT
	var nearest: float = INF
	for pass_index: int in area.passes:
		var way: LocationLayout.Pass = layout.passes[pass_index]
		var other: int = way.from if way.to == index else way.to
		if layout.areas[other].distance < nearest:
			nearest = layout.areas[other].distance
			var step: int = mini(way.points.size() - 1, maxi(1, ceili(area.radius * 0.5 / 2.0)))
			best = (
				way.points[step] if way.from == index else way.points[way.points.size() - 1 - step]
			)
	return best
