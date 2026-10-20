class_name WeaponStation
extends UpgradeStation
## The weapons room's station: a rack along the wall with every weapon of the game (`weapons`) in
## rows by origin (a `WeaponRack`; the ones the player using it doesn't own yet see-through, their
## upgrades "Locked") and a workbench. Picking a weapon on the rack (a click, or
## `tab_prev`/`tab_next` in the rack's order) lays it on the bench (its rack slot stays empty
## meanwhile), where its parts are the upgrades, each at its pips (see `WeaponPart`). A weapon the
## player doesn't own is itself a part on the bench (`StationPart.item` the `WeaponType`): with its
## blueprint, the card builds it for its ore from the hold (`build`). The rack grows with the
## weapons, and the camera follows the bench weapon's place on it.

## Where the holo card floats next to the bench's parts (see `StationPart.card_offset`).
const BENCH_CARD_OFFSET := Vector2(1.5, -0.1)

## Every weapon of the game (the rack hangs them in rows by origin).
@export var weapons: Arsenal

## The weapon on the bench.
var bench_weapon: WeaponType

var _bench_display: Weapon
var _bench_parts: Array[StationPart] = []
## The weapon on the bench as a part, to build it; shown while the player doesn't own it.
var _build_part: StationPart

## The weapons hang and lie with their barrels along +X.
@onready var _rack: WeaponRack = $Rack
## Where the weapon on the bench lies.
@onready var _bench_spot: Node3D = $BenchSpot


func _ready() -> void:
	super()
	if _rack.weapons != weapons:
		_rack.weapons = weapons
		_rack.build()
	var order: Array[WeaponType] = _rack.get_order()
	if not order.is_empty():
		lay_on_bench(order[0])


func get_parts() -> Array[StationPart]:
	var parts: Array[StationPart] = []
	if _build_part and _build_part.visible:
		parts.append(_build_part)
	parts.append_array(_bench_parts)
	return parts


func get_pickable_parts() -> Array[StationPart]:
	var parts: Array[StationPart] = get_parts()
	for part: StationPart in _rack.get_parts():
		if part.visible:
			parts.append(part)
	return parts


## The weapons on the rack, one part each (`StationPart.item` the `WeaponType`).
func get_rack_parts() -> Array[StationPart]:
	return _rack.get_parts()


## The bench, shifted halfway towards the bench weapon's empty place on the rack, so the camera
## follows along a long rack.
func get_view_center() -> Vector3:
	var center: Vector3 = super()
	var slot: StationPart = _rack.get_part(bench_weapon)
	if slot:
		var along: Vector3 = _rack.global_basis.x.normalized()
		center += along * along.dot(slot.global_position - center) * 0.5
	return center


## The part building the weapon on the bench (shown while the player doesn't own it), or null.
func get_build_part() -> StationPart:
	return _build_part


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


## Whether the player using it can build `weapon_type` right now: they have its blueprint, the
## hold has its ore and no mission is underway.
func can_build(weapon_type: WeaponType) -> bool:
	return (
		weapon_type != null
		and not is_locked()
		and user != null
		and ship != null
		and user.arsenal.has_blueprint(weapon_type)
		and ship.can_pay(weapon_type.build_cost)
	)


## Builds `weapon_type` for the player using it, paid from the hold. Returns whether it did.
func build(weapon_type: WeaponType) -> bool:
	if not can_build(weapon_type) or not ship.pay(weapon_type.build_cost):
		return false
	user.arsenal.unlock(weapon_type)
	_show_owned()
	if weapon_type == bench_weapon and selected == _build_part:
		select(_bench_parts[0] if not _bench_parts.is_empty() else null)
	refresh()
	return true


## Lays `weapon_type` on the bench (the one there goes back to the rack) and, while used, selects
## its first part (building it, when the player doesn't own it).
func lay_on_bench(weapon_type: WeaponType) -> void:
	bench_weapon = weapon_type
	for part: StationPart in get_parts():
		if hovered == part:
			_hover(null)
		part.queue_free()
	_bench_parts.clear()
	if _build_part and not _build_part.is_queued_for_deletion():
		_build_part.queue_free()
	if _bench_display:
		_bench_display.queue_free()
	_bench_display = WeaponDisplay.create(weapon_type)
	_bench_spot.add_child(_bench_display)
	_build_part = StationPart.new()
	_build_part.name = "Build"
	_build_part.item = weapon_type
	_build_part.pick_radius = 0.3
	_build_part.card_offset = BENCH_CARD_OFFSET
	_build_part.outline = _bench_display
	_bench_spot.add_child(_build_part)
	for weapon_part: WeaponPart in weapon_type.parts:
		var pips := _bench_display.get_node_or_null(NodePath(weapon_part.pips_name())) as Node3D
		if not pips:
			continue
		var part := StationPart.new()
		part.name = String(weapon_part.pips_name()).trim_suffix("Pips")
		part.item = weapon_part
		part.pick_radius = 0.09
		part.card_offset = BENCH_CARD_OFFSET
		part.outline = pips
		_bench_spot.add_child(part)
		part.global_position = pips.global_position
		_bench_parts.append(part)
	for part: StationPart in _rack.get_parts():
		part.visible = part.item != weapon_type
	_show_owned()
	if user:
		var parts: Array[StationPart] = get_parts()
		select(parts[0] if not parts.is_empty() else null)


func _cycle(step_by: int) -> void:
	var order: Array[WeaponType] = _rack.get_order()
	if order.is_empty():
		return
	lay_on_bench(order[posmod(order.find(bench_weapon) + step_by, order.size())])


func _picked(part: StationPart) -> void:
	if part in _rack.get_parts():
		lay_on_bench(part.item as WeaponType)
	else:
		super(part)


func _opened() -> void:
	_show_owned()
	super()


func _bought(_upgrade: Upgrade) -> void:
	_show_owned()


## Shows the player's levels on the bench's weapon, and the weapons they don't own see-through
## (the one on the bench then a part to build it).
func _show_owned() -> void:
	_rack.show_for(user)
	if _bench_display:
		if user:
			_bench_display.apply_upgrades(user.upgrades)
		_set_owned_look(_bench_display, bench_weapon)
	if _build_part:
		_build_part.visible = user != null and not user.arsenal.owns(bench_weapon)


func _set_owned_look(root: Node3D, weapon_type: WeaponType) -> void:
	WeaponDisplay.show_owned(root, not user or user.arsenal.owns(weapon_type))
