class_name Miner
extends StaticBody3D
## Mines its ore node's ore over time and stops when full. The fill level shows in the world:
## the glass column fills up in the ore color and the lamp on top lights up when full.
## A hose connects to the nearest player within `settings.hose_range` and moves the ore to them.
## Aliens can attack it: the frame flashes white when hit and turns rusty with damage. At zero
## health it breaks down: it stops mining and the hose disconnects, so its ore can't be taken out
## (it keeps it). The frame blinks red until a player standing within `settings.repair_range` has
## repaired it completely. Players repair damaged miners that still work too.
##
## The look lives in the `Model` child, so a modeled asset can replace the greybox. The model
## provides these parts by name: `Fill` (scaled along Y from 0 to 1 with the fill level; it and its
## meshes get the ore material), `FullLamp`, `HoseOutlet`, and meshes named `Frame*` (the
## structure that shows damage). Damage is drawn as an overlay on the frame, so it works on top of
## any material the model brings. Parts are looked up among all descendants (also inside an
## instanced model scene).

## Emitted once each time the miner becomes full.
signal filled
## Emitted when health reaches zero and the miner stops mining and transferring.
signal broke
## Emitted when a broken miner is repaired completely and mines again.
signal repaired

const GROUP: StringName = &"miners"

const COLOR_RUST := Color(0.45, 0.17, 0.06)
const COLOR_FLASH := Color(1.0, 1.0, 1.0)
const COLOR_ALARM := Color(1.0, 0.15, 0.1)
## How much the rust covers the frame at zero health (0–1).
const RUST_MAX: float = 0.75
## How much a hit flash or the alarm blink covers the frame (0–1).
const SIGNAL_COVER: float = 0.7
## Seconds a hit flash lasts.
const FLASH_DURATION: float = 0.1
## Blinks per second while broken.
const BLINK_RATE: float = 2.0

@export var settings: MinerSettings

## Set by the ore node before the miner enters the tree.
var ore_type: OreType
## Units currently held, between 0 and `settings.capacity`.
var amount: float = 0.0
## The player the hose is connected to, or null.
var hose_target: Player
## Current health, from 0 to `settings.max_health`.
var health: float
## A broken miner doesn't mine and its hose doesn't connect until it's repaired completely.
var broken: bool = false
## Horizontal radius of the body (its collision shape): attackers reach it at its surface.
var body_radius: float

var _flash_left: float = 0.0
var _time: float = 0.0
var _frame_overlay := StandardMaterial3D.new()

@onready var _model: Node3D = $Model
@onready var _fill: Node3D = _model.find_child("Fill", true, false)
@onready var _full_lamp: Node3D = _model.find_child("FullLamp", true, false)
@onready var _hose_outlet: Node3D = _model.find_child("HoseOutlet", true, false)
@onready var _hose: Hose = $Hose


func _ready() -> void:
	add_to_group(GROUP)
	health = settings.max_health
	body_radius = (($CollisionShape3D as CollisionShape3D).shape as CylinderShape3D).radius
	if ore_type:
		for mesh: MeshInstance3D in _meshes(_fill):
			mesh.material_override = ore_type.get_material()
		_hose.material_override = ore_type.get_material()
	_frame_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_frame_overlay.next_pass = preload("res://assets/shaders/rim_light.tres")
	for frame: Node in _model.find_children("Frame*", "MeshInstance3D", true, false):
		(frame as MeshInstance3D).material_overlay = _frame_overlay
	_hose.visible = false
	_update_gauge()
	_update_frame()


func _physics_process(delta: float) -> void:
	if not broken and not is_full():
		amount = minf(amount + settings.fill_rate * delta, settings.capacity)
		_update_gauge()
		if is_full():
			filled.emit()

	if Player.nearest(get_tree(), global_position, settings.repair_range):
		repair(settings.repair_rate * delta)

	hose_target = (
		null if broken else Player.nearest(get_tree(), global_position, settings.hose_range)
	)
	if hose_target:
		hose_target.add_cargo(ore_type, take(settings.transfer_rate * delta))


func _process(delta: float) -> void:
	_time += delta
	_flash_left = maxf(_flash_left - delta, 0.0)
	_update_frame()
	_hose.visible = hose_target != null
	if hose_target:
		_hose.build(
			_hose_outlet.global_position, hose_target.get_hose_port_position(), global_position.y
		)


func is_full() -> bool:
	return amount >= settings.capacity


## Removes up to `max_amount` units (e.g. for the hose) and returns how many were taken.
## A full miner starts mining again.
func take(max_amount: float) -> float:
	var taken: float = clampf(max_amount, 0.0, amount)
	amount -= taken
	_update_gauge()
	return taken


## Loses `amount` health; breaks down at zero.
func take_damage(amount_lost: float) -> void:
	if broken or amount_lost <= 0.0:
		return
	health = maxf(health - amount_lost, 0.0)
	_flash_left = FLASH_DURATION
	if health == 0.0:
		broken = true
		broke.emit()


## Restores `amount_repaired` health; a broken miner mines again once it's back to full health.
func repair(amount_repaired: float) -> void:
	health = minf(health + amount_repaired, settings.max_health)
	if broken and health >= settings.max_health:
		broken = false
		repaired.emit()


## Whether any miner in `tree` is still mining (or full), i.e. not broken.
static func any_working(tree: SceneTree) -> bool:
	return tree.get_nodes_in_group(GROUP).any(func(miner: Miner) -> bool: return not miner.broken)


func _update_gauge() -> void:
	var ratio: float = amount / settings.capacity
	# A zero scale makes the basis singular, so hide the fill instead.
	_fill.visible = ratio > 0.0
	_fill.scale = Vector3(1.0, maxf(ratio, 0.001), 1.0)
	_full_lamp.visible = is_full()


func _update_frame() -> void:
	var alarm: bool = broken and fmod(_time * BLINK_RATE, 1.0) < 0.5
	var signal_color: Color = COLOR_FLASH if _flash_left > 0.0 else COLOR_ALARM
	var signaling: bool = _flash_left > 0.0 or alarm
	_frame_overlay.emission_enabled = signaling
	_frame_overlay.emission = signal_color
	_frame_overlay.emission_energy_multiplier = 2.0
	if signaling:
		_frame_overlay.albedo_color = Color(signal_color, SIGNAL_COVER)
	else:
		var damage: float = 1.0 - health / settings.max_health
		_frame_overlay.albedo_color = Color(COLOR_RUST, damage * RUST_MAX)


## `node` itself if it's a mesh, and all meshes below it.
static func _meshes(node: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		meshes.append(node as MeshInstance3D)
	for child: Node in node.find_children("*", "MeshInstance3D", true, false):
		meshes.append(child as MeshInstance3D)
	return meshes
