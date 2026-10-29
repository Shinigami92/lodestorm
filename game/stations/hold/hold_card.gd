class_name HoldCard
extends StationCard
## The holo card of the hold (`OreHold`): the selected tank's ore, how much the hold has of it and
## the open regions where it's found, and for an ore too hard for a miner's first drill the drill
## level that mines it at full speed. An ore never brought aboard shows as unknown. An ore found in
## more regions than fit names the bodies instead.

## The most regions the card names; beyond that it names their bodies.
const MAX_REGIONS: int = 4
const DRILL: Upgrade = preload("res://game/progression/upgrades/miner_drill.tres")

@onready var _badge: CenterContainer = %Badge
@onready var _title: Label = %Title
@onready var _band: Label = %Band
@onready var _amount: Label = %Amount
@onready var _found_in: Label = %FoundIn
@onready var _drill: Label = %Drill


func show_part(part: StationPart) -> void:
	var tank := part as OreTank
	var hold := station as OreHold
	visible = tank != null and hold != null
	if not visible:
		return
	var ore_type: OreType = tank.ore_type
	ItemBadge.show_in(_badge, ore_type if tank.found else null, false)
	var drill_mk: int = DRILL.mk_for_hardness(ore_type.hardness)
	_drill.visible = tank.found and drill_mk > 1
	_drill.text = tr("Full speed with drill MK%d.") % drill_mk
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
	var regions: Array[Region] = hold.regions_with(ore_type)
	var names: PackedStringArray = []
	if regions.is_empty():
		_found_in.text = tr("Found in no open region.")
	elif regions.size() <= MAX_REGIONS:
		for region: Region in regions:
			names.append(tr(region.display_name))
		_found_in.text = tr("Found in: %s") % ", ".join(names)
	else:
		for body: CelestialBody in hold.bodies_with(ore_type):
			names.append(tr(body.display_name))
		_found_in.text = tr("Found on: %s") % ", ".join(names)


## The translated name of an ore band.
func band_name(band: OreType.Band) -> String:
	match band:
		OreType.Band.MID:
			return tr("Mid ore")
		OreType.Band.SIGNATURE:
			return tr("Signature ore")
	return tr("Common ore")
