class_name WeaponRack
extends Node3D
## Every weapon of the game (`weapons`) hanging in rows by origin: the colony's arms on top, then
## the converted mining tools, then the expedition's prototypes, each in the order `weapons` lists
## them and named above its start. An origin without weapons gets no row, and the rows grow with
## the weapons, so it holds any number. The armory's weapon wall and the weapons room's rack are
## one. The weapons are parts for the station using it (`StationPart.item` the `WeaponType`),
## their barrels along +X, the rows centered on its origin and going down from it; `panel` (and
## `collision`) are resized to cover them.

## The rows' names, light like the room signs (amber is for what can be used).
const LABEL_COLOR := Color(0.75, 0.8, 0.85)

## Every weapon of the game, in the order they hang in their row.
@export var weapons: Arsenal
## Distance between the weapons in a row, and between the rows, in m.
@export var spacing: float = 1.0
@export var row_spacing: float = 0.6
## Where the holo card floats next to a selected weapon (see `StationPart.card_offset`).
@export var card_offset: Vector2 = Vector2(1.1, 0.1)
## A box behind the weapons and a box shape around them, resized to cover them with `margin`
## around (optional).
@export var panel: MeshInstance3D
@export var collision: CollisionShape3D
@export var margin: float = 0.25
## Whether `panel` and `collision` reach down to the floor (its parent's origin), for a wall
## standing free.
@export var panel_to_floor: bool = false

var _parts: Array[StationPart] = []
var _displays: Array[Weapon] = []
## The origin of each row, top to bottom, and its name.
var _row_origins: Array[WeaponType.Origin] = []
var _labels: Array[Label3D] = []
## The top edge of the weapons and their names with `margin`, from its origin, in m.
var _top: float = 0.0


func _ready() -> void:
	build()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_name_rows()


## The name of the row of weapons from `origin`.
func origin_name(origin: WeaponType.Origin) -> String:
	match origin:
		WeaponType.Origin.TOOL:
			return tr("Converted mining tools")
		WeaponType.Origin.PROTOTYPE:
			return tr("Expedition prototypes")
	return tr("Colony arms")


## The weapons, one part each, in the order they hang (row by row).
func get_parts() -> Array[StationPart]:
	return _parts.duplicate()


## The part showing `weapon_type`, or null.
func get_part(weapon_type: WeaponType) -> StationPart:
	for part: StationPart in _parts:
		if part.item == weapon_type:
			return part
	return null


## The weapons in the order they hang: row by row.
func get_order() -> Array[WeaponType]:
	var order: Array[WeaponType] = []
	for part: StationPart in _parts:
		order.append(part.item as WeaponType)
	return order


## The origins of the rows, top to bottom.
func get_row_origins() -> Array[WeaponType.Origin]:
	return _row_origins.duplicate()


## The rows' names, top to bottom.
func get_labels() -> Array[Label3D]:
	return _labels.duplicate()


## The top edge of the weapons and their names with `margin` (the top of `panel`), from its
## origin, in m.
func get_top() -> float:
	return _top


## The display of `weapon_type` hanging on it, or null.
func get_display(weapon_type: WeaponType) -> Weapon:
	var index: int = get_order().find(weapon_type)
	return _displays[index] if index >= 0 else null


## Shows `player`'s MK levels on the weapons and the ones they don't own see-through (null: all
## solid at MK1).
func show_for(player: Player) -> void:
	var upgrades: Upgrades = player.upgrades if player else Upgrades.new()
	for i: int in _parts.size():
		_displays[i].apply_upgrades(upgrades)
		var owned: bool = not player or player.arsenal.owns(_parts[i].item as WeaponType)
		WeaponDisplay.show_owned(_displays[i], owned)


## Hangs the weapons (again, e.g. after `weapons` changed).
func build() -> void:
	for node: Node in _parts + _labels:
		remove_child(node)
		node.queue_free()
	_parts.clear()
	_displays.clear()
	_labels.clear()
	_row_origins.clear()
	if not weapons:
		return
	var rows: Array[Array] = []
	for origin: int in WeaponType.Origin.values():
		var row: Array[WeaponType] = []
		for weapon_type: WeaponType in weapons.weapons:
			if weapon_type.origin == origin:
				row.append(weapon_type)
		if not row.is_empty():
			rows.append(row)
			_row_origins.append(origin as WeaponType.Origin)
	var longest: int = 0
	for row: Array in rows:
		longest = maxi(longest, row.size())
	var start_x: float = -(longest - 1) * spacing * 0.5
	for r: int in rows.size():
		var y: float = -r * row_spacing
		for i: int in rows[r].size():
			_hang(rows[r][i] as WeaponType, Vector3(start_x + i * spacing, y, 0.0))
		var label := Label3D.new()
		label.name = "Row%d" % (r + 1)
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		label.position = Vector3(start_x - spacing * 0.45, y + row_spacing * 0.4, 0.02)
		label.pixel_size = 0.0025
		label.font_size = 40
		label.outline_size = 8
		label.modulate = LABEL_COLOR
		label.uppercase = true
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		add_child(label)
		_labels.append(label)
	_name_rows()
	_fit(longest, rows.size())


func _hang(weapon_type: WeaponType, at: Vector3) -> void:
	var part := StationPart.new()
	var file_name: String = weapon_type.resource_path.get_file().get_basename().capitalize()
	part.name = file_name if not file_name.is_empty() else "Weapon%d" % (_parts.size() + 1)
	part.item = weapon_type
	part.pick_radius = minf(spacing, row_spacing) * 0.45
	part.card_offset = card_offset
	part.position = at
	var display: Weapon = WeaponDisplay.create(weapon_type)
	# Hanging with the barrel to the right, like on the bench.
	display.rotation.y = -PI * 0.5
	part.outline = display
	add_child(part)
	part.add_child(display)
	WeaponDisplay.center(display)
	_parts.append(part)
	_displays.append(display)


func _name_rows() -> void:
	for r: int in _labels.size():
		_labels[r].text = origin_name(_row_origins[r])


## Resizes `panel` and `collision` to cover `columns` weapons in `rows` rows and their names.
func _fit(columns: int, rows: int) -> void:
	var width: float = maxi(columns, 1) * spacing + margin * 2.0
	var top: float = row_spacing * 0.55 + margin
	_top = top
	var bottom: float = -(maxi(rows, 1) - 1) * row_spacing - row_spacing * 0.5 - margin
	if panel_to_floor:
		bottom = -position.y
	if panel and panel.mesh is BoxMesh:
		var box := panel.mesh.duplicate() as BoxMesh
		box.size = Vector3(width, top - bottom, box.size.z)
		panel.mesh = box
		panel.position = Vector3(0.0, (top + bottom) * 0.5, panel.position.z)
	if collision and collision.shape is BoxShape3D:
		var shape := collision.shape.duplicate() as BoxShape3D
		shape.size = Vector3(width, top - bottom, shape.size.z)
		collision.shape = shape
		collision.global_position = to_global(
			Vector3(0.0, (top + bottom) * 0.5, to_local(collision.global_position).z)
		)
