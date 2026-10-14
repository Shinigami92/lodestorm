class_name NavigatorCard
extends StationCard
## The holo card of the navigator (`NavigatorStation`): what's selected and what can be done with
## it. The star: its name; a body: its kind ("Zoom in"); a region: its biome, danger, timer and
## ores ("Zoom in", "Set as destination"); the landing site: the mission's location name and where
## things stand (destination set, scanning, in flight, landed).

const DANGER_COLORS: Array[Color] = [
	Color(0.45, 0.95, 0.55), Color(1.0, 0.75, 0.3), Color(1.0, 0.4, 0.35)
]
const ORE_CHIP_SIZE := Vector2(22.0, 22.0)
const STATUS_COLOR := Color(1.0, 0.75, 0.3)

## What's shown (a body or a region), or null.
var item: Resource

## The ores the chips show.
var _shown_ores: Array[OreType] = []

@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _info: GridContainer = %Info
@onready var _danger: Label = %Danger
@onready var _timer: Label = %Timer
@onready var _ores: HBoxContainer = %Ores
@onready var _status: Label = %Status
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
	var mission: Mission = navigator.mission
	var shown_body := item as CelestialBody
	var shown_region := item as Region
	var star := item as StarSystem
	var offer: MissionBrief = navigator.get_offer(item)
	_status.add_theme_color_override(&"font_color", STATUS_COLOR)
	_choose.visible = shown_region != null
	if star:
		_title.text = tr(star.display_name)
		_subtitle.text = tr("Star")
		_info.visible = false
		_primary.visible = false
		_status.text = ""
	elif shown_body:
		_title.text = tr(shown_body.display_name)
		_subtitle.text = shown_body.kind_name()
		_info.visible = false
		_primary.visible = true
		_primary.text = tr("Zoom in")
		_primary.disabled = not shown_body.is_reachable()
		if shown_body.is_reachable():
			_status.text = ""
		elif shown_body.kind == CelestialBody.Kind.STATION:
			_status.text = tr("No docking yet.")
		else:
			_status.text = tr("Locked")
	elif shown_region:
		var at_landing_site: bool = navigator.level == NavigatorStation.Level.REGION
		_title.text = (
			offer.location_name() if offer and at_landing_site else tr(shown_region.display_name)
		)
		_subtitle.text = tr(shown_region.biome.display_name) if shown_region.biome else ""
		_info.visible = true
		_danger.text = MissionBrief.for_region(shown_region, 1).difficulty_name()
		_danger.add_theme_color_override(&"font_color", DANGER_COLORS[shown_region.danger])
		var minutes: float = (mission.settings.duration if mission else 900.0) * shown_region.length
		_timer.text = tr("%d min") % roundi(minutes / 60.0)
		var ores: Array[OreType] = []
		if shown_region.biome:
			ores = shown_region.biome.ores
		_show_ores(ores)
		_primary.visible = not at_landing_site
		_primary.text = tr("Zoom in")
		_primary.disabled = not shown_region.unlocked
		_choose.text = tr("Set as destination")
		var chosen: bool = offer != null and mission != null and offer == mission.destination
		_choose.disabled = (
			not shown_region.unlocked or not mission or not mission.can_select() or chosen
		)
		_status.text = _region_status(navigator, shown_region, offer)
	_status.visible = _status.text != ""
	_back.visible = navigator.level != NavigatorStation.Level.SYSTEM


## `interact`: zooms in, or at a landing site chooses it as the destination.
func press_primary() -> bool:
	var navigator := station as NavigatorStation
	return navigator != null and navigator.activate()


## Where things stand for `shown_region` (its mission `offer`).
func _region_status(
	navigator: NavigatorStation, shown_region: Region, offer: MissionBrief
) -> String:
	var mission: Mission = navigator.mission
	var text: String = ""
	if not shown_region.unlocked:
		text = tr("Locked")
	elif not mission or not offer:
		text = ""
	elif mission.flight.is_flying():
		text = tr("In flight: gear up and head for the ramp.")
	elif not mission.can_select():
		text = tr("Locked until everyone is back aboard.")
	elif offer == mission.brief:
		text = tr("Landed: lower the ramp in the cargo bay.")
	elif offer != mission.destination:
		text = ""
	elif mission.is_preparing(offer):
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


func _show_ores(ores: Array[OreType]) -> void:
	if ores == _shown_ores:
		return
	_shown_ores = ores.duplicate()
	for node: Node in _ores.get_children():
		_ores.remove_child(node)
		node.queue_free()
	for ore_type: OreType in ores:
		var chip := ColorRect.new()
		chip.color = ore_type.color
		chip.custom_minimum_size = ORE_CHIP_SIZE
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_ores.add_child(chip)


func _on_back_pressed() -> void:
	var navigator := station as NavigatorStation
	if navigator and not navigator.step_back():
		navigator.close()


func _on_close_pressed() -> void:
	if station:
		station.close()
