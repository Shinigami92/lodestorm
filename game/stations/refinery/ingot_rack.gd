class_name IngotRack
extends Station
## The ingot rack beside the furnaces (greybox until the cargo bay's art pass): a steel frame with
## a shelf per alloy of the game (`RackShelf`, from `AlloyCatalog`), a row per tier from the top,
## the bars stacking up on them glowing in the alloy's colors. The bars are kept in the hold
## (`PlayerHold`), so it shows the hold of the player using it, else the viewer's (see
## `Ship.get_viewing_player`); a bar landing from a furnace clinks on its shelf.
## `interact` in front of it opens it as a station; `tab_prev`/`tab_next` step through the shelves
## in reading order (rows from the top, each from left to right), the directions to the nearest
## shelf on screen. The card (`RackCard`) shows the alloy, how many bars there are and its recipe.

const CATALOG: AlloyCatalog = preload("res://game/refinery/all_alloys.tres")
const COLUMNS: int = 2
const SHELF_WIDTH: float = 0.9
const SHELF_DEPTH: float = 0.45
const ROW_HEIGHT: float = 0.52
## Height of the lowest shelf, in m.
const BOTTOM: float = 0.3
const POST_SIZE: float = 0.06
const FRAME_COLOR := Color(0.22, 0.23, 0.25)
const CLINK_SOUND: Sound = preload("res://assets/audio/sfx/refinery/bar_clink.tres")

## The ship whose refinery it belongs to; the one it stands in when not set.
var ship: Ship

var _shelves: Dictionary[AlloyType, RackShelf] = {}
## The shelves in reading order (for `tab_prev`/`tab_next`).
var _reading: Array[StationPart] = []
## The player whose hold it shows right now.
var _shown: Player


func _ready() -> void:
	_build()
	super()


func _process(delta: float) -> void:
	super(delta)
	if not ship:
		ship = Ship.nearest(get_tree(), global_position)
	var viewer: Player = user if user else _viewer()
	show_player(viewer)


## Shows the bars in `player`'s hold (null: all unknown), and their changes from then on.
func show_player(player: Player) -> void:
	if player == _shown:
		return
	if _shown and is_instance_valid(_shown):
		_shown.hold.item_changed.disconnect(_on_item_changed)
		_shown.refining.bars_finished.disconnect(_on_bars_finished)
	_shown = player
	if player:
		player.hold.item_changed.connect(_on_item_changed)
		player.refining.bars_finished.connect(_on_bars_finished)
	for alloy: AlloyType in _shelves:
		_show(alloy)


## The player whose bars it shows (null: none).
func get_shown_player() -> Player:
	return _shown


## The shelf of `alloy`, or null.
func get_shelf(alloy: AlloyType) -> RackShelf:
	return _shelves.get(alloy)


## The shelves in the order `tab_next` steps through them.
func get_reading_order() -> Array[StationPart]:
	return _reading


func get_parts() -> Array[StationPart]:
	return _reading.duplicate()


func _cycle(step_by: int) -> void:
	if _reading.is_empty():
		return
	var index: int = _reading.find(selected)
	select(_reading[posmod(index + step_by, _reading.size())])


func _viewer() -> Player:
	return ship.get_viewing_player() if ship else Player.first_local(get_tree())


func _show(alloy: AlloyType) -> void:
	var shelf: RackShelf = _shelves[alloy]
	if not _shown:
		shelf.show_count(0, false)
	else:
		var hold: PlayerHold = _shown.hold
		shelf.show_count(floori(hold.amount(alloy)), hold.has_found(alloy) or alloy.is_known(hold))
	if user and selected == shelf:
		refresh()


func _on_item_changed(item: ItemType, _amount: float) -> void:
	var alloy := item as AlloyType
	if alloy and _shelves.has(alloy):
		_show(alloy)
	elif item is OreType:
		# A recipe may have become known.
		for shown: AlloyType in _shelves:
			if item in shown.recipe:
				_show(shown)


func _on_bars_finished(_slot: int, alloy: AlloyType, _count: int) -> void:
	var shelf: RackShelf = _shelves.get(alloy)
	if shelf:
		Sfx.play_at(CLINK_SOUND, shelf.global_position)


## The frame (posts, top and base) and a shelf per alloy: rows by tier from the top, `COLUMNS`
## across.
func _build() -> void:
	var frame := StandardMaterial3D.new()
	frame.albedo_color = FRAME_COLOR
	frame.metallic = 0.4
	frame.roughness = 0.5
	var alloys: Array[AlloyType] = CATALOG.alloys
	@warning_ignore("integer_division")
	var rows: int = (alloys.size() + COLUMNS - 1) / COLUMNS
	var width: float = COLUMNS * SHELF_WIDTH + (COLUMNS + 1) * POST_SIZE
	var height: float = BOTTOM + rows * ROW_HEIGHT
	for column: int in COLUMNS + 1:
		var x: float = -width * 0.5 + POST_SIZE * 0.5 + column * (SHELF_WIDTH + POST_SIZE)
		for z: float in [-SHELF_DEPTH * 0.5, SHELF_DEPTH * 0.5]:
			_box(frame, Vector3(POST_SIZE, height, POST_SIZE), Vector3(x, height * 0.5, z))
	_box(frame, Vector3(width, POST_SIZE, SHELF_DEPTH + POST_SIZE), Vector3(0.0, height, 0.0))
	_box(frame, Vector3(width, 0.1, SHELF_DEPTH + POST_SIZE), Vector3(0.0, 0.05, 0.0))
	# A back panel, so the bars read against it.
	_box(frame, Vector3(width, height, 0.03), Vector3(0.0, height * 0.5, -SHELF_DEPTH * 0.5))
	for index: int in alloys.size():
		@warning_ignore("integer_division")
		var row: int = index / COLUMNS
		var column: int = index % COLUMNS
		var shelf := RackShelf.new()
		shelf.setup(alloys[index], SHELF_WIDTH, SHELF_DEPTH)
		shelf.position = Vector3(
			-width * 0.5 + POST_SIZE + column * (SHELF_WIDTH + POST_SIZE) + SHELF_WIDTH * 0.5,
			height - (row + 1) * ROW_HEIGHT,
			0.0
		)
		add_child(shelf)
		_shelves[alloys[index]] = shelf
		_reading.append(shelf)
	var body := StaticBody3D.new()
	body.name = "Body"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, height, SHELF_DEPTH + POST_SIZE)
	shape.shape = box
	shape.position.y = height * 0.5
	body.add_child(shape)
	add_child(body)


func _box(material: Material, box_size: Vector3, at: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = box_size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	add_child(instance)
