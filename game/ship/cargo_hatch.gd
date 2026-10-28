class_name CargoHatch
extends Interactable
## The cargo hatch outside on the tail, beside the ramp (greybox until the ship's art pass): an
## intake that slides down a pair of rails on the tail's wall to the ground while the ramp goes down
## and back up with it (it stays up docked at a station). `interact` there while the ramp is down
## for a run unloads everything the player carries into the hold (`Mission.bank_ore`), so the run
## goes on: the ore flows through a hose from the player's back into the intake, one ore after
## another, all of it in `FLOW_TIME`. Walking farther than `HOSE_RANGE` off stops the flow: what
## went in is banked, the rest stays carried (`interact` again goes on). Players bank at the same
## time, each through their own hose. Its strip and the lamp over it glow amber while it can be
## used, in the ore's color while ore flows; dark otherwise.

## Seconds everything a player carries takes to flow in. TBD (playtest).
const FLOW_TIME: float = 2.0
## How far from the intake a player may walk before the flow stops, in m. TBD (playtest).
const HOSE_RANGE: float = 3.0
## How high the intake hangs on the tail's wall while the ramp is up, in m.
const STOWED_RISE: float = 1.7
const COLOR_READY := Color(1.0, 0.7, 0.15)
const COLOR_OFF := Color(0.12, 0.12, 0.12)
const STRIP_ENERGY: float = 3.0
const HOSE_SOUND: Sound = preload("res://assets/audio/sfx/mining/hose.tres")
const LATCH_SOUND: Sound = preload("res://assets/audio/sfx/mining/miner_latch.tres")

## The ship it belongs to: its ramp moves the intake, its mission banks the ore.
@export var ship: Ship

## The flows under way, by player.
var _flows: Dictionary[Player, Flow] = {}
var _strip_material := StandardMaterial3D.new()

@onready var _slide: Node3D = $Slide
@onready var _outlet: Marker3D = $Slide/Outlet
@onready var _strip: MeshInstance3D = $Slide/Strip
@onready var _lamp: OmniLight3D = $Slide/Lamp


## A player's ore flowing in: how fast, what went in so far and the hose it flows through.
class Flow:
	## Units per second, so everything carried at the start flows in within `FLOW_TIME`.
	var rate: float
	## What went in so far, per ore.
	var moved: Dictionary[OreType, float] = {}
	## The ore flowing right now (the hose glows in its color).
	var ore_type: OreType
	var hose: Hose
	var sound: AudioStreamPlayer3D


func _ready() -> void:
	super()
	used.connect(_start_flow)
	_strip_material.emission_enabled = true
	_strip_material.emission_energy_multiplier = STRIP_ENERGY
	_strip.material_override = _strip_material
	# The ship gets ready after its children.
	ship.ready.connect(_follow_ramp, CONNECT_ONE_SHOT)


func _physics_process(delta: float) -> void:
	_follow_ramp()
	enabled = _can_bank()
	for player: Player in _flows.keys():
		_flow(player, delta)


func _process(_delta: float) -> void:
	var color: Color = COLOR_READY if enabled else COLOR_OFF
	for player: Player in _flows:
		var flow: Flow = _flows[player]
		if flow.ore_type:
			color = flow.ore_type.color
		flow.hose.build(_outlet.global_position, player.get_hose_port_position(), global_position.y)
	_strip_material.albedo_color = color
	_strip_material.emission = color
	_lamp.visible = enabled or not _flows.is_empty()
	_lamp.light_color = color


## Whether `player` is banking here right now.
func is_flowing(player: Player) -> bool:
	return _flows.has(player)


## Whether ore can be banked: the ramp down for a run (not docked at a station).
func _can_bank() -> bool:
	return (
		ship.mission != null
		and ship.mission.is_underway()
		and not ship.flight.is_docked()
		and ship.is_ramp_down()
	)


## Slides the intake down with the ramp, or up with it (and keeps it up at a station).
func _follow_ramp() -> void:
	var lowered: float = 0.0 if ship.flight.is_docked() else ship.ramp_lowered()
	_slide.position.y = (1.0 - lowered) * STOWED_RISE


func _start_flow(player: Player) -> void:
	var carried: float = _carried(player)
	if _flows.has(player) or player.dead or carried <= 0.0:
		return
	var flow := Flow.new()
	flow.rate = carried / FLOW_TIME
	flow.hose = Hose.new()
	add_child(flow.hose)
	flow.sound = Sfx.play_loop_at(HOSE_SOUND, self)
	Sfx.play_at(LATCH_SOUND, _outlet.global_position)
	_flows[player] = flow


## Moves this tick's share of `player`'s ore into the intake, one ore after another; ends the flow
## when everything went in, the player walked off or died, or the ramp goes up.
func _flow(player: Player, delta: float) -> void:
	var flow: Flow = _flows[player]
	if not enabled or player.dead or distance_to(player.global_position) > HOSE_RANGE:
		_end_flow(player)
		return
	var left: float = flow.rate * delta
	for ore_type: OreType in player.cargo:
		var carried: float = player.cargo[ore_type]
		if carried <= 0.0:
			continue
		var taken: float = minf(carried, left)
		player.take_ore(ore_type, taken)
		flow.moved[ore_type] = flow.moved.get(ore_type, 0.0) + taken
		_glow(flow, ore_type)
		left -= taken
		if left <= 0.0:
			break
	if _carried(player) <= 0.0:
		_end_flow(player)


## Banks what went in and takes the hose away.
func _end_flow(player: Player) -> void:
	var flow: Flow = _flows[player]
	_flows.erase(player)
	flow.hose.queue_free()
	Sfx.stop_loop(flow.sound)
	Sfx.play_at(LATCH_SOUND, _outlet.global_position)
	if ship.mission and not flow.moved.is_empty():
		ship.mission.bank_ore(player, flow.moved)


## Lets `flow`'s hose glow in `ore_type`'s color.
func _glow(flow: Flow, ore_type: OreType) -> void:
	if flow.ore_type == ore_type:
		return
	flow.ore_type = ore_type
	flow.hose.material_override = ore_type.get_glow_material()
	OreGlow.set_phase(flow.hose, OreGlow.phase_at(global_position))


func _carried(player: Player) -> float:
	var total: float = 0.0
	for ore_type: OreType in player.cargo:
		total += player.cargo[ore_type]
	return total
