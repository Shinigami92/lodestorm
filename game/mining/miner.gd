class_name Miner
extends StaticBody3D
## Mines its ore node's ore over time (`OreNode.mine`) and stops when full or when the node runs
## dry. The fill level shows in the world: the glass column fills up in the ore color and the lamp
## on top lights up when full; on a dry node it blinks amber instead ("move me").
## A hose connects to the nearest player within `settings.hose_range` and moves the ore to them.
## Aliens can attack it: the frame flashes white when hit and turns rusty with damage. At zero
## health it breaks down: it stops mining and the hose disconnects, so its ore can't be taken out
## (it keeps it). The frame blinks red until a player standing within `settings.repair_range` has
## repaired it completely. Players repair damaged miners that still work too.
## Its sounds: set down with a thud, the servos' loop while it's placed or picked up (higher as it
## turns real; not while that waits), the drill's loop while it mines, the hose's while ore flows,
## a chime when full, an alarm when it breaks down and the repair's loop while a player mends it.
## A player's miners come from their `MinerFleet` (`take_from`): a crafted one brings its own
## levels (`upgrades`), which raise its fill rate (`drill_upgrade`), capacity (`tank_upgrade`), hose
## range and transfer rate (`hose_upgrade`) and health (`plating_upgrade`), and wears its number
## plate with a strip in its owner's color; a standard-issue one is MK1 in everything, mines at
## `settings.standard_fill_share` and has a plain grey plate. Its drill's MK level sets how hard an
## ore it mines at full speed (`Upgrade.hardness_at`, standard-issue ones MK1); a harder one it
## mines at `settings.soft_drill_share` of the speed, its drill turning slower and its loop
## strained. Placing takes the miner that mines the node's ore fastest. Any player can pick one up
## with `interact` within `settings.repair_range` (`pick_up`): what's in its tank goes onto their
## back and the miner back to its owner's fleet, to place again.
## Placing and picking up take time (see `MinerHandling`): meanwhile it stands on its node as a
## hologram that turns real from the bottom up as its `handled_by` player places it, and back into
## a hologram from the top down as they pick it up (`built`, `MinerHologram`); its fill, number
## plate and hose show only once it's real. Only a standing miner mines, connects its hose and can
## be picked up. Its ring on the ground (`MinerRing`) shows its health, fill, hose range and that
## progress.
##
## The look lives in the `Model` child, so a modeled asset can replace the greybox. The model
## provides these parts by name: `Fill` (scaled along Y from 0 to 1 with the fill level; it and its
## meshes get the ore material), `FullLamp`, `HoseOutlet`, and meshes named `Frame*` (the
## structure that shows damage) and `Drill` (turning about its Y axis while it mines). Damage is
## drawn as an overlay on the frame, so it works on top of any material the model brings. Parts are
## looked up among all descendants (also inside an instanced model scene). The model's front is +Z:
## when the miner is placed, the model turns its front toward the camera's view (plus
## `FACING_OFFSET`), so the fill column stays in view.

## Emitted once each time the miner becomes full.
signal filled
## Emitted when its ore node runs dry while it mines.
signal ran_dry
## Emitted when health reaches zero and the miner stops mining and transferring.
signal broke
## Emitted when a broken miner is repaired completely and mines again.
signal repaired
## Emitted when `by` picks it up (it leaves the world right after).
signal picked_up(by: Player)

const GROUP: StringName = &"miners"

const COLOR_RUST := Color(0.45, 0.17, 0.06)
const COLOR_FLASH := Color(1.0, 1.0, 1.0)
const COLOR_ALARM := Color(1.0, 0.15, 0.1)
## The plate of a standard-issue miner (the ship's: no number, no owner's color).
const COLOR_STANDARD_PLATE := Color(0.42, 0.44, 0.46)
const COLOR_HIGHLIGHT := Color(1.0, 0.75, 0.3)
## The lamp blinking on a dry node.
const COLOR_DRY := Color(1.0, 0.55, 0.1)
## How bright the lamp glows blinking amber.
const DRY_ENERGY: float = 8.0
## How much the rust covers the frame at zero health (0–1).
const RUST_MAX: float = 0.75
## How much a hit flash or the alarm blink covers the frame (0–1).
const SIGNAL_COVER: float = 0.7
## How far the model turns past facing the camera (degrees): straight on looks flat and puts a leg
## in front of the drill, 45° lets a side box cover the column.
const FACING_OFFSET: float = 25.0
## Seconds a hit flash lasts.
const FLASH_DURATION: float = 0.1
## Blinks per second while broken, and the lamp's on a dry node.
const BLINK_RATE: float = 2.0
## Seconds it takes to turn real again when a pickup is cancelled.
const STAND_TIME: float = 0.4
## How bright the hologram is while the build waits for its player (0–1).
const WAITING_ENERGY: float = 0.35
## The servos' pitch as a hologram and real.
const SERVO_PITCH := Vector2(0.8, 1.2)
## How fast the drill turns while it mines at full speed (radians per second).
const DRILL_SPIN: float = 9.0
## The drill's loop on an ore too hard for it: lower, wavering this much this many times a second.
const STRAINED_PITCH: float = 0.7
const STRAINED_WAVER: float = 0.04
const STRAINED_WAVER_RATE: float = 3.0

const PLACE_SOUND: Sound = preload("res://assets/audio/sfx/mining/miner_place.tres")
const DRILL_SOUND: Sound = preload("res://assets/audio/sfx/mining/drill.tres")
const HOSE_SOUND: Sound = preload("res://assets/audio/sfx/mining/hose.tres")
const FULL_SOUND: Sound = preload("res://assets/audio/sfx/mining/miner_full.tres")
const BREAKDOWN_SOUND: Sound = preload("res://assets/audio/sfx/mining/breakdown.tres")
const REPAIR_SOUND: Sound = preload("res://assets/audio/sfx/mining/repair.tres")
const SERVO_SOUND: Sound = preload("res://assets/audio/sfx/mining/miner_servo.tres")

@export var settings: MinerSettings
@export var drill_upgrade: Upgrade
@export var tank_upgrade: Upgrade
@export var hose_upgrade: Upgrade
@export var plating_upgrade: Upgrade

## Set by the ore node before the miner enters the tree.
var ore_type: OreType
## Its levels (a crafted miner's, see `take_from`), or null: MK1.
var upgrades: Upgrades
## The ore node it stands on (set with `ore_type`), or null.
var ore_node: OreNode
## The fleet it came from (null: placed loose, e.g. by a test), the crafted miner it is (null:
## standard-issue or loose) and its owner.
var fleet: MinerFleet
var crafted: CraftedMiner
var owned_by: Player
## Whether it's a standard-issue miner (the ship's).
var standard: bool = false
## Units currently held, between 0 and `capacity()`.
var amount: float = 0.0
## The player the hose is connected to, or null.
var hose_target: Player
## Current health, from 0 to `max_health()`.
var health: float
## A broken miner doesn't mine and its hose doesn't connect until it's repaired completely.
var broken: bool = false
## Horizontal radius of the body (its collision shape): attackers reach it at its surface.
var body_radius: float
## How far it's real: 0 only the hologram, 1 the miner itself (see `MinerHologram`).
var built: float = 1.0
## The player placing or picking it up (see `MinerHandling`), or null.
var handled_by: Player
## Whether placing or picking it up waits for `handled_by` to come back into range.
var paused: bool = false

var _flash_left: float = 0.0
var _time: float = 0.0
var _frame_overlay := StandardMaterial3D.new()
var _dry_lamp := StandardMaterial3D.new()
## The loops playing (null: off).
var _drill: AudioStreamPlayer3D
var _flow: AudioStreamPlayer3D
var _repairing: AudioStreamPlayer3D
var _servo: AudioStreamPlayer3D
## What picks it up (a fleet's miner), or null.
var _pickup: Interactable
## Whether it mined in the last physics frame.
var _mining: bool = false
## Its look while it's placed or picked up, and its height (its collision shape's).
var _hologram: MinerHologram
var _height: float

@onready var _model: Node3D = $Model
@onready var _fill: Node3D = _model.find_child("Fill", true, false)
@onready var _full_lamp: Node3D = _model.find_child("FullLamp", true, false)
@onready var _lamp_meshes: Array[MeshInstance3D] = _meshes(_full_lamp)
@onready var _hose_outlet: Node3D = _model.find_child("HoseOutlet", true, false)
@onready var _hose: Hose = $Hose
@onready var _plate: Node3D = _model.get_node_or_null(^"Plate") as Node3D
@onready var _drill_bit: Node3D = _model.find_child("Drill", true, false) as Node3D


func _ready() -> void:
	add_to_group(GROUP)
	health = max_health()
	if crafted and crafted.health >= 0.0:
		# Picked up earlier in this run: its damage comes along.
		health = minf(crafted.health, health)
		broken = health == 0.0
	var body := ($CollisionShape3D as CollisionShape3D).shape as CylinderShape3D
	body_radius = body.radius
	_height = body.height
	_face_camera()
	# The fill and the plate don't show as a hologram.
	var parts: Array[MeshInstance3D] = []
	for mesh: MeshInstance3D in _meshes(_model):
		var in_fill: bool = mesh == _fill or _fill.is_ancestor_of(mesh)
		if not in_fill and not (_plate and _plate.is_ancestor_of(mesh)):
			parts.append(mesh)
	_hologram = MinerHologram.new(parts)
	if ore_type:
		# In sync with the deposit it stands on (see `OreGlow.phase_at`).
		var phase: float = OreGlow.phase_at(global_position)
		for mesh: MeshInstance3D in _meshes(_fill):
			mesh.material_override = ore_type.get_glow_material()
			OreGlow.set_phase(mesh, phase)
		_hose.material_override = ore_type.get_glow_material()
		OreGlow.set_phase(_hose, phase)
	_dry_lamp.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dry_lamp.albedo_color = COLOR_DRY
	_dry_lamp.emission_enabled = true
	_dry_lamp.emission = COLOR_DRY
	_dry_lamp.emission_energy_multiplier = DRY_ENERGY
	_frame_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_frame_overlay.next_pass = preload("res://assets/shaders/rim_light.tres")
	# Seen behind cliffs too, as a silhouette.
	var silhouette: ShaderMaterial = OccludedSilhouette.overlay(
		OccludedSilhouette.MINER_COLOR, _frame_overlay
	)
	for frame: Node in _model.find_children("Frame*", "MeshInstance3D", true, false):
		(frame as MeshInstance3D).material_overlay = silhouette
	OccludedSilhouette.mark_visible(_model)
	_hose.visible = false
	_show_plate()
	if fleet:
		_add_pickup()
	_update_gauge()
	_update_frame()
	var ring := MinerRing.new()
	ring.name = "Ring"
	add_child(ring)
	if is_standing():
		Sfx.play_at(PLACE_SOUND, global_position)
	else:
		_show_built()


func _physics_process(delta: float) -> void:
	var standing: bool = is_standing()
	var mining: bool = standing and not broken and not is_full() and not is_dry()
	_mining = mining
	if mining:
		var mined: float = minf(fill_rate() * delta, capacity() - amount)
		if ore_node:
			mined = ore_node.mine(mined)
		amount = minf(amount + mined, capacity())
		_update_gauge()
		if is_full():
			filled.emit()
			Sfx.play_at(FULL_SOUND, global_position)
		elif is_dry():
			ran_dry.emit()
			GameEvents.bus.miner_ran_dry.emit(self)
			Sfx.play_at(FULL_SOUND, global_position)

	var mending: bool = false
	if Player.nearest(get_tree(), global_position, settings.repair_range):
		mending = health < max_health()
		repair(settings.repair_rate * delta)

	hose_target = (
		Player.nearest(get_tree(), global_position, hose_range())
		if standing and not broken
		else null
	)
	var flowing: bool = false
	if hose_target:
		var taken: float = take(transfer_rate() * delta)
		flowing = taken > 0.0
		hose_target.cargo.add(ore_type, taken)
	_drill = _loop(_drill, DRILL_SOUND, mining)
	if _drill:
		_drill.pitch_scale = (
			STRAINED_PITCH + STRAINED_WAVER * sin(_time * TAU * STRAINED_WAVER_RATE)
			if is_drill_too_soft()
			else 1.0
		)
	_flow = _loop(_flow, HOSE_SOUND, flowing)
	_repairing = _loop(_repairing, REPAIR_SOUND, mending)
	_servo = _loop(_servo, SERVO_SOUND, not standing and not paused)
	if _servo:
		_servo.pitch_scale = lerpf(SERVO_PITCH.x, SERVO_PITCH.y, built)


func _process(delta: float) -> void:
	_time += delta
	if not is_instance_valid(handled_by) and built < 1.0:
		# A pickup cancelled: it turns real again.
		paused = false
		built = move_toward(built, 1.0, delta / STAND_TIME)
		if built >= 1.0:
			stand()
	if not is_standing():
		_show_built()
	if _mining and _drill_bit:
		var spin: float = settings.soft_drill_share if is_drill_too_soft() else 1.0
		_drill_bit.rotate_y(DRILL_SPIN * spin * delta)
	if _pickup:
		_pickup.enabled = is_standing()
	_flash_left = maxf(_flash_left - delta, 0.0)
	_update_frame()
	_update_lamp()
	_hose.visible = hose_target != null
	if hose_target:
		_hose.build(
			_hose_outlet.global_position, hose_target.get_hose_port_position(), global_position.y
		)


func is_full() -> bool:
	return amount >= capacity()


## Whether its ore node has run dry (a loose miner without one never does).
func is_dry() -> bool:
	return ore_node != null and ore_node.is_dry()


## Whether it stands on its node, nobody placing or picking it up: only then it mines, connects
## its hose and can be picked up.
func is_standing() -> bool:
	return built >= 1.0 and not is_instance_valid(handled_by)


## Makes it real for good (placing done, or real again after a cancelled pickup), with a thud.
func stand() -> void:
	built = 1.0
	handled_by = null
	paused = false
	_hologram.hide()
	_show_plate()
	_update_gauge()
	Sfx.play_at(PLACE_SOUND, global_position)


## Takes a miner out of `from_fleet` (after `ore_type` is set, before it enters the tree): the one
## still to place that mines this ore fastest (a crafted one with its levels, the first by number on
## a tie, or a standard-issue one). `by` is the player placing it, whose fleet it is.
func take_from(from_fleet: MinerFleet, by: Player) -> void:
	fleet = from_fleet
	owned_by = by
	crafted = _fastest(fleet)
	fleet.take(crafted)
	standard = crafted == null
	upgrades = crafted.upgrades if crafted else null


## Units mined per second, with the drill upgrade (rarer ores mine slower, `OreType.mine_rate`, and
## ores too hard for the drill slower still; standard-issue miners at
## `settings.standard_fill_share`).
func fill_rate() -> float:
	return _fill_rate_with(upgrades, standard)


## Whether its ore is harder than its drill mines at full speed.
func is_drill_too_soft() -> bool:
	return ore_type != null and ore_type.hardness > _drill_hardness(upgrades)


## Health when undamaged, with the plating upgrade.
func max_health() -> float:
	return settings.max_health * _multiplier(plating_upgrade)


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
		GameEvents.bus.miner_broke.emit(self)
		Sfx.play_at(BREAKDOWN_SOUND, global_position)


## Restores `amount_repaired` health; a broken miner mines again once it's back to full health.
func repair(amount_repaired: float) -> void:
	health = minf(health + amount_repaired, max_health())
	if broken and health >= max_health():
		broken = false
		repaired.emit()
		GameEvents.bus.miner_repaired.emit(self)


## Picks it up for `by` (anyone, also a broken one): what's in its tank goes onto their back, the
## miner back to its owner's fleet (a crafted one with its damage, until the run ends), and it
## leaves the world. Nothing happens once the run it was placed in has ended (it's lost then).
## Returns whether it was picked up.
func pick_up(by: Player) -> bool:
	if not fleet or is_queued_for_deletion() or (crafted and not crafted.out):
		return false
	if amount > 0.0:
		by.cargo.add(ore_type, take(amount))
	if crafted:
		crafted.health = health
	fleet.bring_back(crafted)
	if ore_node and ore_node.miner == self:
		ore_node.miner = null
	picked_up.emit(by)
	queue_free()
	return true


## Whether any miner in `tree` is still mining (or full), i.e. not broken.
static func any_working(tree: SceneTree) -> bool:
	return tree.get_nodes_in_group(GROUP).any(func(miner: Miner) -> bool: return not miner.broken)


## `playing` with `sound` started or stopped as `on` says.
func _loop(playing: AudioStreamPlayer3D, sound: Sound, on: bool) -> AudioStreamPlayer3D:
	if on and not playing:
		return Sfx.play_loop_at(sound, self)
	if not on and playing:
		Sfx.stop_loop(playing)
		return null
	return playing


func _update_gauge() -> void:
	var ratio: float = amount / capacity()
	# A zero scale makes the basis singular, so hide the fill instead; a hologram has none.
	_fill.visible = ratio > 0.0 and not _hologram.shown
	_fill.scale = Vector3(1.0, maxf(ratio, 0.001), 1.0)
	_full_lamp.visible = is_full()


## Lights the lamp steady when full; on a dry node it blinks amber (only once it's real: the
## hologram keeps the lamp's materials meanwhile).
func _update_lamp() -> void:
	if not is_standing() or is_full():
		return
	var dry: bool = is_dry()
	_full_lamp.visible = dry and fmod(_time * BLINK_RATE, 1.0) < 0.5
	for mesh: MeshInstance3D in _lamp_meshes:
		mesh.material_override = _dry_lamp if dry else null


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
		var damage: float = 1.0 - health / max_health()
		_frame_overlay.albedo_color = Color(COLOR_RUST, damage * RUST_MAX)


func _multiplier(upgrade: Upgrade) -> float:
	return upgrades.multiplier(upgrade) if upgrades else 1.0


## The fill rate with the drill of `levels` (null: MK1); `standard_issue`: at the ship's share.
func _fill_rate_with(levels: Upgrades, standard_issue: bool) -> float:
	var share: float = settings.standard_fill_share if standard_issue else 1.0
	var drill: float = levels.multiplier(drill_upgrade) if levels else 1.0
	return (
		settings.fill_rate * share * drill * settings.ore_share(ore_type, _drill_hardness(levels))
	)


## The hardest ore the drill of `levels` (null: MK1) mines at full speed.
func _drill_hardness(levels: Upgrades) -> int:
	return drill_upgrade.hardness_at(levels.mk(drill_upgrade) if levels else 1)


## Of the miners still to place in `from_fleet`, the crafted one that mines this ore fastest (the
## first by number on a tie), or null when a standard-issue one is faster or no crafted one is left.
func _fastest(from_fleet: MinerFleet) -> CraftedMiner:
	var best: CraftedMiner = null
	var best_rate: float = -1.0
	for miner: CraftedMiner in from_fleet.waiting():
		var rate: float = _fill_rate_with(miner.upgrades, false)
		if rate > best_rate:
			best = miner
			best_rate = rate
	if from_fleet.standard_left() > 0 and _fill_rate_with(null, true) > best_rate:
		return null
	return best


## Shows the number plate: a crafted miner's number above a strip in its owner's color, a
## standard-issue miner's plain grey plate; loose miners and holograms have none.
func _show_plate() -> void:
	if not _plate:
		return
	_plate.visible = fleet != null and not _hologram.shown
	var label := _plate.get_node(^"Number") as Label3D
	label.text = crafted.plate() if crafted else ""
	var strip := _plate.get_node(^"Strip") as MeshInstance3D
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = owned_by.color() if crafted and owned_by else COLOR_STANDARD_PLATE
	strip.material_override = material


## The `Interactable` that picks it up (any player within the repair range), with an amber ring.
func _add_pickup() -> void:
	_pickup = Interactable.new()
	_pickup.name = "Pickup"
	_pickup.interact_range = settings.repair_range
	var ring := MeshInstance3D.new()
	ring.name = "Highlight"
	var torus := TorusMesh.new()
	torus.inner_radius = body_radius + 0.05
	torus.outer_radius = body_radius + 0.12
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = COLOR_HIGHLIGHT
	torus.material = material
	ring.mesh = torus
	ring.position.y = 0.05
	ring.visible = false
	_pickup.add_child(ring)
	add_child(_pickup)
	_pickup.used.connect(func(player: Player) -> void: player.handling.pick_up(self))


## Shows it as far as it's `built`, from its foot up, and the rest as the hologram.
func _show_built() -> void:
	var was_shown: bool = _hologram.shown
	# Just below its foot at 0, so nothing is real yet, and just above its top at 1.
	var line: float = global_position.y - 0.05 + (_height + 0.1) * built
	_hologram.show(line, WAITING_ENERGY if paused else 1.0)
	if not was_shown:
		_show_plate()
		_update_gauge()


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
