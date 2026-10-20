class_name WeaponRack
extends Node3D
## Every weapon of the game (`weapons`) hanging in rows by origin: the colony's arms on top, then
## the converted mining tools, then the expedition's prototypes, each in the order `weapons` lists
## them and named above its start. An origin without weapons gets no row, and the rows grow with
## the weapons, so it holds any number; a row longer than `columns` wraps onto more lines. The
## armory's weapon wall and the weapons room's rack are one. The weapons are parts for the station
## using it (`StationPart.item` the `WeaponType`), their barrels along +X, the lines centered on its
## origin and going down from it; `panel` (and `collision`) are resized to cover them. `neighbor`
## and `row_start` move a keyboard or gamepad highlight over them as a grid.

## The rows' names, light like the room signs (amber is for what can be used).
const LABEL_COLOR := Color(0.75, 0.8, 0.85)

## Every weapon of the game, in the order they hang in their row.
@export var weapons: Arsenal
## Distance between the weapons in a row, and between the rows, in m.
@export var spacing: float = 1.0
@export var row_spacing: float = 0.6
## Extra room above each row for its name, in m (tight lines need it).
@export var label_space: float = 0.0
## At most this many weapons per line; a longer row wraps onto the next line (0: no limit).
@export var columns: int = 0
## Whether its bottom line is at its origin and more lines push the top up (else the top line is
## at its origin and they go down), e.g. a rack above a bench.
@export var grow_up: bool = false
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
## The parts on each line, top to bottom, and the row each line belongs to.
var _lines: Array[Array] = []
var _line_rows: Array[int] = []
## The top edge of the weapons and their names with `margin`, from its origin, in m.
var _top: float = 0.0
## Half its width with `margin`, in m (its lines are centered on its origin).
var _half_width: float = 0.0


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


## The line `part` hangs on (0: the top one), or -1.
func get_line(part: StationPart) -> int:
	for line: int in _lines.size():
		if part in _lines[line]:
			return line
	return -1


## The visible part next to `part` in `direction` (on screen: up is -Y): left and right along its
## line, up and down the nearest one on the line above or below; null at the edge.
func neighbor(part: StationPart, direction: Vector2) -> StationPart:
	var line: int = get_line(part)
	if line < 0:
		return null
	if absf(direction.x) > absf(direction.y):
		var on_line: Array = _lines[line]
		var step_by: int = 1 if direction.x > 0.0 else -1
		var i: int = on_line.find(part) + step_by
		while i >= 0 and i < on_line.size():
			if (on_line[i] as StationPart).visible:
				return on_line[i] as StationPart
			i += step_by
		return null
	var line_step: int = 1 if direction.y > 0.0 else -1
	var next: int = line + line_step
	while next >= 0 and next < _lines.size():
		var nearest: StationPart = nearest_on_line(next, part.position.x)
		if nearest:
			return nearest
		next += line_step
	return null


## The visible part on `line` nearest to `x` (along the lines), or null.
func nearest_on_line(line: int, x: float) -> StationPart:
	var nearest: StationPart = null
	for candidate: StationPart in _lines[line]:
		if not candidate.visible:
			continue
		if not nearest or absf(candidate.position.x - x) < absf(nearest.position.x - x):
			nearest = candidate
	return nearest


## How many lines it has.
func get_line_count() -> int:
	return _lines.size()


## The first visible part of the row `step_by` rows from `part`'s (wrapping around; `part` null:
## from before the first row), or null.
func row_start(part: StationPart, step_by: int) -> StationPart:
	if _row_origins.is_empty():
		return null
	var line: int = get_line(part) if part else -1
	var row: int = _line_rows[line] if line >= 0 else (-1 if step_by > 0 else 0)
	for attempt: int in _row_origins.size():
		row = posmod(row + step_by, _row_origins.size())
		for first: int in _lines.size():
			if _line_rows[first] != row:
				continue
			for candidate: StationPart in _lines[first]:
				if candidate.visible:
					return candidate
	return null


## Half its width with `margin` (the panel's), in m: its lines are centered on its origin.
func get_half_width() -> float:
	return _half_width


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
	_lines.clear()
	_line_rows.clear()
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
	if columns > 0:
		longest = mini(longest, columns)
	var start_x: float = -(longest - 1) * spacing * 0.5
	var line_count: int = 0
	for row: Array in rows:
		line_count += ceili(float(row.size()) / longest)
	var height: float = (line_count - 1) * row_spacing + (rows.size() - 1) * label_space
	var lift: float = height if grow_up else 0.0
	for r: int in rows.size():
		var y: float = lift - _lines.size() * row_spacing - r * label_space
		for i: int in rows[r].size():
			var column: int = i % longest
			if column == 0:
				_lines.append([])
				_line_rows.append(r)
			var line_y: float = lift - (_lines.size() - 1) * row_spacing - r * label_space
			_lines[-1].append(
				_hang(rows[r][i] as WeaponType, Vector3(start_x + column * spacing, line_y, 0.0))
			)
		var label := Label3D.new()
		label.name = "Row%d" % (r + 1)
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		var label_y: float = y + row_spacing * 0.4 + label_space * 0.6
		label.position = Vector3(start_x - spacing * 0.45, label_y, 0.02)
		label.pixel_size = 0.0025
		label.font_size = 40
		label.outline_size = 8
		label.modulate = LABEL_COLOR
		label.uppercase = true
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		add_child(label)
		_labels.append(label)
	_name_rows()
	_fit(longest, height, lift)


func _hang(weapon_type: WeaponType, at: Vector3) -> StationPart:
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
	return part


func _name_rows() -> void:
	for r: int in _labels.size():
		_labels[r].text = origin_name(_row_origins[r])


## Resizes `panel` and `collision` to cover `across` weapons on lines `height` from the top one to
## the bottom one and their names, the top line `lift` above its origin.
func _fit(across: int, height: float, lift: float) -> void:
	var width: float = maxi(across, 1) * spacing + margin * 2.0
	_half_width = width * 0.5
	var top: float = lift + row_spacing * 0.55 + label_space * 0.6 + margin
	_top = top
	var bottom: float = lift - height - row_spacing * 0.5 - margin
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
