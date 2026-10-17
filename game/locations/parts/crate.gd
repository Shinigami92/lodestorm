class_name Crate
extends Interactable
## A crate in a map part: `interact` (a press) opens it once per run. Its lid swings open, what it
## holds (`content`) flies to the player who opened it and is theirs. Unopened, an amber light
## strip glows around it; it goes dark once it's open. Close to a player, an unopened crate
## also shows behind props and cliffs as an amber silhouette (like ore). Crates don't show in the
## location hologram, so finding them stays a discovery. Greybox until the art pass.

## How long the lid takes to swing open, and the content to fly to the player, in s.
const OPEN_TIME: float = 0.5
const FLY_TIME: float = 0.4
## How far the lid swings open, in radians.
const LID_OPEN: float = 1.9
## How close a player must be for an unopened crate to show behind props and cliffs, in m (like
## ore, `OreNode.SILHOUETTE_RANGE`). TBD (playtest).
const SILHOUETTE_RANGE: float = 30.0
## How often the distance to the players is checked, in s.
const SILHOUETTE_CHECK: float = 0.25

## What it holds; set by the location when it's placed (a supply cache unless a quest put
## something in it).
@export var content: CrateContent

var opened: bool = false

var _silhouette: ShaderMaterial = OccludedSilhouette.overlay(OccludedSilhouette.CRATE_COLOR)
var _check_left: float = 0.0

@onready var _lid: Node3D = $Lid
@onready var _strip: MeshInstance3D = $Strip
@onready var _meshes: Array[MeshInstance3D] = [
	$Base/Mesh as MeshInstance3D, $Lid/Top/Mesh as MeshInstance3D, _strip
]


func _init() -> void:
	add_to_group(HoloTable.HIDDEN_GROUP)


func _ready() -> void:
	super()
	if not content:
		content = SupplyCache.new()
	used.connect(_open)
	OccludedSilhouette.mark_visible(self)


func _process(delta: float) -> void:
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = SILHOUETTE_CHECK
	var shown: bool = false
	if not opened:
		for player: Node3D in get_tree().get_nodes_in_group(Player.GROUP):
			if player.global_position.distance_to(global_position) <= SILHOUETTE_RANGE:
				shown = true
				break
	show_silhouette(shown)


## Whether it shows behind props and cliffs (unopened, close to a player).
func is_silhouette_shown() -> bool:
	return _meshes[0].material_overlay != null


func show_silhouette(shown: bool) -> void:
	for mesh: MeshInstance3D in _meshes:
		mesh.material_overlay = _silhouette if shown else null


func _open(player: Player) -> void:
	if opened:
		return
	opened = true
	enabled = false
	highlighted = false
	show_silhouette(false)
	var material := _strip.get_active_material(0) as StandardMaterial3D
	if material:
		material = material.duplicate() as StandardMaterial3D
		material.emission_enabled = false
		material.albedo_color = Color(0.08, 0.08, 0.08)
		_strip.material_override = material
	var swing: Tween = create_tween()
	(
		swing
		. tween_property(_lid, ^"rotation:x", LID_OPEN, OPEN_TIME)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	_fly_to(player)
	content.open(player)


## A glowing piece of the content that flies from the crate to `player` and disappears there.
func _fly_to(player: Player) -> void:
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = content.color
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE * 0.18
	cube.material = glow
	var piece := MeshInstance3D.new()
	piece.mesh = cube
	piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(piece)
	piece.position = Vector3.UP * 0.6
	var flight: Tween = piece.create_tween()
	flight.tween_method(
		func(t: float) -> void:
			if not is_instance_valid(player):
				return
			var target: Vector3 = player.global_position + Vector3.UP * 1.2
			var start: Vector3 = global_transform * (Vector3.UP * 0.6)
			piece.global_position = start.lerp(target, t) + Vector3.UP * sin(t * PI) * 0.8,
		0.0,
		1.0,
		FLY_TIME
	)
	flight.tween_callback(piece.queue_free)
