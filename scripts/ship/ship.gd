class_name Ship
extends Node3D
## The ship, in space or landed on its landing gear (its `flight` flies it between the two). Its
## interior is the hub (`Rooms`), on two decks:
## the nose points left, the ramp is at the tail on the right (screen right), so players walk from
## the inside to the right into the mission. Upper deck: cockpit, bridge (the holo table shows the
## mission location), player and crew cabins, mess hall. Lower deck: medical bay, engine room,
## shooting range, armory, upgrade rooms. Lifts (`Lifts`) by the bridge and in the double-height
## cargo bay (by the ramp) join them.
## Ship and planet are one world, without loading screens. The ramp is closed by default; the
## button on the inner wall next to the door lowers it (see `Mission` for the flow). The ship tracks
## who is aboard and holsters their weapons inside, except in the shooting range's weapon zone (a
## barrier in its doorway keeps the shots inside).
## While the `viewer` is aboard, the camera sees inside: on the lower deck, the walls facing the
## camera (`Hull/LowerCut`) and the whole upper deck (`Hull/Upper`, `Rooms/Upper`, the lifts'
## upper gates) only cast shadows; on the upper deck, its walls facing the camera and the roof
## (`Hull/Upper/Cut`) do.
## Inner walls between the camera and the corridor keep a low stub, so the rooms stay outlined.
## Windows in the outer walls look out from every room along them (and in from outside).
## The beacon on the roof shows the mission time from far away: green, amber after half the time,
## red and blinking in the warning time, steady red in the storm, blue once everyone is back and
## grey when the mission is lost. A countdown above the door shows the exact time ("No mission"
## until one is picked at the holo table, "In flight" on the way).
## Returned cargo goes into the hold, shown as big canisters by the back wall. Dead players
## respawn at `Respawn` in the medical bay.

## Emitted when a player steps out of the ship.
signal player_left(player: Player)
## Emitted when a player comes back aboard.
signal player_boarded(player: Player)
## Emitted when the hold's amount of `ore_type` changes (stored cargo, paid upgrades).
signal hold_changed(ore_type: OreType, amount: float)

## What the camera sees of the ship: its outside, or into one of its decks.
enum View { OUTSIDE, LOWER, UPPER }

const GROUP: StringName = &"ships"
## Ship-local height from which the viewer counts as being on the upper deck (its floor is at 7;
## the lower deck's at 2.5, the hull stands on landing gear).
const UPPER_DECK_HEIGHT: float = 6.5
## Window panes: they never cast shadows (light comes in), so they're hidden with their wall.
const GLASS_GROUP: StringName = &"ship_glass"

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

## Seconds the ramp takes to go down or up. TBD (playtest).
@export var ramp_duration: float = 2.0
## Whose view the cutaway follows (the camera's player); without one, the first player aboard.
@export var viewer: Node3D

## The mission whose time the beacon and countdown show; set by the mission.
var mission: Mission
## The beacon's current color.
var beacon_color: Color = COLOR_CALM
## The beacon's current brightness (0 to 1), dims while blinking.
var beacon_brightness: float = 1.0
## What the countdown above the door shows: the time left, or the mission's state (translated).
var countdown_text: String = ""
## Whether the ramp is going down (or is down); it moves there over `ramp_duration`.
var ramp_open: bool = false
## Ore brought back over all runs and not spent yet, in units per ore type. Upgrades are paid from
## it (`pay`).
var hold: Dictionary[OreType, float] = {}
## What has happened in the story so far (e.g. what the crew told), saved with the ship.
var story := Story.new()

var _aboard: Array[Player] = []
## Players in the shooting range's weapon zone.
var _armed: Array[Player] = []
## What the cutaway shows right now.
var _view: View = View.OUTSIDE
var _ramp_angle: float = RAMP_CLOSED_ANGLE
var _lamp_material := StandardMaterial3D.new()
var _column_material := StandardMaterial3D.new()
var _button_material := StandardMaterial3D.new()

@onready var ramp_button: Interactable = $RampButton
@onready var flight: ShipFlight = $Flight
@onready var _ramp: AnimatableBody3D = $Ramp
@onready var _interior: Area3D = $Interior
@onready var _weapon_zone: Area3D = $Rooms/Lower/ShootingRange/WeaponZone
@onready var _boarding: Marker3D = $Boarding
@onready var _respawn: Marker3D = $Respawn
@onready var _hold_rack: CargoRack = $HoldRack
@onready var _floor: Node3D = $Hull/Floor
@onready var _holo_table: HoloTable = $Rooms/Upper/Bridge/HoloTable
@onready var _lower_cut: Node3D = $Hull/LowerCut
@onready var _upper_hull: Node3D = $Hull/Upper
@onready var _upper_cut: Node3D = $Hull/Upper/Cut
@onready var _upper_rooms: Node3D = $Rooms/Upper
@onready var _lifts: Node3D = $Lifts
@onready var _lamp: MeshInstance3D = $Beacon/Lamp
@onready var _column: MeshInstance3D = $Beacon/Column
@onready var _light: OmniLight3D = $Beacon/Light
@onready var _countdown: Label3D = $Countdown
@onready var _button_face: MeshInstance3D = $RampButton/Face


func _ready() -> void:
	add_to_group(GROUP)
	_interior.body_entered.connect(_on_body_entered)
	_interior.body_exited.connect(_on_body_exited)
	_weapon_zone.body_entered.connect(_on_weapon_zone_entered)
	_weapon_zone.body_exited.connect(_on_weapon_zone_exited)
	_ramp_angle = RAMP_OPEN_ANGLE if ramp_open else RAMP_CLOSED_ANGLE
	_ramp.rotation.z = _ramp_angle
	_lamp_material.emission_enabled = true
	_lamp_material.emission_energy_multiplier = 3.0
	_lamp.material_override = _lamp_material
	_column_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_column_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_column_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_column.material_override = _column_material
	_button_material.emission_enabled = true
	_button_face.material_override = _button_material
	_update_display()


func _physics_process(delta: float) -> void:
	var target: float = RAMP_OPEN_ANGLE if ramp_open else RAMP_CLOSED_ANGLE
	var speed: float = (RAMP_CLOSED_ANGLE - RAMP_OPEN_ANGLE) / ramp_duration
	if _ramp_angle != target:
		_ramp_angle = move_toward(_ramp_angle, target, speed * delta)
		_ramp.rotation.z = _ramp_angle
	_update_view()


func _process(_delta: float) -> void:
	_update_display()
	_update_view()


func is_aboard(player: Player) -> bool:
	return player in _aboard


## Whether the ramp is all the way down.
func is_ramp_down() -> bool:
	return _ramp_angle == RAMP_OPEN_ANGLE


## Whether the ramp is all the way up, closing the door.
func is_ramp_up() -> bool:
	return _ramp_angle == RAMP_CLOSED_ANGLE


## Where players board: the door at the top of the ramp.
func get_boarding_position() -> Vector3:
	return _boarding.global_position


## Where dead players come back to life.
func get_respawn_position() -> Vector3:
	return _respawn.global_position


## Whether the hold has at least `cost` (units per ore type).
func can_pay(cost: Dictionary[OreType, int]) -> bool:
	for ore_type: OreType in cost:
		var stored: float = hold.get(ore_type, 0.0)
		if stored < cost[ore_type]:
			return false
	return true


## Takes `cost` (units per ore type) out of the hold if it's there. Returns whether it paid.
func pay(cost: Dictionary[OreType, int]) -> bool:
	if not can_pay(cost):
		return false
	for ore_type: OreType in cost:
		var stored: float = hold[ore_type]
		_set_hold(ore_type, stored - cost[ore_type])
	return true


## Adds `amount` units of `ore_type` to the hold.
func add_to_hold(ore_type: OreType, amount: float) -> void:
	var stored: float = hold.get(ore_type, 0.0)
	_set_hold(ore_type, stored + amount)


## Moves everything `player` carries into the hold.
func store_cargo(player: Player) -> void:
	var cargo: Dictionary[OreType, float] = player.take_cargo()
	for ore_type: OreType in cargo:
		add_to_hold(ore_type, cargo[ore_type])


## Shows `location` and where the ship stands in it (its floor) on the holo table; null clears it.
## The location doesn't need to be in the tree: locations stand where the ship stands.
func show_preview(location: Node3D) -> void:
	_holo_table.show_location(location, [_floor], global_transform)


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


func _set_hold(ore_type: OreType, amount: float) -> void:
	hold[ore_type] = amount
	_hold_rack.show_cargo(ore_type, amount)
	hold_changed.emit(ore_type, amount)


func _update_display() -> void:
	beacon_brightness = 1.0
	if not mission:
		beacon_color = COLOR_CALM
		countdown_text = ""
	elif flight.is_flying():
		beacon_color = COLOR_CALM
		countdown_text = tr("In flight")
	elif mission.state == Mission.State.RETURNED:
		beacon_color = COLOR_RETURNED
		countdown_text = tr("All aboard")
	elif mission.state == Mission.State.LOST:
		beacon_color = COLOR_LOST
		countdown_text = tr("Lost")
	elif mission.state == Mission.State.STORM:
		beacon_color = COLOR_WARNING
		countdown_text = tr("Storm")
	elif not mission.brief:
		beacon_color = COLOR_CALM
		countdown_text = tr("No mission")
	else:
		var time_left: float = mission.time_left
		var seconds: int = ceili(time_left)
		countdown_text = "%d:%02d" % [floori(seconds / 60.0), seconds % 60]
		if time_left <= mission.settings.warning_time:
			beacon_color = COLOR_WARNING
			# Tied to the timer, so the blinking stays in step with the countdown.
			beacon_brightness = 0.25 + 0.75 * absf(cos(time_left * PI * WARNING_BLINK_RATE))
		elif time_left <= mission.duration() * 0.5:
			beacon_color = COLOR_HALF
		else:
			beacon_color = COLOR_CALM

	_lamp_material.albedo_color = beacon_color
	_lamp_material.emission = beacon_color * beacon_brightness
	_column_material.albedo_color = Color(beacon_color, 0.35 * beacon_brightness)
	_light.light_color = beacon_color
	_light.light_energy = 2.0 * beacon_brightness
	_countdown.text = countdown_text
	_countdown.modulate = beacon_color

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


## Weapons work outside the ship and in the shooting range; aboard, reloads come from the ship's
## stock for free.
func _update_weapon(player: Player) -> void:
	player.weapon_allowed = player not in _aboard or player in _armed
	player.ammo_free = player in _aboard


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
	if not who and not _aboard.is_empty():
		who = _aboard[0]
	if not who or who not in _aboard:
		return View.OUTSIDE
	if to_local(who.global_position).y >= UPPER_DECK_HEIGHT:
		return View.UPPER
	return View.LOWER


func _apply_view() -> void:
	_show(_lower_cut, _view != View.LOWER)
	_show(_upper_hull, _view != View.LOWER)
	_show(_upper_rooms, _view != View.LOWER)
	for lift: Node in _lifts.get_children():
		_show(lift.get_node(^"UpperGate"), _view != View.LOWER)
	_show(_upper_cut, _view == View.OUTSIDE)


## Shows `root`'s geometry, or only lets it cast shadows; its lights, holograms and windows turn
## off.
static func _show(root: Node, shown: bool) -> void:
	for child: Node in root.get_children():
		if child is Light3D or child is HoloTable or child.is_in_group(GLASS_GROUP):
			(child as Node3D).visible = shown
			continue
		if child is GeometryInstance3D:
			(child as GeometryInstance3D).cast_shadow = (
				GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				if shown
				else GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			)
		_show(child, shown)


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
