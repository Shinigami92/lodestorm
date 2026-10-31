class_name FlightCard
extends StationCard
## The holo card of the flight console (`FlightStation`): the destination picked at the navigator
## (its location, body, danger and timer; a station's name and kind), where things stand, and "Set
## course".

@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _info: GridContainer = %Info
@onready var _danger: Label = %Danger
@onready var _timer: Label = %Timer
@onready var _ores: BadgeRow = %Ores
@onready var _status: Label = %Status
@onready var _launch: Button = %Launch


func _ready() -> void:
	_launch.pressed.connect(press_primary)


func show_part(part: StationPart) -> void:
	var console := station as FlightStation
	visible = part != null and console != null
	if not visible:
		return
	var voyage: Voyage = console.voyage
	var destination: MissionBrief = voyage.destination if voyage else null
	if not destination and voyage:
		destination = voyage.brief
	if destination and destination.station:
		_title.text = destination.location_name()
		_subtitle.text = destination.station.kind_name()
		_info.visible = false
	elif destination:
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
		_ores.show_items(destination.found_ores())
	else:
		_title.text = tr("No destination")
		_subtitle.text = ""
		_info.visible = false
	_status.text = _status_text(voyage)
	_launch.disabled = not console.can_launch()


func press_primary() -> bool:
	var console := station as FlightStation
	return console != null and console.launch()


func _status_text(voyage: Voyage) -> String:
	var text: String = ""
	var boarding: Array[Npc] = NpcBoarding.walking(get_tree())
	if not voyage:
		text = ""
	elif voyage.flight.is_flying():
		text = tr("In flight: gear up and head for the ramp.")
	elif not voyage.can_select():
		text = _locked_text()
	elif not voyage.destination:
		text = tr("Pick a destination at the navigator on the bridge.")
	elif voyage.is_preparing(voyage.destination):
		text = tr("Scanning the location...")
	elif not boarding.is_empty():
		text = tr("Wait until %s is aboard.") % boarding[0].profile.display_name
	elif voyage.can_confirm():
		text = (
			tr("Set course to dock there.")
			if voyage.destination.station
			else tr("Set course to fly there.")
		)
	elif voyage.is_docked() and voyage.destination != voyage.brief:
		text = tr("Wait until everyone is back aboard.")
	elif voyage.is_docked():
		text = tr("Docked: lower the ramp in the cargo bay.")
	else:
		text = tr("Landed: lower the ramp in the cargo bay.")
	return text
