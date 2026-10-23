class_name NavigatorCard
extends StationCard
## The holo card of the navigator (`NavigatorStation`): what's selected and what can be done with
## it. The star: its name; a body: its kind and tier, its signature ore ("?" while it can't be
## reached; "Zoom in"); a region: its biome and tier, danger, timer and ores ("Zoom in", "Set as
## destination"); the landing site: the mission's location name and where
## things stand (destination set, scanning, in flight, landed). A body out of the heat shield's
## reach, and its regions, say which MK level it needs, with the ores of that plate's cost.

const DANGER_COLORS: Array[Color] = [
	Color(0.45, 0.95, 0.55), Color(1.0, 0.75, 0.3), Color(1.0, 0.4, 0.35)
]
const STATUS_COLOR := Color(1.0, 0.75, 0.3)

## What's shown (a body or a region), or null.
var item: Resource

## The ores the badges show, and the ores of the plate a locked body needs.
var _shown_ores: Array[OreType] = []
var _needed_ores: Array[OreType] = []

@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _info: GridContainer = %Info
@onready var _danger: Label = %Danger
@onready var _timer: Label = %Timer
@onready var _ores: HFlowContainer = %Ores
## Rows shown for a region only (the tier and ore rows show for bodies too).
@onready var _region_rows: Array[Control] = [%DangerLabel, %Danger, %TimerLabel, %Timer]
@onready var _ore_rows: Array[Control] = [%OresLabel, %Ores]
@onready var _status: Label = %Status
@onready var _needs: HFlowContainer = %Needs
@onready var _primary: Button = %Primary
@onready var _choose: Button = %Choose
@onready var _back: Button = %Back
@onready var _close: Button = %Close


func _ready() -> void:
	_primary.pressed.connect(_on_zoom_pressed)
	_choose.pressed.connect(_on_choose_pressed)
	_back.pressed.connect(_on_back_pressed)
	_close.pressed.connect(_on_close_pressed)


func show_part(part: StationPart) -> void:
	var navigator := station as NavigatorStation
	item = part.item if part else null
	visible = item != null and navigator != null
	if not visible:
		return
	_status.add_theme_color_override(&"font_color", STATUS_COLOR)
	_choose.visible = item is Region
	var needed: ShieldPlate = null
	if item is StarSystem:
		_show_star(item as StarSystem)
	elif item is CelestialBody:
		needed = _show_body(navigator, item as CelestialBody)
	elif item is Region:
		needed = _show_region(navigator, item as Region)
	_status.visible = _status.text != ""
	_show_needed(needed)
	_back.visible = navigator.level != NavigatorStation.Level.SYSTEM


func _show_star(star: StarSystem) -> void:
	_title.text = tr(star.display_name)
	_subtitle.text = tr("Star")
	_info.visible = false
	_primary.visible = false
	_status.text = ""


## Shows `shown_body`: its kind and tier, its signature ores, "Zoom in". Returns the heat shield
## plate it needs (null: none, or none would help).
func _show_body(navigator: NavigatorStation, shown_body: CelestialBody) -> ShieldPlate:
	var reachable: bool = navigator.is_reachable(shown_body)
	_title.text = tr(shown_body.display_name)
	_subtitle.text = shown_body.kind_name()
	if shown_body.kind != CelestialBody.Kind.STATION:
		_subtitle.text = _with_tier(_subtitle.text, shown_body)
	_show_rows(_region_rows, false)
	var signature: Array[OreType] = []
	for ore_type: OreType in shown_body.signature_ores:
		signature.append(ore_type if reachable else null)
	_info.visible = not signature.is_empty()
	_show_rows(_ore_rows, not signature.is_empty())
	_show_ores(signature)
	_primary.visible = true
	_primary.text = tr("Zoom in")
	_primary.disabled = not reachable
	if reachable:
		_status.text = ""
	elif shown_body.kind == CelestialBody.Kind.STATION:
		_status.text = tr("No docking yet.")
	elif shown_body.kind == CelestialBody.Kind.GAS_GIANT:
		_status.text = tr("Nowhere to land: its moons can be visited.")
	else:
		_status.text = _needs_text(shown_body)
		return _needed_plate(navigator, shown_body)
	return null


## Shows `shown_region` (at its landing site: its mission's location name): its biome and tier,
## danger, timer and ores, "Zoom in" and "Set as destination", and where things stand. Returns
## the heat shield plate its body needs (null: none).
func _show_region(navigator: NavigatorStation, shown_region: Region) -> ShieldPlate:
	var voyage: Voyage = navigator.voyage
	var offer: MissionBrief = navigator.get_offer(shown_region)
	var reachable: bool = navigator.is_reachable(shown_region)
	var at_landing_site: bool = navigator.level == NavigatorStation.Level.REGION
	_title.text = (
		offer.location_name() if offer and at_landing_site else tr(shown_region.display_name)
	)
	_subtitle.text = tr(shown_region.biome.display_name) if shown_region.biome else ""
	var system: StarSystem = navigator.get_system()
	var region_body: CelestialBody = system.body_of(shown_region) if system else null
	if region_body:
		_subtitle.text = _with_tier(_subtitle.text, region_body)
	_info.visible = true
	_show_rows(_region_rows, true)
	_show_rows(_ore_rows, true)
	_danger.text = MissionBrief.for_region(shown_region, 1).difficulty_name()
	_danger.add_theme_color_override(&"font_color", DANGER_COLORS[shown_region.danger])
	_timer.text = ""
	if voyage:
		var minutes: float = voyage.mission.settings.duration * shown_region.length / 60.0
		_timer.text = tr("%d min") % roundi(minutes)
	_show_ores(navigator.shown_ores(shown_region))
	_primary.visible = not at_landing_site
	_primary.text = tr("Zoom in")
	_primary.disabled = not reachable
	_choose.text = tr("Set as destination")
	var chosen: bool = offer != null and voyage != null and offer == voyage.destination
	_choose.disabled = not reachable or not voyage or not voyage.can_select() or chosen
	_status.text = _region_status(navigator, shown_region, offer)
	if region_body and not reachable:
		return _needed_plate(navigator, region_body)
	return null


## `interact`: zooms in, or at a landing site chooses it as the destination.
func press_primary() -> bool:
	var navigator := station as NavigatorStation
	return navigator != null and navigator.activate()


## Where things stand for `shown_region` (its mission `offer`).
func _region_status(
	navigator: NavigatorStation, shown_region: Region, offer: MissionBrief
) -> String:
	var voyage: Voyage = navigator.voyage
	var text: String = ""
	var system: StarSystem = navigator.get_system()
	if not navigator.is_reachable(shown_region):
		var region_body: CelestialBody = system.body_of(shown_region) if system else null
		text = _needs_text(region_body) if region_body else tr("Locked")
	elif not voyage or not offer:
		text = ""
	elif voyage.flight.is_flying():
		text = tr("In flight: gear up and head for the ramp.")
	elif not voyage.can_select():
		text = tr("Locked until everyone is back aboard.")
	elif offer == voyage.brief:
		text = tr("Landed: lower the ramp in the cargo bay.")
	elif offer != voyage.destination:
		text = ""
	elif voyage.is_preparing(offer):
		text = tr("Scanning the location...")
	else:
		text = tr("Destination set: set course at the cockpit.")
	return text


func _on_zoom_pressed() -> void:
	var navigator := station as NavigatorStation
	if navigator:
		navigator.activate()


func _on_choose_pressed() -> void:
	var navigator := station as NavigatorStation
	if navigator:
		navigator.choose_destination()


## The ores as badges with their names (from common to rare); null shows as "?" (an ore not known
## yet).
func _show_ores(ores: Array[OreType]) -> void:
	if ores == _shown_ores:
		return
	_shown_ores = ores.duplicate()
	for node: Node in _ores.get_children():
		_ores.remove_child(node)
		node.queue_free()
	for ore_type: OreType in ores:
		if ore_type:
			_ores.add_child(ItemBadge.new(ore_type))
		else:
			var unknown := Label.new()
			unknown.text = "?"
			unknown.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			_ores.add_child(unknown)


## What a body out of reach needs: the heat shield MK level of its tier.
func _needs_text(of_body: CelestialBody) -> String:
	return tr("Needs heat shield MK%d (engine room)") % of_body.tier


## The heat shield plate that brings `of_body` in reach, or null.
static func _needed_plate(navigator: NavigatorStation, of_body: CelestialBody) -> ShieldPlate:
	var shield: HeatShield = navigator.get_heat_shield()
	return shield.plate_for(of_body.tier) if shield else null


## The ores of `plate`'s cost as badges (null: none).
func _show_needed(plate: ShieldPlate) -> void:
	var ores: Array[OreType] = []
	if plate:
		ores.assign(plate.cost.keys())
	_needs.visible = not ores.is_empty()
	if ores == _needed_ores:
		return
	_needed_ores = ores
	for node: Node in _needs.get_children():
		_needs.remove_child(node)
		node.queue_free()
	for ore_type: OreType in ores:
		_needs.add_child(ItemBadge.new(ore_type))


## `text` followed by `of_body`'s tier ("Dust flats · Tier 2").
func _with_tier(text: String, of_body: CelestialBody) -> String:
	return "%s · %s" % [text, tr("Tier %d") % of_body.tier]


static func _show_rows(rows: Array[Control], shown: bool) -> void:
	for row: Control in rows:
		row.visible = shown


func _on_back_pressed() -> void:
	var navigator := station as NavigatorStation
	if navigator and not navigator.step_back():
		navigator.close()


func _on_close_pressed() -> void:
	if station:
		station.close()
