class_name HoldCard
extends StationCard
## The holo card of the hold (`OreHold`): the selected tank's ore, how much the hold has of it and
## the open regions where it's found. An ore never brought aboard shows as unknown.

const NOTE_COLOR := Color(1.0, 1.0, 1.0, 0.75)

@onready var _badge: Control = %Badge
@onready var _title: Label = %Title
@onready var _band: Label = %Band
@onready var _amount: Label = %Amount
@onready var _found_in: Label = %FoundIn
@onready var _close: Button = %Close


func _ready() -> void:
	_close.pressed.connect(_on_close_pressed)


func show_part(part: StationPart) -> void:
	var tank := part as OreTank
	var hold := station as OreHold
	visible = tank != null and hold != null
	if not visible:
		return
	var ore_type: OreType = tank.ore_type
	_set_badge(ore_type if tank.found else null)
	if not tank.found:
		_title.text = tr("Unknown ore")
		_band.text = band_name(ore_type.band)
		_amount.text = ""
		_amount.visible = false
		_found_in.text = tr("Not brought aboard yet.")
		return
	_title.text = ore_type.get_display_name()
	_band.text = band_name(ore_type.band)
	_amount.visible = true
	_amount.text = tr("In the hold: %d") % floori(tank.amount)
	var names: PackedStringArray = []
	for region: Region in hold.regions_with(ore_type):
		names.append(tr(region.display_name))
	if names.is_empty():
		_found_in.text = tr("Found in no open region.")
	else:
		_found_in.text = tr("Found in: %s") % ", ".join(names)


## The translated name of an ore band.
func band_name(band: OreType.Band) -> String:
	match band:
		OreType.Band.MID:
			return tr("Mid ore")
		OreType.Band.SIGNATURE:
			return tr("Signature ore")
	return tr("Common ore")


func _set_badge(ore_type: OreType) -> void:
	for node: Node in _badge.get_children():
		_badge.remove_child(node)
		node.queue_free()
	if ore_type:
		_badge.add_child(OreBadge.new(ore_type, false))
	_badge.visible = ore_type != null


func _on_close_pressed() -> void:
	if station:
		station.close()
