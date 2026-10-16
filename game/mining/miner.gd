class_name Miner
extends StaticBody3D
## Mines its ore node's ore over time and stops when full. The fill level shows in the world:
## the glass column fills up in the ore color and the lamp on top lights up when full.
## A hose connects to the nearest player within `settings.hose_range` and moves the ore to them.
## Aliens can attack it: the frame flashes white when hit and turns rusty with damage. At zero
## health it breaks down: it stops mining and the hose disconnects, so its ore can't be taken out
## (it keeps it). The frame blinks red until a player standing within `settings.repair_range` has
## repaired it completely. Players repair damaged miners that still work too.
## The upgrades of the player who placed it (`upgrades`) raise its fill rate (`drill_upgrade`),
## capacity (`tank_upgrade`), hose range and transfer rate (`hose_upgrade`); for now they apply to
## every miner that player places.
##
## The look lives in the `Model` child, so a modeled asset can replace the greybox. The model
## provides these parts by name: `Fill` (scaled along Y from 0 to 1 with the fill level; it and its
## meshes get the ore material), `FullLamp`, `HoseOutlet`, and meshes named `Frame*` (the
## structure that shows damage). Damage is drawn as an overlay on the frame, so it works on top of
## any material the model brings. Parts are looked up among all descendants (also inside an
## instanced model scene). The model's front is +Z: when the miner is placed, the model turns its
## front toward the camera's view (plus `FACING_OFFSET`), so the fill column stays in view.

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
## How far the model turns past facing the camera (degrees): straight on looks flat and puts a leg
## in front of the drill, 45° lets a side box cover the column.
const FACING_OFFSET: float = 25.0
## Seconds a hit flash lasts.
const FLASH_DURATION: float = 0.1
## Blinks per second while broken.
const BLINK_RATE: float = 2.0

@export var settings: MinerSettings
@export var drill_upgrade: Upgrade
@export var tank_upgrade: Upgrade
@export var hose_upgrade: Upgrade

## Set by the ore node before the miner enters the tree.
var ore_type: OreType
## The upgrades of the player who placed it (set with `ore_type`), or null: MK1.
var upgrades: Upgrades
## Units currently held, between 0 and `capacity()`.
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
	_face_camera()
	if ore_type:
		# In sync with the deposit it stands on (see `OreGlow.phase_at`).
		var phase: float = OreGlow.phase_at(global_position)
		for mesh: MeshInstance3D in _meshes(_fill):
			mesh.material_override = ore_type.get_glow_material()
			OreGlow.set_phase(mesh, phase)
		_hose.material_override = ore_type.get_glow_material()
		OreGlow.set_phase(_hose, phase)
	_frame_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_frame_overlay.next_pass = preload("res://assets/shaders/rim_light.tres")
	for frame: Node in _model.find_children("Frame*", "MeshInstance3D", true, false):
		(frame as MeshInstance3D).material_overlay = _frame_overlay
	_hose.visible = false
	_update_gauge()
	_update_frame()


func _physics_process(delta: float) -> void:
	if not broken and not is_full():
		amount = minf(amount + fill_rate() * delta, capacity())
		_update_gauge()
		if is_full():
			filled.emit()

	if Player.nearest(get_tree(), global_position, settings.repair_range):
		repair(settings.repair_rate * delta)

	hose_target = (null if broken else Player.nearest(get_tree(), global_position, hose_range()))
	if hose_target:
		hose_target.add_cargo(ore_type, take(transfer_rate() * delta))


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
	return amount >= capacity()


## Units mined per second, with the drill upgrade (rarer ores mine slower, `OreType.mine_rate`).
func fill_rate() -> float:
	var ore_rate: float = ore_type.mine_rate if ore_type else 1.0
	return settings.fill_rate * ore_rate * _multiplier(drill_upgrade)


## Units it holds when full, with the tank upgrade.
func capacity() -> float:
	return settings.capacity * _multiplier(tank_upgrade)


## How close a player must be for the hose to connect, with the hose upgrade.
func hose_range() -> float:
	return settings.hose_range * _multiplier(hose_upgrade)


## Units per second the hose moves, with the hose upgrade.
func transfer_rate() -> float:
	return settings.transfer_rate * _multiplier(hose_upgrade)


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
	var ratio: float = amount / capacity()
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


func _multiplier(upgrade: Upgrade) -> float:
	return upgrades.multiplier(upgrade) if upgrades else 1.0


func _face_camera() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if not camera:
		return
	# Against the view direction rather than toward the camera's position: the same for every miner
	# on screen, wherever the camera is.
	var to_camera: Vector3 = camera.global_basis.z
	if Vector2(to_camera.x, to_camera.z).is_zero_approx():
		return
	var yaw: float = atan2(to_camera.x, to_camera.z) + deg_to_rad(FACING_OFFSET)
	_model.global_basis = Basis(Vector3.UP, yaw)


## `node` itself if it's a mesh, and all meshes below it.
static func _meshes(node: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		meshes.append(node as MeshInstance3D)
	for child: Node in node.find_children("*", "MeshInstance3D", true, false):
		meshes.append(child as MeshInstance3D)
	return meshes
