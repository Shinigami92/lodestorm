class_name MapPart
extends Node3D
## A point of interest or a set piece a generated location places in one of its areas (a wreck, an
## outpost, ...): the root of its scene. Its props (with colliders) stand within `prop_radius` of
## it; the ground is flattened out to `footprint`, so a walkable ring stays around them. Its front
## (-z) turns towards the way into the area. `PartMarker` children (directly in its scene, not in
## instanced ones) say where ore nodes, nests, crates and quest sites go. Planning reads the scene
## without instancing it (`describe`), so it works on a worker thread. Points of interest show in
## the landmark color in the location hologram. All values greybox, TBD (playtest).


## What `describe` reads from a part's scene.
class Info:
	var display_name: String = ""
	var footprint: float = 0.0
	var prop_radius: float = 0.0
	var min_area_radius: float = 0.0
	var area_kinds: Array[LocationLayout.Kind] = []
	var shapes_basin: bool = false
	## The markers: their kinds, ore bands and where they are in the part.
	var marker_kinds: Array[PartMarker.Kind] = []
	var marker_bands: Array[PartMarker.Band] = []
	var marker_spots: Array[Transform3D] = []

	## Whether it fits an area of `kind` and `radius` (in m; outlines wobble by `wobble`); without
	## `sized`, also one smaller than `min_area_radius`.
	func fits(kind: LocationLayout.Kind, radius: float, wobble: float, sized: bool = true) -> bool:
		if footprint <= 0.0 or radius * (1.0 - wobble) < footprint:
			return false
		if sized and radius < min_area_radius:
			return false
		return kind in area_kinds or (shapes_basin and kind == LocationLayout.Kind.BASIN)

	## How many of its markers are of `kind`.
	func count(kind: PartMarker.Kind) -> int:
		return marker_kinds.count(kind)


## Node properties that make up a node's transform in a scene file.
const TRANSFORM_PROPERTIES: Array[StringName] = [
	&"transform", &"basis", &"quaternion", &"rotation", &"rotation_order", &"scale", &"position"
]

static var _infos: Dictionary[String, Info] = {}
static var _lock := Mutex.new()

## Player-facing name (the location viewer shows it; later its name plate).
@export var display_name: String = ""
## Radius of the flattened ground it stands on, in m.
@export var footprint: float = 12.0
## Radius its props stay within, in m: the ring between it and `footprint` stays walkable.
@export var prop_radius: float = 8.0
## Smallest area it goes into (radius, in m); 0: any area its footprint fits in.
@export var min_area_radius: float = 0.0
## The kinds of areas it fits.
@export var area_kinds: Array[LocationLayout.Kind] = [
	LocationLayout.Kind.BASIN, LocationLayout.Kind.CROSSROADS
]
## Whether, as a set piece, it may turn a basin into its first kind (a crater) when no area of its
## kinds fits.
@export var shapes_basin: bool = false


func _init() -> void:
	add_to_group(HoloTable.LANDMARK_GROUP)


## What the part in `scene` is, read from the scene file (cached): safe on a worker thread.
static func describe(scene: PackedScene) -> Info:
	_lock.lock()
	var info: Info = _infos.get(scene.resource_path)
	if not info:
		info = _read(scene.get_state())
		_infos[scene.resource_path] = info
	_lock.unlock()
	return info


static func _read(state: SceneState) -> Info:
	var info := Info.new()
	var spots: Dictionary[NodePath, Transform3D] = {}
	for node: int in state.get_node_count():
		var path: NodePath = state.get_node_path(node)
		var local: Transform3D = Transform3D.IDENTITY
		var script: Script = null
		var values: Dictionary[StringName, Variant] = {}
		for property: int in state.get_node_property_count(node):
			var property_name: StringName = state.get_node_property_name(node, property)
			var value: Variant = state.get_node_property_value(node, property)
			if property_name == &"script":
				script = value as Script
			else:
				values[property_name] = value
		if node > 0:
			local = (
				spots.get(state.get_node_path(node, true), Transform3D.IDENTITY) * _local(values)
			)
		spots[path] = local
		if script == MapPart and node == 0:
			var root := MapPart.new()
			_apply(root, values)
			info.display_name = root.display_name
			info.footprint = root.footprint
			info.prop_radius = root.prop_radius
			info.min_area_radius = root.min_area_radius
			info.area_kinds = root.area_kinds
			info.shapes_basin = root.shapes_basin
			root.free()
		elif script == PartMarker:
			var marker := PartMarker.new()
			_apply(marker, values)
			info.marker_kinds.append(marker.kind)
			info.marker_bands.append(marker.band)
			info.marker_spots.append(local)
			marker.free()
	return info


## A node's transform from its stored properties.
static func _local(values: Dictionary[StringName, Variant]) -> Transform3D:
	var node := Node3D.new()
	for property_name: StringName in TRANSFORM_PROPERTIES:
		if values.has(property_name):
			node.set(property_name, values[property_name])
	var local: Transform3D = node.transform
	node.free()
	return local


static func _apply(node: Node, values: Dictionary[StringName, Variant]) -> void:
	for property_name: StringName in values:
		node.set(property_name, values[property_name])
