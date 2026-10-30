class_name OreNode
extends Node3D
## A deposit of one ore type that a single miner can be placed on (a player about to place one sees
## a preview of it there, see `MinerPreview`). Close to a player, its crystals also show behind
## cliffs, as a faint silhouette in the ore's color (farther out finding ore stays exploring).
## It holds a limited amount (`amount`, from its ore's band, see `FILLS`, more in a rich field) that
## its miner takes out (`mine`): its crystals shrink into the rock one after another as it empties,
## the smallest first (each holds its share by its volume), until only the rock is left once it's
## dry.

const GROUP: StringName = &"ore_nodes"
## How many fills of a standard-issue miner's tank (`MinerSettings.capacity`) a node of each band
## holds: rarer ore, smaller deposits. TBD (playtest).
const FILLS: Dictionary[OreType.Band, float] = {
	OreType.Band.COMMON: 1.0,
	OreType.Band.MID: 0.75,
	OreType.Band.SIGNATURE: 0.5,
}
## How many times that a node in a nest hollow's rich field holds (`rich`). TBD (playtest).
const RICH_FACTOR: float = 2.0
const MINER_SETTINGS: MinerSettings = preload("res://game/mining/miner_settings.tres")
## How close a player must be for the crystals to show behind cliffs, in m. TBD (playtest).
const SILHOUETTE_RANGE: float = 30.0
## How often the distance to the players is checked, in s.
const SILHOUETTE_CHECK: float = 0.25

@export var ore_type: OreType
## Which of the ore type's model variants this node shows (wraps around), so neighboring nodes
## can look different.
@export var variant: int = 0
## In a nest hollow's rich field: holds `RICH_FACTOR` times its band's amount.
@export var rich: bool = false

## Units it holds untouched; 0: from its ore's band (`FILLS`). Set before it enters the tree.
var full_amount: float = 0.0
## Units left, dry at 0; below 0: `full_amount` (set before it enters the tree).
var amount: float = -1.0
## The miner placed on this node, or null.
var miner: Miner

var _silhouette: ShaderMaterial
var _check_left: float = 0.0
## The crystals, smallest first, with their untouched bases and the share of `full_amount` mined
## when each is gone (rising to 1).
var _crystal_list: Array[Node3D] = []
var _crystal_bases: Array[Basis] = []
var _crystal_ends: Array[float] = []

@onready var _mount: Marker3D = $MinerMount
@onready var _deposit: MeshInstance3D = $Deposit
@onready var _crystals: Node3D = $Crystals


func _ready() -> void:
	add_to_group(GROUP)
	if ore_type.model and not ore_type.variants.is_empty():
		_use_model()
	if full_amount <= 0.0:
		full_amount = FILLS[ore_type.band] * MINER_SETTINGS.capacity
		if rich:
			full_amount *= RICH_FACTOR
	if amount < 0.0:
		amount = full_amount
	_list_crystals()
	_update_crystals()
	var phase: float = OreGlow.phase_at(global_position)
	for crystal: Node in _crystals.get_children():
		(crystal as MeshInstance3D).material_override = ore_type.get_material()
		OreGlow.set_phase(crystal as MeshInstance3D, phase)
	var color: Color = ore_type.color
	color.a = OccludedSilhouette.ORE_ALPHA
	_silhouette = OccludedSilhouette.overlay(color)
	OccludedSilhouette.mark_visible(self)


func _process(delta: float) -> void:
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = SILHOUETTE_CHECK
	var shown: bool = false
	for player: Node3D in get_tree().get_nodes_in_group(Player.GROUP):
		if player.global_position.distance_to(global_position) <= SILHOUETTE_RANGE:
			shown = true
			break
	show_silhouette(shown)


## Whether the crystals show behind cliffs (close to a player).
func is_silhouette_shown() -> bool:
	return (
		_crystals.get_child_count() > 0
		and ((_crystals.get_child(0) as GeometryInstance3D).material_overlay != null)
	)


## Shows the crystals behind cliffs or not.
func show_silhouette(shown: bool) -> void:
	for crystal: Node in _crystals.get_children():
		(crystal as GeometryInstance3D).material_overlay = _silhouette if shown else null


## Replaces the greybox deposit and crystals with the variant's meshes from the ore type's model.
func _use_model() -> void:
	var variant_name: StringName = ore_type.variants[posmod(variant, ore_type.variants.size())]
	for crystal: Node in _crystals.get_children():
		_crystals.remove_child(crystal)
		crystal.free()
	for part: MeshInstance3D in ModelParts.child_parts(ore_type.model, variant_name):
		if part.name.begins_with("Base"):
			_deposit.mesh = part.mesh
			_deposit.transform = part.transform
			part.free()
		elif part.name.begins_with("Crystal"):
			_crystals.add_child(part)
		else:
			part.free()


func is_free() -> bool:
	return not is_instance_valid(miner)


func is_dry() -> bool:
	return amount == 0.0


## Takes up to `max_amount` units out (for its miner) and returns how many were taken.
func mine(max_amount: float) -> float:
	if is_dry():
		return 0.0
	var taken: float = clampf(max_amount, 0.0, amount)
	amount -= taken
	if is_node_ready():
		_update_crystals()
	return taken


## Places a new miner from `miner_scene` on this node and returns it, or null if occupied or dry.
## With `fleet` it's `choice` of that fleet, or the one placing takes by default (see
## `Miner.take_from`), placed by `by`; without, a loose MK1 miner. `projected`: it starts as a
## hologram that `by` builds (see `MinerHandling`); else it stands at once.
func place_miner(
	miner_scene: PackedScene,
	fleet: MinerFleet = null,
	by: Player = null,
	projected: bool = false,
	choice: MinerChoice = null,
) -> Miner:
	if not is_free() or is_dry():
		return null
	miner = miner_scene.instantiate() as Miner
	miner.ore_type = ore_type
	miner.ore_node = self
	if fleet:
		miner.take_from(fleet, by, choice)
	if projected and by:
		miner.handled_by = by
		miner.built = 0.0
	_mount.add_child(miner)
	return miner


## Where a miner placed on it stands.
func get_mount_position() -> Vector3:
	return _mount.global_position


## The free ore node closest to `from` within `max_distance` (horizontally) that isn't dry, or
## null.
static func nearest_free(tree: SceneTree, from: Vector3, max_distance: float) -> OreNode:
	var nearest: OreNode = null
	var nearest_distance: float = max_distance
	for node: OreNode in tree.get_nodes_in_group(GROUP):
		var offset: Vector3 = node.global_position - from
		var distance: float = Vector2(offset.x, offset.z).length()
		if distance <= nearest_distance and node.is_free() and not node.is_dry():
			nearest = node
			nearest_distance = distance
	return nearest


## Orders the crystals smallest first and gives each its share of the amount by its volume.
func _list_crystals() -> void:
	var volumes: Dictionary[Node3D, float] = {}
	var total: float = 0.0
	for crystal: Node in _crystals.get_children():
		var volume: float = _volume(crystal as MeshInstance3D)
		volumes[crystal as Node3D] = volume
		total += volume
	_crystal_list.assign(volumes.keys())
	_crystal_list.sort_custom(func(a: Node3D, b: Node3D) -> bool: return volumes[a] < volumes[b])
	var mined: float = 0.0
	for crystal: Node3D in _crystal_list:
		_crystal_bases.append(crystal.basis)
		mined += volumes[crystal] / total if total > 0.0 else 1.0 / _crystal_list.size()
		_crystal_ends.append(mined)
	if not _crystal_ends.is_empty():
		_crystal_ends[-1] = 1.0


## Shrinks each crystal into the rock as far as its share is mined, hiding the ones mined out.
func _update_crystals() -> void:
	var mined: float = 1.0 - amount / full_amount if full_amount > 0.0 else 1.0
	var start: float = 0.0
	for i: int in _crystal_list.size():
		var end: float = _crystal_ends[i]
		var left: float = clampf((end - mined) / maxf(end - start, 0.0001), 0.0, 1.0)
		var crystal: Node3D = _crystal_list[i]
		# A zero scale makes the basis singular, so a mined out crystal hides instead.
		crystal.visible = left > 0.0
		crystal.basis = _crystal_bases[i] * maxf(left, 0.001)
		start = end


## A crystal's volume in m³ (its mesh is closed), so bigger crystals hold more.
static func _volume(crystal: MeshInstance3D) -> float:
	if not crystal or not crystal.mesh:
		return 0.0
	var faces: PackedVector3Array = crystal.mesh.get_faces()
	var volume: float = 0.0
	for i: int in range(0, faces.size() - 2, 3):
		volume += faces[i].dot(faces[i + 1].cross(faces[i + 2]))
	return absf(volume / 6.0 * crystal.basis.determinant())
