class_name MedBedStation
extends Station
## A med bed in the medical bay (see docs/design/death-and-persistence.md): health carries over
## between runs, and the player using it lies down on it (`Lie`) and heals to full, for free. The
## bed is its part; its card (`MedBedCard`) shows the health filling up and "Get up". Any player can
## use any bed, one player per bed.

## Seconds a player with no health left would take to heal to full; less is missing, less it takes.
## TBD (playtest).
@export var heal_time: float = 3.0
## The bed it is (outlined while selected).
@export var bed: Node3D

@onready var _part: StationPart = $Part
## Where the body lies: its Y towards the head, its -Z where the face looks.
@onready var _lie: Marker3D = $Lie


func _ready() -> void:
	super()
	_part.outline = bed
	closed.connect(_on_closed)


func _process(delta: float) -> void:
	super(delta)
	if not user:
		return
	var maximum: float = user.max_health()
	if user.health < maximum:
		user.heal(maximum / heal_time * delta)
	refresh()


## Whether the player using it is still healing.
func is_healing() -> bool:
	return user != null and user.health < user.max_health()


func _opened() -> void:
	super()
	user.lie_on(_lie)


func _on_closed(player: Player) -> void:
	if is_instance_valid(player):
		player.lie_on(null)
