class_name LoadoutStation
extends Station
## A player's locker in the armory, where they pick their loadout (see GAME_DESIGN.md, Armory).
## Every weapon of the game (`weapons`) hangs in it, the ones the player doesn't own yet
## see-through ("Locked"); below are two cradles, slots 1 and 2, holding the weapons in the
## loadout. The weapons are the parts; `tab_prev`/`tab_next` pick the slot (its cradle's strip
## lights up, its number turns amber), and `interact` (or the card's slot buttons) puts the
## selected weapon into that slot (if it's in the other one, the two swap) or takes it out again,
## unless it's the only weapon in the loadout: one always goes along. `slot_1`/`slot_2` (keys 1
## and 2) put it straight into that slot. Locker `number` belongs to the `number`th player; nobody
## else can open it. While a mission is underway its door stays shut and the loadout can't change;
## lockers of players who aren't in the session stay shut too.

## The cradles' light strips: dim, the selected slot's bright (its number turns amber). A strip
## fully amber made the weapon on it hard to read.
const SLOT_COLOR := Color(0.12, 0.34, 0.4)
const SELECTED_SLOT_COLOR := Color(0.3, 0.85, 1.0)
const SELECTED_NUMBER_COLOR := Color(1.0, 0.75, 0.3)

## Every weapon of the game, in the order they hang.
@export var weapons: Arsenal
## Whose locker it is: the `number`th player (1: the first, the one playing solo).
@export_range(1, 4) var number: int = 1
## The owner's color, on the strip along the locker. TBD with co-op (players' colors).
@export var color: Color = Color(0.3, 0.85, 1.0):
	set(value):
		color = value
		if is_node_ready():
			_show_color()
## Vertical distance between the weapons hanging in it, and how many hang in a column (more
## weapons start the next column, `column_spacing` to the right).
@export var row_spacing: float = 0.34
@export var rows_per_column: int = 4
@export var column_spacing: float = 1.0

## The slot `interact` puts the selected weapon into (0: slot 1).
var selected_slot: int = 0
## The mission that locks it while underway; found in the scene tree when not set.
var mission: Mission

var _weapon_parts: Array[StationPart] = []
## What the weapons were last arranged for: the player, their loadout, weapons and MK levels.
var _arranged_for: Array = []
var _cradle_materials: Array[StandardMaterial3D] = []

## Where the weapons hang (the first at its origin, then down).
@onready var _rack: Node3D = $Rack
## One marker per slot, where the weapon in it lies.
@onready var _cradles: Array[Node3D] = [$Cradle1 as Node3D, $Cradle2 as Node3D]
@onready var _door: Node3D = $Door
## Marks the cradles as the loadout (what goes along on a mission).
@onready var _loadout_sign: Node3D = $LoadoutSign
@onready var _strip: MeshInstance3D = $Strip
@onready var _number_label: Label3D = $Number


func _ready() -> void:
	super()
	for cradle: Node3D in _cradles:
		var glow := cradle.get_node(^"Glow") as MeshInstance3D
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = SLOT_COLOR
		glow.material_override = material
		_cradle_materials.append(material)
	_number_label.text = str(number)
	_show_color()
	_build()


func _process(delta: float) -> void:
	super(delta)
	if not mission:
		mission = get_tree().get_first_node_in_group(Mission.GROUP) as Mission
	# Lockers of players not in the session stay shut, like all of them during a mission.
	_door.visible = is_locked() or not get_owner_player()
	_rack.visible = not _door.visible
	_loadout_sign.visible = not _door.visible
	var player: Player = user if user else get_owner_player()
	if player and _arranged_for != _arrangement(player):
		_arrange()
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


## The part showing `weapon_type`, or null.
func get_part(weapon_type: WeaponType) -> StationPart:
	for part: StationPart in _weapon_parts:
		if part.item == weapon_type:
			return part
	return null


func get_parts() -> Array[StationPart]:
	return _weapon_parts.duplicate()


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


func _cycle(step_by: int) -> void:
	selected_slot = posmod(selected_slot + step_by, _cradles.size())
	_show_selected_slot()
	refresh()


func _opened() -> void:
	selected_slot = 0
	_show_selected_slot()
	_arrange()
	super()


func _build() -> void:
	if not weapons:
		return
	for weapon_type: WeaponType in weapons.weapons:
		var part := StationPart.new()
		part.name = weapon_type.resource_path.get_file().get_basename().capitalize()
		part.item = weapon_type
		part.pick_radius = 0.3
		part.card_offset = Vector2(1.1, 0.1)
		var display: Weapon = WeaponDisplay.create(weapon_type)
		# Hanging with the barrel to the right, like on the weapons rack.
		display.rotation.y = -PI * 0.5
		part.outline = display
		_rack.add_child(part)
		part.add_child(display)
		WeaponDisplay.center(display)
		_weapon_parts.append(part)
	_arrange()


## Hangs every weapon at its place, or lays it in its slot's cradle; shows the player's levels on
## them and the ones they don't own see-through.
func _arrange() -> void:
	var player: Player = user if user else get_owner_player()
	for i: int in _weapon_parts.size():
		var part: StationPart = _weapon_parts[i]
		var weapon_type := part.item as WeaponType
		var slot: int = player.loadout.slot_of(weapon_type) if player else -1
		if slot >= 0 and slot < _cradles.size():
			part.global_position = _cradles[slot].global_position
		else:
			part.position = Vector3(
				floori(float(i) / rows_per_column) * column_spacing,
				-(i % rows_per_column) * row_spacing,
				0.0
			)
		var display := part.get_child(0) as Weapon
		if player:
			display.apply_upgrades(player.upgrades)
		WeaponDisplay.show_owned(display, not player or player.arsenal.owns(weapon_type))
	_arranged_for = _arrangement(player) if player else []


func _arrangement(player: Player) -> Array:
	return [
		player,
		player.loadout.weapons.duplicate(),
		player.arsenal.weapons.duplicate(),
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
