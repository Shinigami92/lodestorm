class_name Ship
extends Node3D
## The ship, in space, landed on its landing gear or docked at a station (its `flight` flies it
## between them). Its
## interior is the hub (`Rooms`), on two decks:
## the nose points left, the ramp is at the tail on the right (screen right), so players walk from
## the inside to the right into the mission. Upper deck: cockpit, bridge (the holo table shows the
## mission location), player and crew cabins, mess hall. Lower deck: medical bay, engine room,
## shooting range, armory, upgrade rooms. Lifts (`Lifts`) by the bridge and in the double-height
## cargo bay (by the ramp) join them.
## Ship and planet are one world, without loading screens. The ramp is closed by default; the
## button on the inner wall next to the door lowers it (see `Mission` for the flow); a hurt player
## standing at it is told once where to heal (`ramp_hint`); the cargo hatch outside beside it
## (`CargoHatch`) comes down with it. The ship tracks who is aboard and
## holsters their weapons inside, except in the shooting range's weapon zone (a barrier in its
## doorway keeps the shots inside), and outside too while docked at a station.
## While the `viewer` is aboard (and `show_outside` is off), the camera sees inside: on the lower
## deck, the walls facing the camera (`Hull/LowerCut`) and the whole upper deck (`Hull/Upper`,
## `Rooms/Upper`, the lifts' upper gates) only cast shadows; on the upper deck, its walls facing
## the camera and the roof (`Hull/Upper/Cut`) do. What draws over everything (`OVERLAY_GROUP`)
## only shows while the camera looks into the upper deck.
## Inner walls between the camera and the corridor keep a low stub, so the rooms stay outlined.
## Windows in the outer walls look out from every room along them (and in from outside).
## A countdown above the door (running outwards from it, clear of the silos) shows the mission time
## ("No mission" until one is picked at the holo table, "In flight" on the way, "Docked" at a
## station) in its status color:
## green, amber after half the time, red in the
## warning time (the ship pointer outside blinks then), red in the storm, blue once everyone is back
## and grey when the mission is lost.
## Returned cargo goes into every player's own hold (`PlayerHold`, shown by the silos in the cargo
## bay), after the heat shield's plate took what it still needs while it's the ship's project
## (`store_haul`); the refinery at the bay's far end turns it into alloys (`Refinery`). Dead
## players respawn at
## `Respawn` in the medical bay. The crew find their way aboard over its `navigation`.

## Emitted when a player steps out of the ship.
signal player_left(player: Player)
## Emitted when a player comes back aboard.
signal player_boarded(player: Player)

## What the camera sees of the ship: its outside, or into one of its decks.
enum View { OUTSIDE, LOWER, UPPER }

const GROUP: StringName = &"ships"
## Ship-local height from which the viewer counts as being on the upper deck (its floor is at 7;
## the lower deck's at 2.5, the hull stands on landing gear).
const UPPER_DECK_HEIGHT: float = 6.5
## Upper-deck nodes drawn over everything (the navigator's name plates): shown only while the
## camera looks into the upper deck, so they don't show through the roof.
const OVERLAY_GROUP: StringName = &"ship_overlays"

const COLOR_CALM := Color(0.3, 1.0, 0.45)
const COLOR_HALF := Color(1.0, 0.7, 0.15)
const COLOR_WARNING := Color(1.0, 0.2, 0.15)
const COLOR_RETURNED := Color(0.35, 0.6, 1.0)
const COLOR_LOST := Color(0.45, 0.45, 0.5)
## Ramp button: lowers the ramp / raises it again / can't be used right now.
const COLOR_BUTTON_LOWER := Color(0.3, 1.0, 0.45)
const COLOR_BUTTON_RAISE := Color(1.0, 0.7, 0.15)
const COLOR_BUTTON_DISABLED := Color(0.25, 0.25, 0.25)
## Blinks per second in the warning time.
const WARNING_BLINK_RATE: float = 2.0
## Ramp angle around its hinge at the door: standing up (closing the door) and lying on the ground.
const RAMP_CLOSED_ANGLE: float = PI * 0.5
## asin(2.5 / 5): the 5 m ramp reaches 2.5 m down from the door to the ground (30°).
const RAMP_OPEN_ANGLE: float = -0.523599
## The ramp moving (as long as `ramp_duration`): latches, hydraulics, the clunk at the end.
const RAMP_SOUND: Sound = preload("res://assets/audio/sfx/mission/ramp.tres")
const RAMP_HINT_SCENE: PackedScene = preload("res://game/ship/ramp_hint.tscn")

## Seconds the ramp takes to go down or up. TBD (playtest).
@export var ramp_duration: float = 2.0
## Whose view the cutaway follows (the camera's player); without one, the first player aboard.
@export var viewer: Node3D

## The mission whose time the countdown shows; set by the mission.
var mission: Mission
## Where the ship goes (the mission it flies to or stands at); set by the voyage.
var voyage: Voyage
## The mission time's current color (countdown, ship pointer).
var status_color: Color = COLOR_CALM
## The status color's current brightness (0 to 1), dims while blinking.
var status_brightness: float = 1.0
## What the countdown above the door shows: the time left, or the mission's state (translated).
var countdown_text: String = ""
## Hides the countdown (it draws over everything): e.g. while the hold's silos by the ramp are
## looked at up close.
var countdown_hidden: bool = false
## Shows the closed hull whoever is aboard (e.g. the title view).
var show_outside: bool = false
## Whether the ramp is going down (or is down); it moves there over `ramp_duration`.
var ramp_open: bool = false
## What has happened in the story so far (e.g. what the crew told), saved with the ship.
var story := Story.new()
## The heat shield around the drive core: how far inwards the ship can fly, saved with the ship.
var heat_shield := HeatShield.new()
## How many of the refinery's furnaces it has, saved with the ship.
var furnaces := Furnaces.new()
## The crew's reactions to what happens, and their radio calls, saved with the ship.
var reactions := CrewReactions.new()
## Lets the levels and skill ranks under way take effect once done.
var progress_clock: ProgressClock
## Where the crew can walk aboard.
var navigation: DeckNavigation
## Says once where to heal when a hurt player stands at the ramp button.
var ramp_hint: RampHint

var _aboard: Array[Player] = []
## Players in the shooting range's weapon zone.
var _armed: Array[Player] = []
## What the cutaway shows right now.
var _view: View = View.OUTSIDE
var _ramp_angle: float = RAMP_CLOSED_ANGLE
## Where the ramp last set off to (it sounds each time it sets off).
var _ramp_heading: float = NAN
var _button_material := StandardMaterial3D.new()

@onready var ramp_button: Interactable = $RampButton
## Its rooms' areas (from the hull's layout), for what people say where they stand.
@onready var room_plan: RoomPlan = $Hull/RoomPlan
@onready var flight: ShipFlight = $Flight
@onready var _ramp: AnimatableBody3D = $Ramp
@onready var _interior: Area3D = $Interior
@onready var _weapon_zone: Area3D = $Rooms/Lower/ShootingRange/WeaponZone
@onready var _boarding: Marker3D = $Boarding
@onready var _respawn: Marker3D = $Respawn
@onready var _floor: Node3D = $Hull/Floor
@onready var _holo_table: HoloTable = $Rooms/Upper/Bridge/HoloTable
@onready var _lower_cut: Node3D = $Hull/LowerCut
@onready var _upper_hull: Node3D = $Hull/Upper
@onready var _upper_cut: Node3D = $Hull/Upper/Cut
@onready var _upper_rooms: Node3D = $Rooms/Upper
@onready var _exterior: ShipExterior = $Exterior
@onready var _lifts: Node3D = $Lifts
@onready var _countdown: Label3D = $Countdown
@onready var _button_face: MeshInstance3D = $RampButton/Face


func _ready() -> void:
	add_to_group(GROUP)
	_interior.body_entered.connect(_on_body_entered)
	_interior.body_exited.connect(_on_body_exited)
	_weapon_zone.body_entered.connect(_on_weapon_zone_entered)
	_weapon_zone.body_exited.connect(_on_weapon_zone_exited)
	flight.phase_changed.connect(_update_weapons.unbind(1))
	_ramp_angle = RAMP_OPEN_ANGLE if ramp_open else RAMP_CLOSED_ANGLE
	_ramp.rotation.z = _ramp_angle
	_button_material.emission_enabled = true
	_button_face.material_override = _button_material
	ramp_hint = RAMP_HINT_SCENE.instantiate() as RampHint
	ramp_hint.ship = self
	ramp_hint.position = _button_face.position
	ramp_button.add_child(ramp_hint)
	_update_display()
	_apply_view()
	progress_clock = ProgressClock.new()
	progress_clock.name = "ProgressClock"
	add_child(progress_clock)
	reactions.name = "Reactions"
	reactions.ship = self
	add_child(reactions)
	navigation = DeckNavigation.new()
	navigation.name = "Navigation"
	add_child(navigation)


func _physics_process(delta: float) -> void:
	var target: float = RAMP_OPEN_ANGLE if ramp_open else RAMP_CLOSED_ANGLE
	var speed: float = (RAMP_CLOSED_ANGLE - RAMP_OPEN_ANGLE) / ramp_duration
	if _ramp_angle != target:
		if target != _ramp_heading and not is_nan(_ramp_heading):
			Sfx.play_at(RAMP_SOUND, _ramp.global_position)
		_ramp_heading = target
		_ramp_angle = move_toward(_ramp_angle, target, speed * delta)
		_ramp.rotation.z = _ramp_angle
	elif is_nan(_ramp_heading):
		_ramp_heading = target
	_update_view()


func _process(_delta: float) -> void:
	_update_display()
	_update_view()


func is_aboard(player: Player) -> bool:
	return player in _aboard


## Whether every player in the session is aboard (e.g. before undocking from a station).
func everyone_aboard() -> bool:
	for player: Player in get_tree().get_nodes_in_group(Player.GROUP):
		if player not in _aboard:
			return false
	return true


## Whether the ramp is all the way down.
func is_ramp_down() -> bool:
	return _ramp_angle == RAMP_OPEN_ANGLE


## Whether the ramp is all the way up, closing the door.
func is_ramp_up() -> bool:
	return _ramp_angle == RAMP_CLOSED_ANGLE


## How far the ramp is down: 0 up (closing the door), 1 lying on the ground.
func ramp_lowered() -> float:
	return (RAMP_CLOSED_ANGLE - _ramp_angle) / (RAMP_CLOSED_ANGLE - RAMP_OPEN_ANGLE)


## Where players board: the door at the top of the ramp.
func get_boarding_position() -> Vector3:
	return _boarding.global_position


## Where dead players come back to life.
func get_respawn_position() -> Vector3:
	return _respawn.global_position


## Stores a run's `haul` (units per ore type, everything brought aboard): while the heat shield's
## next plate is the ship's project, it takes what it still needs first; what's left goes whole into
## the hold of every player in `players` (the session), nothing split. Returns what the plate took.
func store_haul(
	haul: Dictionary[OreType, float], players: Array[Player]
) -> Dictionary[OreType, float]:
	var taken: Dictionary[OreType, float] = {}
	if heat_shield.project:
		taken = heat_shield.take_from(haul)
	for player: Player in players:
		for ore_type: OreType in haul:
			var took: float = taken.get(ore_type, 0.0)
			var left: float = haul[ore_type] - took
			if left > 0.0:
				player.hold.add(ore_type, left)
			elif haul[ore_type] > 0.0:
				# Brought aboard, even if the plate took all of it.
				player.hold.mark_found(ore_type)
	return taken


## Pays what the heat shield's next plate still needs from `hold` (the host's), as far as it has
## it. Returns whether it paid anything.
func pay_shield(hold: PlayerHold) -> bool:
	var available: Dictionary[OreType, float] = {}
	for ore_type: OreType in heat_shield.missing():
		available[ore_type] = maxf(hold.amount(ore_type), 0.0)
	var taken: Dictionary[OreType, float] = heat_shield.take_from(available)
	for ore_type: OreType in taken:
		hold.take(ore_type, taken[ore_type])
	return not taken.is_empty()


## Shows `location` and where the ship stands in it (its floor) on the holo table; null clears it.
## The location doesn't need to be in the tree: locations stand where the ship stands.
func show_preview(location: Node3D) -> void:
	_holo_table.show_location(location, [_floor], global_transform)


## Whose things the ship's stations show while nobody uses them (the silos, the furnaces, the
## ingot rack): the `viewer`, else the first local player.
func get_viewing_player() -> Player:
	var player := viewer as Player
	return player if player else Player.first_local(get_tree())


## The ship closest to `from` (horizontally), or null.
static func nearest(tree: SceneTree, from: Vector3) -> Ship:
	var nearest_ship: Ship = null
	var nearest_distance: float = INF
	for ship: Ship in tree.get_nodes_in_group(GROUP):
		var offset: Vector3 = ship.global_position - from
		var distance: float = Vector2(offset.x, offset.z).length()
		if distance < nearest_distance:
			nearest_ship = ship
			nearest_distance = distance
	return nearest_ship


func _update_display() -> void:
	status_brightness = 1.0
	if not mission:
		status_color = COLOR_CALM
		countdown_text = ""
	elif flight.is_flying():
		status_color = COLOR_CALM
		countdown_text = tr("In flight")
	elif flight.is_docked():
		status_color = COLOR_CALM
		countdown_text = tr("Docked")
	elif mission.state == Mission.State.RETURNED:
		status_color = COLOR_RETURNED
		countdown_text = tr("All aboard")
	elif mission.state == Mission.State.LOST:
		status_color = COLOR_LOST
		countdown_text = tr("Lost")
	elif mission.state == Mission.State.STORM:
		status_color = COLOR_WARNING
		countdown_text = tr("Storm")
	elif not voyage or not voyage.brief:
		status_color = COLOR_CALM
		countdown_text = tr("No mission")
	else:
		var time_left: float = mission.time_left
		var seconds: int = ceili(time_left)
		countdown_text = "%d:%02d" % [floori(seconds / 60.0), seconds % 60]
		if time_left <= mission.warning_time():
			status_color = COLOR_WARNING
			# Tied to the timer, so the blinking stays in step with the countdown.
			status_brightness = 0.25 + 0.75 * absf(cos(time_left * PI * WARNING_BLINK_RATE))
		elif time_left <= mission.duration() * 0.5:
			status_color = COLOR_HALF
		else:
			status_color = COLOR_CALM

	_countdown.text = countdown_text
	_countdown.modulate = status_color
	_countdown.visible = not countdown_hidden

	var button_color: Color = COLOR_BUTTON_DISABLED
	if ramp_button.enabled:
		button_color = COLOR_BUTTON_RAISE if ramp_open else COLOR_BUTTON_LOWER
	_button_material.albedo_color = button_color
	_button_material.emission = button_color


func _update_view() -> void:
	var view: View = _current_view()
	if view != _view:
		_view = view
		_apply_view()


## Weapons work outside the ship (not at a station) and in the shooting range; aboard, reloads
## come from the ship's stock for free.
func _update_weapon(player: Player) -> void:
	var outside: bool = player not in _aboard and not flight.is_docked()
	player.weapon_allowed = outside or player in _armed
	player.ammo_free = player in _aboard


func _update_weapons() -> void:
	for player: Player in get_tree().get_nodes_in_group(Player.GROUP):
		_update_weapon(player)


func _on_weapon_zone_entered(body: Node3D) -> void:
	var player := body as Player
	if player and player not in _armed:
		_armed.append(player)
		_update_weapon(player)


func _on_weapon_zone_exited(body: Node3D) -> void:
	var player := body as Player
	if player:
		_armed.erase(player)
		_update_weapon(player)


## Where the viewer is: outside, or on which deck.
func _current_view() -> View:
	var who: Node3D = viewer
	if show_outside:
		return View.OUTSIDE
	if not who and not _aboard.is_empty():
		who = _aboard[0]
	if not who or who not in _aboard:
		return View.OUTSIDE
	if to_local(who.global_position).y >= UPPER_DECK_HEIGHT:
		return View.UPPER
	return View.LOWER


func _apply_view() -> void:
	CutAway.show(_lower_cut, _view != View.LOWER)
	CutAway.show(_upper_hull, _view != View.LOWER)
	CutAway.show(_upper_rooms, _view != View.LOWER)
	for lift: Node in _lifts.get_children():
		CutAway.show(lift.get_node(^"UpperGate"), _view != View.LOWER)
	CutAway.show(_upper_cut, _view == View.OUTSIDE)
	CutAway.show(_exterior, _view == View.OUTSIDE)
	for overlay: Node in get_tree().get_nodes_in_group(OVERLAY_GROUP):
		if is_ancestor_of(overlay):
			(overlay as Node3D).visible = _view == View.UPPER


func _on_body_entered(body: Node3D) -> void:
	var player := body as Player
	if player and player not in _aboard:
		_aboard.append(player)
		_update_weapon(player)
		_update_view()
		player_boarded.emit(player)


func _on_body_exited(body: Node3D) -> void:
	var player := body as Player
	if player and player in _aboard:
		_aboard.erase(player)
		_update_weapon(player)
		_update_view()
		player_left.emit(player)
