class_name WeaponWall
extends WeaponRack
## The weapon wall in the middle of the armory (see GAME_DESIGN.md, Armory): every weapon of the
## game once, in rows by origin. Players pick from it into the cradles of their own locker
## (`LoadoutStation.wall`). It shows the weapons of the player using a locker at it, else of the
## first local player: their MK levels, the ones they don't own yet see-through, and under each
## weapon in their loadout its slot's number in their color.

## Below a weapon, where its slot number shows, in m.
const TAG_DROP: float = 0.2

## The player whose weapons it shows, or null.
var viewer: Player

## What it last showed: the player, their loadout, weapons and MK levels.
var _shown_for: Array = []
var _tags: Array[Label3D] = []


func _process(_delta: float) -> void:
	viewer = _find_viewer()
	if _arrangement() != _shown_for:
		_show()


## The slot number under `weapon_type`, or null.
func get_tag(weapon_type: WeaponType) -> Label3D:
	var index: int = get_order().find(weapon_type)
	return _tags[index] if index >= 0 and index < _tags.size() else null


func build() -> void:
	super()
	for tag: Label3D in _tags:
		tag.queue_free()
	_tags.clear()
	for part: StationPart in get_parts():
		var tag := Label3D.new()
		tag.name = "Slot"
		tag.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		tag.position = Vector3(0.0, -TAG_DROP, 0.03)
		tag.pixel_size = 0.004
		tag.font_size = 40
		tag.outline_size = 8
		tag.visible = false
		tag.layers = RenderLayers.EFFECTS
		part.add_child(tag)
		_tags.append(tag)
	_shown_for = []


func _show() -> void:
	show_for(viewer)
	var parts: Array[StationPart] = get_parts()
	for i: int in parts.size():
		var slot: int = viewer.loadout.slot_of(parts[i].item as WeaponType) if viewer else -1
		_tags[i].visible = slot >= 0
		_tags[i].text = str(slot + 1)
		if viewer:
			_tags[i].modulate = viewer.color()
	_shown_for = _arrangement()


func _arrangement() -> Array:
	if not viewer:
		return [null]
	return [
		viewer,
		viewer.color(),
		viewer.loadout.weapons.duplicate(),
		viewer.arsenal.weapons.duplicate(),
		viewer.upgrades.levels.duplicate(),
		viewer.upgrades.jobs.keys(),
	]


func _find_viewer() -> Player:
	var first_local: Player = null
	for node: Node in get_tree().get_nodes_in_group(Player.GROUP):
		var player := node as Player
		var locker := WorldMenu.used_by(get_tree(), player) as LoadoutStation
		if locker and locker.wall == self:
			return player
		if player.local and not first_local:
			first_local = player
	return first_local
