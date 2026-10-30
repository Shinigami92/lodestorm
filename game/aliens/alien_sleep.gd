class_name AlienSleep
extends Node
## An alien asleep where it lies (the Ravager in a quest's lair, see `ApexLair`; a child of its
## `Alien`): it stands still, its body low and its eyes and glands dark (`AlienStatus.asleep`),
## until a player outside the ship comes within its `AlienStrain.detection_range` or it's hurt.
## Then it wakes for good and rises. Values TBD (playtest).

## How often it looks for players coming close, in s.
const CHECK: float = 0.25
## The glowing parts darkened while it sleeps (their color; the alien dims their glow itself).
const GLOWING: Array[String] = ["Eyes", "Glands"]

var _alien: Alien
var _check_left: float = 0.0
## The glowing parts' materials and their colors awake, once darkened.
var _dark: Array[BaseMaterial3D] = []
var _colors: Array[Color] = []


func _ready() -> void:
	_alien = get_parent() as Alien
	_alien.status.asleep = true
	GameEvents.bus.alien_damaged.connect(_on_alien_damaged)


func _process(delta: float) -> void:
	if _dark.is_empty():
		_darken()
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = CHECK
	for node: Node in get_tree().get_nodes_in_group(Player.GROUP):
		var player := node as Player
		if (
			player
			and Alien.is_prey(get_tree(), player)
			and _alien.horizontal_distance(player) <= _alien.strain.detection_range
		):
			wake()
			return


## Wakes it: it hunts like any other from now on.
func wake() -> void:
	_alien.status.asleep = false
	for i: int in _dark.size():
		_dark[i].albedo_color = _colors[i]
	queue_free()


## Darkens its glowing parts' color (their own materials, set up once the alien is ready).
func _darken() -> void:
	for part: String in GLOWING:
		var mesh := _alien.find_child(part, true, false) as GeometryInstance3D
		var glow := mesh.material_override as BaseMaterial3D if mesh else null
		if glow:
			_dark.append(glow)
			_colors.append(glow.albedo_color)
			glow.albedo_color = glow.albedo_color.darkened(1.0 - AlienStatus.SLEEP_GLOW)


func _on_alien_damaged(_player: Player, _with: WeaponType, alien: Alien, _amount: float) -> void:
	if alien == _alien:
		wake()
