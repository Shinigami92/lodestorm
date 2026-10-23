class_name FlightCard
extends StationCard
## The holo card of the flight console (`FlightStation`): the destination picked at the navigator
## (its location, body, danger and timer), where things stand, and "Set course".

const STATUS_COLOR := Color(1.0, 0.75, 0.3)

## The ores the badges show.
var _shown_ores: Array[OreType] = []

@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _info: GridContainer = %Info
@onready var _danger: Label = %Danger
@onready var _timer: Label = %Timer
@onready var _ores: HFlowContainer = %Ores
@onready var _status: Label = %Status
@onready var _launch: Button = %Launch
@onready var _close: Button = %Close


func _ready() -> void:
	_launch.pressed.connect(press_primary)
	_close.pressed.connect(_on_close_pressed)


func show_part(part: StationPart) -> void:
	var console := station as FlightStation
	visible = part != null and console != null
	if not visible:
		return
	var voyage: Voyage = console.voyage
	var destination: MissionBrief = voyage.destination if voyage else null
	if not destination and voyage:
		destination = voyage.brief
	if destination:
		_title.text = destination.location_name()
		var system: StarSystem = voyage.settings.system
		var body: CelestialBody = (
			system.body_of(destination.region) if system and destination.region else null
		)
		_subtitle.text = tr(body.display_name) if body else ""
		_info.visible = true
		_danger.text = destination.difficulty_name()
		_danger.add_theme_color_override(
			&"font_color", NavigatorCard.DANGER_COLORS[destination.difficulty]
		)
		_timer.text = (
			tr("%d min") % roundi(voyage.mission.settings.duration * destination.length / 60.0)
		)
		_show_ores(destination.found_ores())
	else:
		_title.text = tr("No destination")
		_subtitle.text = ""
		_info.visible = false
	_status.text = _status_text(voyage)
	_status.add_theme_color_override(&"font_color", STATUS_COLOR)
	_launch.disabled = not console.can_launch()


## The destination's ores as badges with their names (from common to rare).
func _show_ores(ores: Array[OreType]) -> void:
	if ores == _shown_ores:
		return
	_shown_ores = ores.duplicate()
	for node: Node in _ores.get_children():
		_ores.remove_child(node)
		node.queue_free()
	for ore_type: OreType in ores:
		_ores.add_child(ItemBadge.new(ore_type))


func press_primary() -> bool:
	var console := station as FlightStation
	return console != null and console.launch()


func _status_text(voyage: Voyage) -> String:
	var text: String = ""
	if not voyage:
		text = ""
	elif voyage.flight.is_flying():
		text = tr("In flight: gear up and head for the ramp.")
	elif not voyage.can_select():
		text = tr("Locked until everyone is back aboard.")
	elif not voyage.destination:
		text = tr("Pick a destination at the navigator on the bridge.")
	elif voyage.is_preparing(voyage.destination):
		text = tr("Scanning the location...")
	elif voyage.can_confirm():
		text = tr("Set course to fly there.")
	else:
		text = tr("Landed: lower the ramp in the cargo bay.")
	return text


func _on_close_pressed() -> void:
	if station:
		station.close()
