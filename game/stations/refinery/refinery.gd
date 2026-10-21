class_name Refinery
extends Node3D
## The refinery in the cargo bay's front corner by the lower deck's door (greybox until the cargo
## bay's art pass): four furnaces in a row (`FurnaceStation`, slots 0–3; the ship's `Furnaces` say
## how many are unlocked) and the ingot rack beside them (`IngotRack`), doors and shelves facing
## the camera. A pipe runs from each silo cluster's pump hub (in `hold`) over the bay to a
## manifold above the furnaces, which takes the furnaces' flues.
## Every second (`TICK`) it puts the bars every player's batches finished by then into their hold
## (`Refining.update`), so they land while playing and during runs; the save does it on loading.

## Seconds between checks for finished bars.
const TICK: float = 1.0
## Height of the pipes over the bay and of the manifold, in m.
const PIPE_HEIGHT: float = 6.2
const MANIFOLD_HEIGHT: float = FurnaceStation.FLUE_TOP
const PIPE_RADIUS: float = 0.1

## The hold whose silo clusters feed it (pipes from their hubs); none drawn without one.
@export var hold: OreHold

var _since_tick: float = 0.0
var _pipe_material := StandardMaterial3D.new()


func _ready() -> void:
	_pipe_material.albedo_color = Color(0.3, 0.32, 0.35)
	_pipe_material.metallic = 0.3
	_pipe_material.roughness = 0.45
	_build_pipes.call_deferred()


func _process(delta: float) -> void:
	_since_tick += delta
	if _since_tick < TICK:
		return
	_since_tick = 0.0
	tick(Time.get_unix_time_from_system())


## Puts the bars every player's batches finished by `now` (Unix seconds) into their hold.
func tick(now: float) -> void:
	for player: Player in get_tree().get_nodes_in_group(Player.GROUP):
		player.refining.update(player.hold, now)


## The furnaces, by slot.
func get_furnaces() -> Array[FurnaceStation]:
	var furnaces: Array[FurnaceStation] = []
	for child: Node in get_children():
		if child is FurnaceStation:
			furnaces.append(child as FurnaceStation)
	furnaces.sort_custom(func(a: FurnaceStation, b: FurnaceStation) -> bool: return a.slot < b.slot)
	return furnaces


## The manifold along the flues' tops, and a pipe from each of the hold's hubs: up to
## `PIPE_HEIGHT`, over towards the furnaces and down into the manifold's middle. Deferred, so the
## hold has built its silos.
func _build_pipes() -> void:
	var furnaces: Array[FurnaceStation] = get_furnaces()
	if furnaces.is_empty():
		return
	var flue_z: float = -FurnaceStation.DEPTH * 0.2
	var left: float = furnaces[0].position.x
	var right: float = furnaces[-1].position.x
	_pipe(Vector3(left, MANIFOLD_HEIGHT, flue_z), Vector3(right, MANIFOLD_HEIGHT, flue_z))
	if not hold:
		return
	var middle := Vector3((left + right) * 0.5, MANIFOLD_HEIGHT, flue_z)
	var over := Vector3(middle.x, PIPE_HEIGHT, middle.z)
	_pipe(middle, over)
	for node: Node in hold.find_children("Hub", "MeshInstance3D", false, false):
		var hub := node as MeshInstance3D
		var top: Vector3 = to_local(hub.global_position) + Vector3.UP * 0.55
		var above := Vector3(top.x, PIPE_HEIGHT, top.z)
		var corner := Vector3(over.x, PIPE_HEIGHT, above.z)
		_pipe(top, above)
		_pipe(above, corner)
		_pipe(corner, over)


func _pipe(from: Vector3, to: Vector3) -> void:
	if from.distance_to(to) < 0.01:
		return
	var mesh := CylinderMesh.new()
	mesh.top_radius = PIPE_RADIUS
	mesh.bottom_radius = PIPE_RADIUS
	mesh.height = from.distance_to(to) + PIPE_RADIUS * 2.0
	mesh.radial_segments = 10
	mesh.rings = 1
	mesh.material = _pipe_material
	var pipe := MeshInstance3D.new()
	pipe.name = "Pipe"
	pipe.mesh = mesh
	pipe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var direction: Vector3 = (to - from).normalized()
	var side: Vector3 = (
		Vector3.RIGHT if absf(direction.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	)
	var basis_x: Vector3 = direction.cross(side).normalized()
	pipe.transform = Transform3D(
		Basis(basis_x, direction, basis_x.cross(direction)), (from + to) * 0.5
	)
	add_child(pipe)
