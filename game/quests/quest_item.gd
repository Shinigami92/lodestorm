class_name QuestItem
extends Interactable
## An item to recover at a quest site (see `RecoverItemGoal`), lying at its part's quest anchor in
## its look (`entry.item`) on an amber glow. A press (`interact`) picks it up: the player carries it
## on the back (`QuestPack`) until they're aboard, where it counts. Close to a player it shows
## behind props and cliffs as an amber silhouette (like a crate).

## How close a player must be for it to show behind props and cliffs, in m (like a crate's).
const SILHOUETTE_RANGE: float = Crate.SILHOUETTE_RANGE
## How often the distance to the players is checked, in s.
const SILHOUETTE_CHECK: float = 0.25
## The glow under it: its radius, in m.
const GLOW_RADIUS: float = 0.55

## The goal it counts for.
var entry: QuestVisit.Entry

var _look: Node3D
var _silhouette: ShaderMaterial = OccludedSilhouette.overlay(OccludedSilhouette.CRATE_COLOR)
var _check_left: float = 0.0


func _init() -> void:
	interact_range = 1.2
	# Before `_ready`: the interactable finds its `Highlight` then.
	_add_glow()


func _ready() -> void:
	_look = entry.item.instantiate() as Node3D
	_look.name = "Look"
	add_child(_look)
	super()
	used.connect(_pick_up)
	OccludedSilhouette.mark_visible(self)


func _process(delta: float) -> void:
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = SILHOUETTE_CHECK
	var shown: bool = false
	for player: Node3D in get_tree().get_nodes_in_group(Player.GROUP):
		if player.global_position.distance_to(global_position) <= SILHOUETTE_RANGE:
			shown = true
			break
	for mesh: MeshInstance3D in _look.find_children("*", "MeshInstance3D", true, false):
		mesh.material_overlay = _silhouette if shown else null


func _pick_up(player: Player) -> void:
	enabled = false
	player.quest_pack.add(entry)
	queue_free()


## An amber disc on the ground under it and, while it's the target, a brighter ring (`Highlight`).
func _add_glow() -> void:
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.albedo_color = Color(1.0, 0.75, 0.3, 0.25)
	var disc := CylinderMesh.new()
	disc.top_radius = GLOW_RADIUS
	disc.bottom_radius = GLOW_RADIUS
	disc.height = 0.01
	disc.material = glow
	var under := MeshInstance3D.new()
	under.name = "Glow"
	under.mesh = disc
	under.position.y = 0.01
	under.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(under)
	var ring_material := StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.albedo_color = Color(1.0, 0.75, 0.3)
	var ring := TorusMesh.new()
	ring.inner_radius = GLOW_RADIUS + 0.05
	ring.outer_radius = GLOW_RADIUS + 0.12
	ring.material = ring_material
	var highlight := MeshInstance3D.new()
	highlight.name = "Highlight"
	highlight.mesh = ring
	highlight.scale.y = 0.05
	highlight.position.y = 0.02
	highlight.visible = false
	highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(highlight)
