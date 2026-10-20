class_name LoadoutStation
extends Station
## A player's locker in the armory, where they pick their loadout (see GAME_DESIGN.md, Armory).
## It has two cradles, slots 1 and 2, holding the weapons in the loadout; every weapon of the game
## hangs once on the armory's weapon wall (`wall`), the ones the player doesn't own yet
## see-through ("Locked"). The weapons on the wall and in the cradles are the parts, and the
## camera follows the selected one to the wall and back. The highlight moves over the wall as a
## grid (up from its top line into the cradles), `tab_prev`/`tab_next` jump to the previous or next
## row. `interact` (or the card's slot buttons) puts the selected weapon into the selected slot
## (if it's in the other one, the two swap) or takes it out again, unless it's the only weapon in
## the loadout: one always goes along. The selected slot (its cradle's strip lights up, its number
## turns amber) is the cradle selected last, or an empty one; `slot_1`/`slot_2` (keys 1 and 2) put
## the weapon straight into that slot. Locker `number` belongs to the
## `number`th player; nobody else can open it. While a mission is underway its door stays shut and
## the loadout can't change; lockers of players who aren't in the session stay shut too.

## Between the weapon wall's top edge and the card above it, in m.
const CARD_GAP: float = 0.1

## The cradles' light strips: dim, the selected slot's bright (its number turns amber). A strip
## fully amber made the weapon on it hard to read.
const SLOT_COLOR := Color(0.12, 0.34, 0.4)
const SELECTED_SLOT_COLOR := Color(0.3, 0.85, 1.0)
const SELECTED_NUMBER_COLOR := Color(1.0, 0.75, 0.3)

## The weapon wall the player picks from.
@export var wall: WeaponWall
## How much the camera sees (m high) while a weapon on the wall is selected: the weapon and its
## card above the wall.
@export var wall_view_height: float = 3.0
## Whose locker it is: the `number`th player (1: the first, the one playing solo).
@export_range(1, 4) var number: int = 1
## The owner's color, on the strip along the locker. TBD with co-op (players' colors).
@export var color: Color = Color(0.3, 0.85, 1.0):
	set(value):
		color = value
		if is_node_ready():
			_show_color()

## The slot `interact` puts the selected weapon into (0: slot 1).
var selected_slot: int = 0
## The mission that locks it while underway; found in the scene tree when not set.
var mission: Mission

## One part per cradle, showing the weapon in that slot (hidden while the slot is empty).
var _cradle_parts: Array[StationPart] = []
## What the cradles were last arranged for: the player, their loadout and MK levels.
var _arranged_for: Array = []
var _cradle_materials: Array[StandardMaterial3D] = []
## `view_height` at the locker.
var _locker_view_height: float

## One marker per slot, where the weapon in it lies.
@onready var _cradles: Array[Node3D] = [$Cradle1 as Node3D, $Cradle2 as Node3D]
@onready var _door: Node3D = $Door
## Marks the cradles as the loadout (what goes along on a mission).
@onready var _loadout_sign: Node3D = $LoadoutSign
@onready var _strip: MeshInstance3D = $Strip
@onready var _number_label: Label3D = $Number


func _ready() -> void:
	super()
	_locker_view_height = view_height
	for cradle: Node3D in _cradles:
		var glow := cradle.get_node(^"Glow") as MeshInstance3D
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = SLOT_COLOR
		glow.material_override = material
		_cradle_materials.append(material)
	_number_label.text = str(number)
	_show_color()
	for slot: int in _cradles.size():
		var part := StationPart.new()
		part.name = "Slot%d" % (slot + 1)
		part.pick_radius = 0.3
		part.card_offset = Vector2(1.1, 0.1)
		_cradles[slot].add_child(part)
		_cradle_parts.append(part)
	_arrange()


func _process(delta: float) -> void:
	super(delta)
	if not mission:
		mission = get_tree().get_first_node_in_group(Mission.GROUP) as Mission
	# Lockers of players not in the session stay shut, like all of them during a mission.
	_door.visible = is_locked() or not get_owner_player()
	_loadout_sign.visible = not _door.visible
	for part: StationPart in _cradle_parts:
		part.visible = part.item != null and not _door.visible
	var player: Player = user if user else get_owner_player()
	if _arranged_for != _arrangement(player):
		_arrange()
	view_height = wall_view_height if is_on_wall() else _locker_view_height
	if user:
		refresh()


## The player whose locker it is, or null.
func get_owner_player() -> Player:
	return Station.nth_player(get_tree(), number)


func can_use(player: Player) -> bool:
	return player == get_owner_player()


## Whether loadouts can't change right now.
func is_locked() -> bool:
	return mission != null and mission.is_underway()


## The part showing `weapon_type` on the wall, or null.
func get_part(weapon_type: WeaponType) -> StationPart:
	return wall.get_part(weapon_type) if wall else null


## The part in `slot`'s cradle (its `item` the weapon in that slot, null while empty).
func get_cradle_part(slot: int) -> StationPart:
	return _cradle_parts[slot]


## The weapons in the cradles first (slot 1 is selected on opening), then the wall's.
func get_parts() -> Array[StationPart]:
	var parts: Array[StationPart] = []
	for part: StationPart in _cradle_parts:
		if part.visible:
			parts.append(part)
	if wall:
		parts.append_array(wall.get_parts())
	return parts


## Whether the selected weapon is one on the wall.
func is_on_wall() -> bool:
	return selected != null and wall != null and selected in wall.get_parts()


## The selected weapon on the wall and its card above (up to its top edge), or the locker.
func get_view_center() -> Vector3:
	if is_on_wall():
		var card_top: Vector3 = _above_wall() + Vector3.UP * card.size.y * 0.5 * _card_scale()
		return (selected.global_position + card_top) * 0.5
	return super()


## Whether the player using it can put `weapon_type` into a slot or take it out right now.
func can_change(weapon_type: WeaponType) -> bool:
	return user != null and not is_locked() and user.arsenal.owns(weapon_type)


## Puts `weapon_type` into `slot` (swapping with its other slot), or takes it out when it's there
## already, unless it's the only weapon in the loadout. Returns whether the loadout changed.
func toggle(weapon_type: WeaponType, slot: int) -> bool:
	if not can_change(weapon_type) or slot < 0 or slot >= _cradles.size():
		return false
	if user.loadout.get_weapon(slot) == weapon_type:
		if _loadout_size() <= 1:
			return false
		user.loadout.assign(slot, null)
	else:
		user.loadout.assign(slot, weapon_type)
	_arrange()
	refresh()
	return true


## How many weapons the loadout of the player using it holds.
func _loadout_size() -> int:
	var count: int = 0
	for slot: int in _cradles.size():
		if user.loadout.get_weapon(slot):
			count += 1
	return count


## `slot_1`, `slot_2`, ...: selects that slot and puts the selected weapon into it (or takes it
## out, like `interact`).
func _shortcut(event: InputEvent) -> bool:
	for slot: int in _cradles.size():
		var action := StringName("slot_%d" % (slot + 1))
		if InputMap.has_action(action) and event.is_action_pressed(action):
			selected_slot = slot
			_show_selected_slot()
			if selected:
				toggle(selected.item as WeaponType, slot)
			refresh()
			return true
	return false


## Selecting a weapon in a cradle selects its slot too.
func select(part: StationPart) -> void:
	super(part)
	var slot: int = _cradle_parts.find(part)
	if slot >= 0 and slot != selected_slot:
		selected_slot = slot
		_show_selected_slot()
		refresh()


## `tab_prev`/`tab_next`: the first weapon of the previous or next row on the wall.
func _cycle(step_by: int) -> void:
	if wall:
		var start: StationPart = wall.row_start(selected if is_on_wall() else null, step_by)
		if start:
			select(start)


## On the wall the highlight moves as on a grid; up from its top line it goes to the lowest cradle
## and down from there back to the wall. The cradles are one above the other.
func _neighbor(part: StationPart, direction: Vector2) -> StationPart:
	var cradles: Array[StationPart] = []
	for cradle: StationPart in _cradle_parts:
		if cradle.visible:
			cradles.append(cradle)
	if part in cradles:
		return _from_cradle(cradles, cradles.find(part), direction)
	if not wall:
		return super(part, direction)
	var on_wall: StationPart = wall.neighbor(part, direction)
	if not on_wall and direction.y < -absf(direction.x) and not cradles.is_empty():
		return cradles[-1]
	return on_wall


## Where the highlight goes from the `index`th of the visible `cradles` in `direction`: the
## other cradle, or down to the first weapon of the wall's top row.
func _from_cradle(cradles: Array[StationPart], index: int, direction: Vector2) -> StationPart:
	if absf(direction.y) <= absf(direction.x):
		return null
	var next: int = index + (1 if direction.y > 0.0 else -1)
	if next >= 0 and next < cradles.size():
		return cradles[next]
	if direction.y > 0.0 and wall:
		return wall.row_start(null, 1)
	return null


func _opened() -> void:
	selected_slot = 0
	_arrange()
	_show_selected_slot()
	super()


## On the wall the card floats above it, over the selected weapon, so it hides no other weapon.
func _card_position(camera: Camera3D) -> Vector3:
	return _above_wall() if is_on_wall() else super(camera)


## Where the card floats above the wall, over the selected weapon.
func _above_wall() -> Vector3:
	var at: Vector3 = wall.to_local(selected.global_position)
	at.y = wall.get_top() + CARD_GAP + card.size.y * 0.5 * _card_scale()
	return wall.to_global(at)


## Lays the weapons of the loadout in their cradles, showing the player's levels on them. A
## selected weapon in a cradle stays selected: in its new cradle, or on the wall.
func _arrange() -> void:
	var player: Player = user if user else get_owner_player()
	var followed: WeaponType = selected.item as WeaponType if selected in _cradle_parts else null
	for slot: int in _cradle_parts.size():
		var part: StationPart = _cradle_parts[slot]
		var weapon_type: WeaponType = player.loadout.get_weapon(slot) if player else null
		if part.item != weapon_type:
			_lay(part, weapon_type)
		if weapon_type:
			(part.get_child(0) as Weapon).apply_upgrades(player.upgrades)
		part.visible = weapon_type != null and not _door.visible
	if followed and selected.item != followed:
		var slot: int = player.loadout.slot_of(followed) if player else -1
		select(_cradle_parts[slot] if slot >= 0 else get_part(followed))
	# An empty slot is where the next weapon goes.
	for slot: int in _cradle_parts.size():
		if player and not player.loadout.get_weapon(slot):
			selected_slot = slot
			_show_selected_slot()
			break
	_arranged_for = _arrangement(player)


## Lays a display of `weapon_type` (null: none) in the cradle of `part`.
func _lay(part: StationPart, weapon_type: WeaponType) -> void:
	part.outline = null
	# Freed right away: nothing else refers to the old display.
	for child: Node in part.get_children():
		child.free()
	part.item = weapon_type
	if not weapon_type:
		return
	var display: Weapon = WeaponDisplay.create(weapon_type)
	# Lying with the barrel to the right, like on the wall.
	display.rotation.y = -PI * 0.5
	part.outline = display
	part.add_child(display)
	WeaponDisplay.center(display)
	part.set_highlight(part.highlight)


func _arrangement(player: Player) -> Array:
	if not player:
		return [null]
	return [
		player,
		player.loadout.weapons.duplicate(),
		player.upgrades.levels.duplicate(),
	]


func _show_selected_slot() -> void:
	for slot: int in _cradle_materials.size():
		var chosen: bool = slot == selected_slot
		_cradle_materials[slot].albedo_color = SELECTED_SLOT_COLOR if chosen else SLOT_COLOR
		var label := _cradles[slot].get_node(^"Label") as Label3D
		label.modulate = SELECTED_NUMBER_COLOR if chosen else Color.WHITE


func _show_color() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	_strip.material_override = material
	_number_label.modulate = color
