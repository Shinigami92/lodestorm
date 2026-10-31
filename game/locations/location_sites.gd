class_name LocationSites
extends RefCounted
## Where a generated location's ore nodes and alien nests go (see `GeneratedLocation`): the map
## parts' markers first, then ore fields (two close to the ramp with the commonest ore, the rarest
## in every ore pocket, a rich field in the middle of every nest hollow, the rest spread over the
## other areas, rarer the farther they lie along the passes; the late deposit's on its part's
## markers, see `deposit_ore`), then nests (two in every nest hollow, one on each side of its rich
## field, then spread over the areas far enough from the ship), then the quest nests of the
## location's `quest_visit` (see `QuestVisit`). Each pass draws from a random stream of its own
## (`GeneratedLocation.random_stream`), so a pass added later doesn't change what the others pick.
## Plain data, planned with the location (safe on a worker thread). All values greybox, TBD
## (playtest).

const ORE_RADIUS: float = 3.0
const NEST_RADIUS: float = 6.0
## Ground kept free of scatter beyond an ore node's and a nest's radius, in m.
const ORE_ROOM: float = 1.5
const NEST_ROOM: float = 3.5
## Closest the nodes of one field are to each other, and how far from its center they spread, in m.
const NODE_SPACING: float = 7.0
const FIELD_SPREAD: float = 12.0
## A rich field: how far from its nest hollow's middle it lies (relative to the hollow's radius)
## and how far its nodes spread from its center, in m (close together, so the nests fit around it).
const RICH_CENTER: float = 0.3
const RICH_SPREAD: float = 8.0
## Closest an ore field or a nest is to the landing site, in m.
const LANDING_GAP: float = 10.0
## How close a nest may be to the landing site in a straight line, relative to
## `LocationBiome.nest_min_distance` (which counts along the passes).
const NEST_STRAIGHT_SHARE: float = 0.6
## How close a nest may be to a part where someone waits (a `PartMarker.Kind.PERSON`, e.g. Hollis'
## camp), in m: nobody lives next to a nest. TBD (playtest).
const PERSON_NEST_DISTANCE: float = 30.0


## An ore node's place.
class OreSite:
	## Location-local, on the ground.
	var position: Vector3
	var ore: OreType
	## The area it lies in.
	var area: LocationLayout.Area
	## Part of a nest hollow's rich field or the late deposit: holds more (`OreNode.rich`).
	var rich: bool
	## The late deposit's: appears with the impact (`LateDeposit`).
	var late: bool

	func _init(
		at: Vector3,
		ore_type: OreType,
		in_area: LocationLayout.Area,
		is_rich: bool = false,
		is_late: bool = false
	) -> void:
		position = at
		ore = ore_type
		area = in_area
		rich = is_rich
		late = is_late


## A nest's place.
class NestSite:
	## Location-local, on the ground.
	var position: Vector3
	## The area it lies in (a nest hollow holds two).
	var area: LocationLayout.Area
	## A quest nest's: the goal it counts for; null for an ordinary nest.
	var quest: QuestVisit.Entry

	func _init(
		at: Vector3, in_area: LocationLayout.Area, for_quest: QuestVisit.Entry = null
	) -> void:
		position = at
		area = in_area
		quest = for_quest


var ores: Array[OreSite] = []
var nests: Array[NestSite] = []

var _location: GeneratedLocation


func _init(location: GeneratedLocation) -> void:
	_location = location


## Picks the sites with the location's ores, commonest first (none: no ore fields), and flattens
## the ground under them.
func pick(found: Array[OreType]) -> void:
	if not found.is_empty():
		_pick_ores(found)
	_pick_nests()
	_pick_quest_nests()
	# Flattening the sites changed the ground a little, also under sites placed before.
	var terrain: LocationTerrain = _location.terrain
	for site: OreSite in ores:
		site.position.y = terrain.height_at(site.position.x, site.position.z)
	for site: NestSite in nests:
		site.position.y = terrain.height_at(site.position.x, site.position.z)


## Where the ore nodes go, location-local.
func ore_positions() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for site: OreSite in ores:
		positions.append(site.position)
	return positions


## Where the nests go, location-local.
func nest_positions() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for site: NestSite in nests:
		positions.append(site.position)
	return positions


func _pick_ores(found: Array[OreType]) -> void:
	var rng: RandomNumberGenerator = _stream("ores")
	var fields: int = _ore_markers(found)
	var layout: LocationLayout = _location.layout
	var landing: LocationLayout.Area = layout.areas[0]
	_add_ore_field(rng, found[0], landing, true)
	_add_ore_field(rng, found[0], landing, true)
	var others: Array[LocationLayout.Area] = []
	for area: LocationLayout.Area in layout.areas:
		var part: LocationParts.Placed = _location.parts.part_in(area)
		if part and part.info.count(PartMarker.Kind.ORE) > 0:
			continue
		if area.holds_rarest_ore():
			_add_ore_field(rng, found[found.size() - 1], area, false)
		elif area.kind == LocationLayout.Kind.NEST_HOLLOW:
			# The rarest or the second rarest ore.
			var rarest: int = found.size() - 1
			_add_ore_field(rng, found[maxi(rarest - rng.randi_range(0, 1), 0)], area, false, true)
		elif area.kind != LocationLayout.Kind.LANDING:
			others.append(area)
	var wanted: int = roundi(layout.areas.size() * _location.biome.ore_fields_per_area)
	var farthest: float = maxf(layout.farthest(), 1.0)
	for attempt: int in wanted * 3:
		if others.is_empty() or fields >= wanted:
			break
		var area: LocationLayout.Area = others[rng.randi() % others.size()]
		var rank: float = area.distance / farthest * found.size() + rng.randf_range(-0.6, 0.6)
		var ore_type: OreType = found[clampi(int(rank), 0, found.size() - 1)]
		if _add_ore_field(rng, ore_type, area, false):
			fields += 1


## The map parts' ore markers, each with the ore of its band (the late deposit's all with
## `deposit_ore`, rich); how many parts have some (not counting the late deposit).
func _ore_markers(found: Array[OreType]) -> int:
	var fields: int = 0
	for part: LocationParts.Placed in _location.parts.placed:
		for i: int in part.info.marker_kinds.size():
			if part.info.marker_kinds[i] != PartMarker.Kind.ORE:
				continue
			var ore_type: OreType = found[found.size() - 1]
			match part.info.marker_bands[i]:
				PartMarker.Band.COMMON:
					ore_type = found[0]
				PartMarker.Band.MID:
					ore_type = found[floori(found.size() / 2.0)]
			if part.late:
				ore_type = deposit_ore(found)
			var at: Vector3 = _on_ground(part.marker_position(i))
			ores.append(OreSite.new(at, ore_type, part.area, part.late, part.late))
		if part.info.count(PartMarker.Kind.ORE) > 0 and not part.late:
			fields += 1
	return fields


## The late deposit's ore among `found` (commonest first): the rarest signature ore, else the
## rarest mid ore, else the rarest.
static func deposit_ore(found: Array[OreType]) -> OreType:
	for band: OreType.Band in [OreType.Band.SIGNATURE, OreType.Band.MID]:
		for i: int in range(found.size() - 1, -1, -1):
			if found[i].band == band:
				return found[i]
	return found[found.size() - 1]


## Adds an ore field of `ore_type` in `area` (`near`: close to the ramp; `rich`: a nest hollow's
## rich field, in its middle); false when there's no room.
func _add_ore_field(
	rng: RandomNumberGenerator,
	ore_type: OreType,
	area: LocationLayout.Area,
	near: bool,
	rich: bool = false
) -> bool:
	var fields: Array[Vector3] = ore_positions()
	var ramp_exit: Vector2 = _location.ramp_exit
	var near_distance: Vector2 = _location.near_ore_distance
	var spacing: float = _location.ore_field_spacing
	var center: Vector3 = _location.find_site(
		rng,
		ORE_RADIUS,
		func(at: Vector2) -> bool:
			if near and at.distance_to(ramp_exit) < near_distance.x:
				return false
			return _location.landing_distance(at) >= LANDING_GAP and _far_from(at, fields, spacing),
		ramp_exit if near else area.center,
		near_distance.y if near else area.radius * (RICH_CENTER if rich else 0.8)
	)
	if center == Vector3.INF:
		return false
	var nodes: Vector2i = _location.biome.ore_nodes_per_field
	for node: int in rng.randi_range(nodes.x, nodes.y):
		var site: Vector3 = Vector3(center.x, 0.0, center.z)
		if node > 0:
			var placed: Array[Vector3] = ore_positions()
			site = _location.find_site(
				rng,
				ORE_RADIUS,
				func(at: Vector2) -> bool:
					return (
						_location.landing_distance(at) >= LANDING_GAP
						and _far_from(at, placed, NODE_SPACING)
					),
				Vector2(center.x, center.z),
				RICH_SPREAD if rich else FIELD_SPREAD
			)
		if site == Vector3.INF:
			continue
		_location.add_site(site, ORE_RADIUS, ORE_ROOM)
		ores.append(OreSite.new(_on_ground(site), ore_type, area, rich))
	return true


## Nests in the areas far enough from the ship: the parts' nest markers first, two in every nest
## hollow (the second across its rich field from the first), then spread over the others, the
## areas every way out goes through last (so they rarely block the way back).
func _pick_nests() -> void:
	var rng: RandomNumberGenerator = _stream("nests")
	var biome: LocationBiome = _location.biome
	var layout: LocationLayout = _location.layout
	var wanted: int = roundi(layout.areas.size() * biome.nests_per_area * _location.nest_factor)
	for part: LocationParts.Placed in _location.parts.placed:
		if part.area.distance < biome.nest_min_distance:
			continue
		for site: Vector3 in part.markers(PartMarker.Kind.NEST):
			if nests.size() < wanted:
				nests.append(NestSite.new(_on_ground(site), part.area))
	var cut: PackedInt32Array = layout.cut_areas()
	var first: Array[LocationLayout.Area] = []
	var spread: Array[LocationLayout.Area] = []
	var last: Array[LocationLayout.Area] = []
	for i: int in layout.areas.size():
		var area: LocationLayout.Area = layout.areas[i]
		if area.kind == LocationLayout.Kind.LANDING or area.distance < biome.nest_min_distance:
			continue
		if area.kind == LocationLayout.Kind.NEST_HOLLOW:
			first.append(area)
			first.append(area)
		elif i in cut:
			last.append(area)
		else:
			spread.append(area)
	var order: Array[LocationLayout.Area] = first
	order.append_array(_shuffled(rng, spread))
	order.append_array(_shuffled(rng, last))
	if order.is_empty():
		return
	var ore_sites: Array[Vector3] = ore_positions()
	for attempt: int in maxi(wanted, order.size()) * 3:
		if nests.size() >= wanted:
			break
		var area: LocationLayout.Area = order[attempt % order.size()]
		var site: Vector3 = _nest_spot(rng, area, ore_sites, _field_side(area))
		if site == Vector3.INF:
			continue
		_location.add_site(site, NEST_RADIUS, NEST_ROOM)
		nests.append(NestSite.new(_on_ground(site), area))


## The quest nests (see `QuestVisit.nest_entries`), from a stream of their own so the ordinary
## nests stay where they were: spread over the areas far enough from the ship, one area after
## another, the areas every way out goes through last.
func _pick_quest_nests() -> void:
	var visit: QuestVisit = _location.quest_visit
	if not visit:
		return
	var wanted: Array[QuestVisit.Entry] = visit.nest_entries()
	if wanted.is_empty():
		return
	var rng: RandomNumberGenerator = _stream("quest_nests")
	var layout: LocationLayout = _location.layout
	var cut: PackedInt32Array = layout.cut_areas()
	var spread: Array[LocationLayout.Area] = []
	var last: Array[LocationLayout.Area] = []
	for i: int in layout.areas.size():
		var area: LocationLayout.Area = layout.areas[i]
		if area.kind == LocationLayout.Kind.LANDING:
			continue
		if area.distance < _location.biome.nest_min_distance:
			continue
		(last if i in cut else spread).append(area)
	var order: Array[LocationLayout.Area] = _shuffled(rng, spread)
	order.append_array(_shuffled(rng, last))
	if order.is_empty():
		push_warning("No area for the quest nests")
		return
	var ore_sites: Array[Vector3] = ore_positions()
	var attempt: int = 0
	while not wanted.is_empty() and attempt < wanted.size() * order.size() * 3:
		var area: LocationLayout.Area = order[attempt % order.size()]
		attempt += 1
		var site: Vector3 = _nest_spot(rng, area, ore_sites)
		if site == Vector3.INF:
			continue
		_location.add_site(site, NEST_RADIUS, NEST_ROOM)
		var quest: QuestVisit.Entry = wanted.pop_front()
		nests.append(NestSite.new(_on_ground(site), area, quest))
	if not wanted.is_empty():
		push_warning("No room for %d quest nests" % wanted.size())


## A spot for a nest in `area`, far enough from the landing site, the other nests, `ore_sites` and
## parts where someone waits (on `side` of a rich field if one is given, see `_field_side`);
## `Vector3.INF` without room.
func _nest_spot(
	rng: RandomNumberGenerator,
	area: LocationLayout.Area,
	ore_sites: Array[Vector3],
	side: PackedVector2Array = []
) -> Vector3:
	var placed: Array[Vector3] = nest_positions()
	var closest: float = _location.biome.nest_min_distance * NEST_STRAIGHT_SHARE
	var people: Array[Vector3] = []
	for part: LocationParts.Placed in _location.parts.placed:
		if part.info.count(PartMarker.Kind.PERSON) > 0:
			people.append(part.origin)
	return _location.find_site(
		rng,
		NEST_RADIUS,
		func(at: Vector2) -> bool:
			return (
				_location.landing_distance(at) >= closest
				and _far_from(at, placed, _location.nest_spacing)
				and _far_from(at, ore_sites, _location.nest_ore_spacing)
				and _far_from(at, people, PERSON_NEST_DISTANCE)
				and (side.is_empty() or (at - side[0]).dot(side[1]) > 0.0)
			),
		area.center,
		area.radius * 0.8
	)


## Which side of `area`'s rich field its second nest goes to, so the field lies between the two:
## the field's center and the way from its first nest across it; empty when any spot will do (not
## a nest hollow with a rich field and one nest).
func _field_side(area: LocationLayout.Area) -> PackedVector2Array:
	if area.kind != LocationLayout.Kind.NEST_HOLLOW:
		return []
	var field := Vector2.ZERO
	var nodes: int = 0
	for site: OreSite in ores:
		if site.rich and site.area == area:
			field += Vector2(site.position.x, site.position.z)
			nodes += 1
	var inside: Array[Vector2] = []
	for nest: NestSite in nests:
		if nest.area == area:
			inside.append(Vector2(nest.position.x, nest.position.z))
	if nodes == 0 or inside.size() != 1:
		return []
	field /= nodes
	return [field, field - inside[0]]


func _stream(stage: String) -> RandomNumberGenerator:
	return GeneratedLocation.random_stream(_location.world_seed, stage)


func _on_ground(site: Vector3) -> Vector3:
	return Vector3(site.x, _location.terrain.height_at(site.x, site.z), site.z)


static func _shuffled(
	rng: RandomNumberGenerator, areas: Array[LocationLayout.Area]
) -> Array[LocationLayout.Area]:
	var mixed: Array[LocationLayout.Area] = areas.duplicate()
	for i: int in range(mixed.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: LocationLayout.Area = mixed[i]
		mixed[i] = mixed[j]
		mixed[j] = swap
	return mixed


static func _far_from(at: Vector2, sites: Array[Vector3], distance: float) -> bool:
	for site: Vector3 in sites:
		if at.distance_to(Vector2(site.x, site.z)) < distance:
			return false
	return true
