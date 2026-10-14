class_name WeaponStation
extends UpgradeStation
## The weapons room's station: a rack along the wall with every weapon of the game (`weapons`;
## the ones the player using it doesn't own yet see-through, their upgrades "Locked") and a
## workbench. Picking a weapon on the rack (a click, or `tab_prev`/`tab_next`) lays it on the bench
## (its rack slot stays empty meanwhile), where its parts are the upgrades: the damage at its MK
## pips, the magazine at its magazine pips. The rack grows with the weapons (`rack_spacing` each).

## Where the holo card floats next to the bench's parts (see `StationPart.card_offset`).
const BENCH_CARD_OFFSET := Vector2(1.5, -0.1)

## Every weapon of the game, in rack order.
@export var weapons: Arsenal
## Distance between the weapons on the rack, in m.
@export var rack_spacing: float = 1.0

## The weapon on the bench.
var bench_weapon: WeaponType

var _rack_parts: Array[StationPart] = []
var _bench_display: Weapon
var _bench_parts: Array[StationPart] = []

## The rack's slots start at its origin and go along its +X; `Rack/Panel` is resized to fit them.
## The weapons hang and lie with their barrels along +X.
@onready var _rack: Node3D = $Rack
@onready var _rack_panel: MeshInstance3D = $Rack/Panel
## Where the weapon on the bench lies.
@onready var _bench_spot: Node3D = $BenchSpot


func _ready() -> void:
	super()
	_build_rack()
	if weapons and not weapons.weapons.is_empty():
		lay_on_bench(weapons.weapons[0])


func get_parts() -> Array[StationPart]:
	return _bench_parts.duplicate()


func get_pickable_parts() -> Array[StationPart]:
	var parts: Array[StationPart] = get_parts()
	for part: StationPart in _rack_parts:
		if part.visible:
			parts.append(part)
	return parts


## The weapons on the rack, one part each (`StationPart.item` the `WeaponType`).
func get_rack_parts() -> Array[StationPart]:
	return _rack_parts.duplicate()


func get_upgrades() -> Array[Upgrade]:
	var upgrades: Array[Upgrade] = []
	if weapons:
		for weapon_type: WeaponType in weapons.weapons:
			upgrades.append_array(weapon_type.get_upgrades())
	return upgrades


func get_weapon(upgrade: Upgrade) -> WeaponType:
	if weapons and upgrade:
		for weapon_type: WeaponType in weapons.weapons:
			if upgrade in weapon_type.get_upgrades():
				return weapon_type
	return null


## Lays `weapon_type` on the bench (the one there goes back to the rack) and, while used, selects
## its first part.
func lay_on_bench(weapon_type: WeaponType) -> void:
	bench_weapon = weapon_type
	for part: StationPart in _bench_parts:
		if hovered == part:
			_hover(null)
		part.queue_free()
	_bench_parts.clear()
	if _bench_display:
		_bench_display.queue_free()
	_bench_display = WeaponDisplay.create(weapon_type)
	_bench_spot.add_child(_bench_display)
	var pips_of: Dictionary[NodePath, Upgrade] = {
		^"MkPips": weapon_type.upgrade, ^"MagazinePips": weapon_type.magazine_upgrade
	}
	for path: NodePath in pips_of:
		var pips := _bench_display.get_node_or_null(path) as Node3D
		if not pips or not pips_of[path]:
			continue
		var part := StationPart.new()
		part.name = String(path).trim_suffix("Pips")
		part.item = pips_of[path]
		part.pick_radius = 0.09
		part.card_offset = BENCH_CARD_OFFSET
		part.outline = pips
		_bench_spot.add_child(part)
		part.global_position = pips.global_position
		_bench_parts.append(part)
	for part: StationPart in _rack_parts:
		part.visible = part.item != weapon_type
	_show_owned()
	if user:
		select(_bench_parts[0] if not _bench_parts.is_empty() else null)


func _cycle(step: int) -> void:
	if not weapons or weapons.weapons.is_empty():
		return
	var index: int = weapons.weapons.find(bench_weapon)
	lay_on_bench(weapons.weapons[posmod(index + step, weapons.weapons.size())])


func _picked(part: StationPart) -> void:
	if part in _rack_parts:
		lay_on_bench(part.item as WeaponType)
	else:
		super(part)


func _opened() -> void:
	_show_owned()
	super()


func _bought(_upgrade: Upgrade) -> void:
	_show_owned()


func _build_rack() -> void:
	if not weapons:
		return
	for i: int in weapons.weapons.size():
		var weapon_type: WeaponType = weapons.weapons[i]
		var part := StationPart.new()
		part.name = weapon_type.resource_path.get_file().get_basename().capitalize()
		part.item = weapon_type
		part.pick_radius = rack_spacing * 0.4
		part.position = Vector3(rack_spacing * i, 0.0, 0.0)
		var display: Weapon = WeaponDisplay.create(weapon_type)
		# Hanging with the barrel to the right, like on the bench.
		display.rotation.y = -PI * 0.5
		part.outline = display
		_rack.add_child(part)
		part.add_child(display)
		WeaponDisplay.center(display)
		_rack_parts.append(part)
	var box := _rack_panel.mesh.duplicate() as BoxMesh
	_rack_panel.mesh = box
	var length: float = rack_spacing * weapons.weapons.size()
	box.size.x = length
	_rack_panel.position.x = (length - rack_spacing) * 0.5


## Shows the player's levels on the bench's weapon, and the weapons they don't own see-through.
func _show_owned() -> void:
	for part: StationPart in _rack_parts:
		_set_owned_look(part, part.item as WeaponType)
	if _bench_display:
		if user:
			_bench_display.apply_upgrades(user.upgrades, bench_weapon)
		_set_owned_look(_bench_display, bench_weapon)


func _set_owned_look(root: Node3D, weapon_type: WeaponType) -> void:
	WeaponDisplay.show_owned(root, not user or user.arsenal.owns(weapon_type))
