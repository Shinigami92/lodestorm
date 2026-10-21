class_name OreHold
extends Station
## The hold in the cargo bay (greybox until the cargo bay's art pass): an industrial silo
## per ore of the game (`OreTank`, from `OreCatalog`), in fixed spots ordered by rarity, its window
## glowing with what the hold has. The silos stand in clusters, one per band, each around a pump
## hub with pipes to the silos' tops: the common and mid clusters behind the main lane (from the
## ramp to the lower deck, along the hold's X axis), the commons by the ramp; the signature cluster
## in front of the lane, a bit away from the ramp and the lane (the way from the ramp stays open),
## with smaller and lower silos. A cluster is two rows (the one
## nearer the camera first), the far row shifted half a step sideways (`window_shift`): the
## isometric camera looks along the hold's -Z, and the shift keeps every window in sight. These
## stay clear: the main lane (`LANE_WIDTH`), the way between the clusters (`WALK_WIDTH`), the way
## to the lift (back, by the lower deck's door), the ramp button and the refinery's corner (front,
## by the door).
## Every player has their own hold (`PlayerHold`): the silos show the one of the player using them,
## else the viewer's (the ship's `viewer`, or the first local player). Ores never brought aboard
## show as dark "?" silos.
## A silo is used directly (`interact` next to it): the hold opens as a station with it selected,
## the camera follows the selected silo, and the card shows the ore's name, how much the hold has
## and where it's found. `tab_prev`/`tab_next` step through the silos in reading order (rows from
## the back, each from left to right), the directions to the nearest silo, furnace or ingot rack
## shelf on screen (the cargo bay's `room`).

const CATALOG: OreCatalog = preload("res://game/ores/all_ores.tres")
## Silo size per band: radius, height (m) and the units it shows as full (TBD (playtest)).
const TANKS: Dictionary[OreType.Band, Vector3] = {
	OreType.Band.COMMON: Vector3(1.1, 5.0, 3000.0),
	OreType.Band.MID: Vector3(0.8, 4.0, 1500.0),
	OreType.Band.SIGNATURE: Vector3(0.72, 2.6, 600.0),
}
## Silos per row in a band's cluster.
const ROW_LENGTH: Dictionary[OreType.Band, int] = {
	OreType.Band.COMMON: 2,
	OreType.Band.MID: 2,
	OreType.Band.SIGNATURE: 3,
}
## Gap between neighboring silos of a cluster (room for the hub and its pipes), in m.
const GAP: float = 0.75
## Clear width (m) of the main lane (four players side by side, VR comfort) and of the way between
## clusters.
const LANE_WIDTH: float = 4.0
const WALK_WIDTH: float = 1.4
## How far a cluster's near row keeps from the lane's edge, in m.
const LANE_MARGIN: float = 0.45
const PIPE_RADIUS: float = 0.1
const HUB_RADIUS: float = 0.38

## In the hold's space (its origin on the cargo bay's floor, in the middle of the main lane): the
## right edge (towards the ramp) of the clusters behind the lane (commons first, then each next one
## `WALK_WIDTH` further left) and of the cluster in front of it, and how far that one keeps from
## the lane's edge (more than those behind it: the way from the ramp into the bay stays open).
@export var back_right_edge: float = 7.8
@export var front_right_edge: float = 6.2
@export var front_lane_margin: float = 2.6

## The mission (for where ores are found); found in the scene tree when not set.
var mission: Mission

var _tanks: Dictionary[OreType, OreTank] = {}
## The hold the silos show right now.
var _shown: PlayerHold
var _clusters: Array[Array] = []
## The silos in reading order (for `tab_prev`/`tab_next`).
var _reading: Array[StationPart] = []
var _pipe_material := StandardMaterial3D.new()
var _hub_material := StandardMaterial3D.new()


func _ready() -> void:
	_build_tanks()
	super()


func _process(delta: float) -> void:
	super(delta)
	if not mission:
		mission = get_tree().get_first_node_in_group(Mission.GROUP) as Mission
	var shown: Player = user if user else _viewer()
	show_hold(shown.hold if shown else null)


## Shows `hold` in the silos (null: all empty and unknown), and its changes from then on.
func show_hold(hold: PlayerHold) -> void:
	if hold == _shown:
		return
	if _shown:
		_shown.item_changed.disconnect(_on_item_changed)
	_shown = hold
	if hold:
		hold.item_changed.connect(_on_item_changed)
	for ore_type: OreType in _tanks:
		var amount: float = hold.amount(ore_type) if hold else 0.0
		show_amount(ore_type, amount, hold != null and hold.has_found(ore_type))


## The hold the silos show (null: none yet).
func get_shown_hold() -> PlayerHold:
	return _shown


## Shows `amount` units of `ore_type` in its silo; `found`: it was ever brought aboard.
func show_amount(ore_type: OreType, amount: float, found: bool) -> void:
	var tank: OreTank = _tanks.get(ore_type)
	if tank:
		tank.show_amount(amount, found)
	if user and selected == tank:
		refresh()


## The silo of `ore_type`, or null.
func get_tank(ore_type: OreType) -> OreTank:
	return _tanks.get(ore_type)


## The clusters of silos, one per band (`Array[OreTank]` each, near row first).
func get_clusters() -> Array[Array]:
	return _clusters


## The silos in the order `tab_next` steps through them.
func get_reading_order() -> Array[StationPart]:
	return _reading


## The open regions where `ore_type` is found.
func regions_with(ore_type: OreType) -> Array[Region]:
	var found_in: Array[Region] = []
	var system: StarSystem = mission.settings.system if mission and mission.settings else null
	var ship := get_parent() as Ship
	if system:
		for region: Region in system.open_regions(ship.heat_shield.mk if ship else 1):
			if ore_type in system.ores_of(region):
				found_in.append(region)
	return found_in


## The camera follows the selected silo (the card beside it).
func get_view_center() -> Vector3:
	if not selected:
		return super()
	var camera: Camera3D = get_viewport().get_camera_3d()
	var right: Vector3 = camera.global_basis.x if camera else Vector3.RIGHT
	return selected.global_position + right * selected.card_offset.x * 0.5


## How far a cluster's far row shifts sideways for silos of `radius`: half a step, which is just
## past where the near row's silo would hide the window behind it.
static func window_shift(radius: float) -> float:
	return radius + GAP * 0.5


func _opened() -> void:
	super()
	_enable_uses(false)
	var ship := get_parent() as Ship
	if ship:
		ship.countdown_hidden = true


func _closed() -> void:
	super()
	_enable_uses(true)
	var ship := get_parent() as Ship
	if ship:
		ship.countdown_hidden = false


func _cycle(step_by: int) -> void:
	if _reading.is_empty():
		return
	var index: int = _reading.find(selected)
	select(_reading[posmod(index + step_by, _reading.size())])


func _enable_uses(enabled: bool) -> void:
	for tank: OreTank in _tanks.values():
		tank.use_point.enabled = enabled


## Whose hold the silos show while nobody uses them (see `Ship.get_viewing_player`).
func _viewer() -> Player:
	var ship := get_parent() as Ship
	return ship.get_viewing_player() if ship else Player.first_local(get_tree())


func _on_item_changed(item: ItemType, amount: float) -> void:
	var ore_type := item as OreType
	if ore_type:
		show_amount(ore_type, amount, _shown.has_found(ore_type))


func _on_tank_used(player: Player, tank: OreTank) -> void:
	if user or not can_use(player):
		return
	select(tank)
	open(player)


## A cluster per band: commons and mids behind the lane (from the ramp leftwards), signatures in
## front of it.
func _build_tanks() -> void:
	_pipe_material.albedo_color = Color(0.3, 0.32, 0.35)
	_pipe_material.metallic = 0.3
	_pipe_material.roughness = 0.45
	_hub_material.albedo_color = Color(0.24, 0.25, 0.28)
	_hub_material.metallic = 0.3
	_hub_material.roughness = 0.5
	var back_edge: float = back_right_edge
	for band: OreType.Band in [OreType.Band.COMMON, OreType.Band.MID, OreType.Band.SIGNATURE]:
		var ores: Array[OreType] = []
		for ore_type: OreType in OreCatalog.sorted(CATALOG.ores):
			if ore_type.band == band:
				ores.append(ore_type)
		if ores.is_empty():
			continue
		var side: int = 1 if band == OreType.Band.SIGNATURE else -1
		var right_edge: float = front_right_edge if side > 0 else back_edge
		var cluster: Array[OreTank] = _build_cluster(ores, band, side, right_edge)
		_clusters.append(cluster)
		if side < 0:
			var left: float = INF
			for tank: OreTank in cluster:
				left = minf(left, tank.position.x - tank.radius)
			back_edge = left - WALK_WIDTH
	_reading = _reading_order()


## One band's cluster: rows of `ROW_LENGTH` silos, the near row along the lane's edge, the far row
## behind it shifted half a step towards the ramp, the hub in the middle; its right edge at
## `right_edge`. `side`: -1 behind the lane, 1 in front of it.
func _build_cluster(
	ores: Array[OreType], band: OreType.Band, side: int, right_edge: float
) -> Array[OreTank]:
	var size: Vector3 = TANKS[band]
	var radius: float = size.x
	var spacing: float = radius * 2.0 + GAP
	var per_row: int = ROW_LENGTH[band]
	var rows: int = ceili(float(ores.size()) / per_row)
	var widest: float = (per_row - 1) * spacing + (window_shift(radius) if rows > 1 else 0.0)
	var left: float = right_edge - radius - widest
	var margin: float = front_lane_margin if side > 0 else LANE_MARGIN
	var near_z: float = side * (LANE_WIDTH * 0.5 + margin + radius + 0.14)
	# The row nearer the camera (larger Z) is the near row behind the lane, the far row in front.
	var cluster: Array[OreTank] = []
	for i: int in ores.size():
		var row: int = floori(float(i) / per_row)
		var column: int = i % per_row
		var x: float = left + column * spacing + row * window_shift(radius)
		var z: float = near_z + side * row * spacing
		var tank := OreTank.new()
		tank.setup(ores[i], radius, size.y, size.z)
		tank.position = Vector3(x, size.y * 0.5, z)
		add_child(tank)
		tank.use_point.used.connect(_on_tank_used.bind(tank))
		_tanks[ores[i]] = tank
		cluster.append(tank)
	_add_hub(cluster)
	return cluster


## The cluster's pump hub in the middle of its silos, with a pipe up and over to each silo's top.
func _add_hub(cluster: Array[OreTank]) -> void:
	var center := Vector3.ZERO
	var top: float = 0.0
	for tank: OreTank in cluster:
		center += Vector3(tank.position.x, 0.0, tank.position.z)
		top = maxf(top, tank.height)
	center /= cluster.size()
	top += 0.45
	var hub := MeshInstance3D.new()
	hub.name = "Hub"
	var mesh := CylinderMesh.new()
	mesh.top_radius = HUB_RADIUS * 0.8
	mesh.bottom_radius = HUB_RADIUS
	mesh.height = 1.1
	mesh.radial_segments = 16
	mesh.material = _hub_material
	hub.mesh = mesh
	hub.position = center + Vector3.UP * 0.55
	add_child(hub)
	var riser := center + Vector3.UP * top
	_pipe(center + Vector3.UP * 1.1, riser)
	for tank: OreTank in cluster:
		var over := Vector3(tank.position.x, top, tank.position.z)
		_pipe(riser, over)
		_pipe(Vector3(tank.position.x, tank.height, tank.position.z), over)


func _pipe(from: Vector3, to: Vector3) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = PIPE_RADIUS
	mesh.bottom_radius = PIPE_RADIUS
	mesh.height = from.distance_to(to) + PIPE_RADIUS * 2.0
	mesh.radial_segments = 10
	mesh.rings = 1
	mesh.material = _pipe_material
	var pipe := MeshInstance3D.new()
	pipe.name = "Pipe"
	pipe.mesh = mesh
	pipe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var direction: Vector3 = (to - from).normalized()
	var side: Vector3 = (
		Vector3.RIGHT if absf(direction.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	)
	var basis_x: Vector3 = direction.cross(side).normalized()
	pipe.transform = Transform3D(
		Basis(basis_x, direction, basis_x.cross(direction)), (from + to) * 0.5
	)
	add_child(pipe)


## The silos like reading the bay from the camera: rows from the back (smallest Z) to the front,
## each from left to right. Silos within `ROW_TOLERANCE` of a row's first one share its row.
func _reading_order() -> Array[StationPart]:
	const ROW_TOLERANCE: float = 1.2
	var tanks: Array[OreTank] = []
	tanks.assign(_tanks.values())
	tanks.sort_custom(func(a: OreTank, b: OreTank) -> bool: return a.position.z < b.position.z)
	var order: Array[StationPart] = []
	var row: Array[OreTank] = []
	for tank: OreTank in tanks:
		if not row.is_empty() and tank.position.z - row[0].position.z > ROW_TOLERANCE:
			order.append_array(_left_to_right(row))
			row = []
		row.append(tank)
	order.append_array(_left_to_right(row))
	return order


static func _left_to_right(row: Array[OreTank]) -> Array[StationPart]:
	var sorted: Array[OreTank] = row.duplicate()
	sorted.sort_custom(func(a: OreTank, b: OreTank) -> bool: return a.position.x < b.position.x)
	var parts: Array[StationPart] = []
	parts.assign(sorted)
	return parts
