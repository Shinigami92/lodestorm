class_name CargoRack
extends Node3D
## Shows the player's cargo on their back, as one stack of ore poured into glass vessels like
## layered sand: the rarest ore at the bottom, the commonest on top. The stack fills the backpack's
## `TUBES` tall tubes first (left, then right), then canisters strapped on beside the backpack, so a
## big haul makes the silhouette bulkier. Ammo is paid with the commonest ore first, so it takes
## from the top of the stack and rare ore stays safe at the bottom. There's no carry limit, but at
## most `max_canisters` strap on (alternating sides, stacking up); beyond that they all show full.
## Exact amounts show at the silos once it's in the hold. With the hardened canister skill, the
## share of the stack that's safe on death (`safe_share`, from the bottom) sits behind a reinforced
## band.

## Tubes on the backpack.
const TUBES: int = 2
const TUBE_HEIGHT: float = 0.56
const TUBE_RADIUS: float = 0.065
## Distance between the tubes' centers.
const TUBE_SPACING: float = 0.16
const CANISTER_HEIGHT: float = 0.3
const CANISTER_RADIUS: float = 0.085
## Where the canisters hang beside the backpack: sideways from the middle, and the bottom one's
## height. Per side two stack up, the third hangs farther out between them.
const CANISTER_SIDE: float = 0.27
const CANISTER_OUTER: float = 0.45
const CANISTER_BASE: float = -0.05
## Inner radius of the ore inside a vessel, relative to the glass.
const FILL_INSET: float = 0.8
## Outer radius of the reinforced band around a vessel, relative to the glass.
const BAND_OUTSET: float = 1.15

## A cylinder of radius 1 and height 1, shared by all layers (scaled per layer).
static var _shared_cylinder: CylinderMesh

## Units one tube holds. Greybox: one full miner. TBD (playtest).
@export var units_per_tube: float = 180.0
## Units one strapped-on canister holds. TBD (playtest).
@export var units_per_canister: float = 180.0
## Most canisters strapped on at once. TBD (playtest).
@export var max_canisters: int = 6

## The share of the stack (from the bottom) behind the reinforced band (the hardened canister).
var safe_share: float = 0.0:
	set(value):
		safe_share = value
		if is_node_ready():
			_pour()

## Units carried per ore type.
var _cargo: Dictionary[OreType, float] = {}
var _tubes: Array[Node3D] = []
var _canisters: Array[Node3D] = []
var _glass_material := StandardMaterial3D.new()
var _band_material := StandardMaterial3D.new()


func _ready() -> void:
	_glass_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass_material.albedo_color = Color(0.75, 0.85, 0.95, 0.22)
	_glass_material.roughness = 0.1
	_band_material.albedo_color = Color(0.32, 0.34, 0.37)
	_band_material.metallic = 0.8
	_band_material.roughness = 0.35
	for i: int in TUBES:
		var tube: Node3D = _vessel("Tube%d" % (i + 1), TUBE_RADIUS, TUBE_HEIGHT)
		tube.position.x = (i - (TUBES - 1) * 0.5) * TUBE_SPACING
		_tubes.append(tube)
	_pour()


## Shows `amount` units of `ore_type` (connect to `PlayerCargo.ore_changed`).
func show_cargo(ore_type: OreType, amount: float) -> void:
	if amount > 0.0:
		_cargo[ore_type] = amount
	else:
		_cargo.erase(ore_type)
	if is_node_ready():
		_pour()


## The stack from the bottom up: per ore type present, `[ore_type, units]`, rarest first.
func layers() -> Array[Array]:
	var ore_types: Array[OreType] = OreCatalog.sorted(_cargo.keys())
	ore_types.reverse()
	var result: Array[Array] = []
	for ore_type: OreType in ore_types:
		result.append([ore_type, _cargo[ore_type]])
	return result


## Units carried in all.
func total() -> float:
	var sum: float = 0.0
	for amount: float in _cargo.values():
		sum += amount
	return sum


## Fill level (0–1) of tube `index`.
func tube_fill(index: int) -> float:
	return clampf((total() - index * units_per_tube) / units_per_tube, 0.0, 1.0)


## Number of canisters strapped on beside the backpack.
func canister_count() -> int:
	return _canisters.size()


## How far up (0–1) the reinforced band covers tube `index`.
func tube_band(index: int) -> float:
	var safe: float = total() * safe_share
	return clampf((safe - index * units_per_tube) / units_per_tube, 0.0, 1.0)


## Pours the stack into the tubes, then into as many canisters as it needs.
func _pour() -> void:
	var overflow: float = maxf(total() - TUBES * units_per_tube, 0.0)
	var needed: int = mini(ceili(overflow / units_per_canister - 0.0001), max_canisters)
	while _canisters.size() < needed:
		var k: int = _canisters.size()
		var canister: Node3D = _vessel("Canister%d" % (k + 1), CANISTER_RADIUS, CANISTER_HEIGHT)
		var side: float = -1.0 if k % 2 == 0 else 1.0
		var level: int = floori(k / 2.0)
		if level < 2:
			canister.position = Vector3(
				side * CANISTER_SIDE, CANISTER_BASE + level * CANISTER_HEIGHT * 1.04, 0.0
			)
		else:
			canister.position = Vector3(
				side * CANISTER_OUTER, CANISTER_BASE + CANISTER_HEIGHT * 0.5, 0.0
			)
		_canisters.append(canister)
	while _canisters.size() > needed:
		var last: Node3D = _canisters.pop_back()
		remove_child(last)
		last.queue_free()

	var stack: Array[Array] = layers()
	var start: float = 0.0
	for tube: Node3D in _tubes:
		_fill(tube, stack, start, units_per_tube, TUBE_HEIGHT)
		_band(tube, start, units_per_tube, TUBE_HEIGHT)
		start += units_per_tube
	for canister: Node3D in _canisters:
		_fill(canister, stack, start, units_per_canister, CANISTER_HEIGHT)
		_band(canister, start, units_per_canister, CANISTER_HEIGHT)
		start += units_per_canister
	RenderLayers.put(self, RenderLayers.CHARACTERS)


## Shows the part of `stack` between `start` and `start + capacity` units in `vessel`: one layer
## per ore type in that range, from the bottom up.
func _fill(
	vessel: Node3D, stack: Array[Array], start: float, capacity: float, height: float
) -> void:
	var fill: Node3D = vessel.get_node(^"Fill")
	var shown: int = 0
	var below: float = 0.0
	for layer: Array in stack:
		var ore_type: OreType = layer[0]
		var amount: float = layer[1]
		var from: float = maxf(below, start)
		var to: float = minf(below + amount, start + capacity)
		below += amount
		if to <= from:
			continue
		var segment: MeshInstance3D
		if shown < fill.get_child_count():
			segment = fill.get_child(shown)
		else:
			segment = MeshInstance3D.new()
			segment.mesh = _unit_cylinder()
			segment.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			fill.add_child(segment)
		segment.material_override = ore_type.get_glow_material()
		var bottom: float = (from - start) / capacity * height
		var top: float = (to - start) / capacity * height
		var radius: float = (vessel.get_meta(&"radius") as float) * FILL_INSET
		segment.scale = Vector3(radius, maxf(top - bottom, 0.001), radius)
		segment.position.y = (bottom + top) * 0.5
		segment.visible = true
		shown += 1
	for i: int in range(shown, fill.get_child_count()):
		(fill.get_child(i) as Node3D).visible = false


## Covers the safe part of the stack between `start` and `start + capacity` units in `vessel` with
## the reinforced band, from its bottom up.
func _band(vessel: Node3D, start: float, capacity: float, height: float) -> void:
	var band := vessel.get_node(^"Band") as MeshInstance3D
	var covered: float = clampf((total() * safe_share - start) / capacity, 0.0, 1.0) * height
	band.visible = covered > 0.001
	band.scale.y = maxf(covered, 0.001)
	band.position.y = covered * 0.5


## An empty glass vessel (its bottom at its origin) with a `Fill` node for the ore layers.
func _vessel(vessel_name: String, radius: float, height: float) -> Node3D:
	var vessel := Node3D.new()
	vessel.name = vessel_name
	vessel.set_meta(&"radius", radius)
	add_child(vessel)
	var glass := MeshInstance3D.new()
	glass.name = "Glass"
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 1
	mesh.material = _glass_material
	glass.mesh = mesh
	glass.position.y = height * 0.5
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vessel.add_child(glass)
	var fill := Node3D.new()
	fill.name = "Fill"
	vessel.add_child(fill)
	var band := MeshInstance3D.new()
	band.name = "Band"
	band.mesh = _unit_cylinder()
	band.material_override = _band_material
	band.scale = Vector3(radius * BAND_OUTSET, 0.001, radius * BAND_OUTSET)
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	band.visible = false
	vessel.add_child(band)
	return vessel


## The shared layer cylinder.
static func _unit_cylinder() -> CylinderMesh:
	if not _shared_cylinder:
		_shared_cylinder = CylinderMesh.new()
		_shared_cylinder.top_radius = 1.0
		_shared_cylinder.bottom_radius = 1.0
		_shared_cylinder.height = 1.0
		_shared_cylinder.radial_segments = 12
		_shared_cylinder.rings = 1
	return _shared_cylinder
