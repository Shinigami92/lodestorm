class_name QuestMark
extends Node3D
## Marks something a quest step needs in a location (see `QuestVisit`): its site, a crate with one
## of its fragments, one of its quest nests, its brood nest or lair, its item. While it's open
## (`close` ends it: the site reached, the crate opened, the nest destroyed, the item picked up)
## and its quest is the tracked one, a thin amber beam rises from it, tall enough to show over the
## cliffs; the location hologram shows it as an amber beam too (`HoloTable`) and the suit ring
## points to the nearest one (`QuestPointer`). It hides from the hologram's copy of the location
## itself.

const GROUP: StringName = &"quest_marks"
## The quests' amber (their diamonds, the items' glow).
const COLOR := Color(1.0, 0.75, 0.3)
## The beam: its height and radius (m) and how bright it is. TBD (playtest).
const BEAM_HEIGHT: float = 80.0
const BEAM_RADIUS: float = 0.12
const BEAM_ALPHA: float = 0.35
## How often it looks whether its quest is tracked, in s.
const CHECK: float = 0.25

## The goal it's for, and the visit it belongs to.
var entry: QuestVisit.Entry
var visit: QuestVisit
## Whether its target still waits (not reached, opened, destroyed or picked up).
var is_open: bool = true

var _beam: MeshInstance3D
var _check_left: float = 0.0


## A mark for `for_entry` of `in_visit`, added to `target` at `at` (in its space).
static func on(
	target: Node3D, for_entry: QuestVisit.Entry, in_visit: QuestVisit, at := Vector3.ZERO
) -> QuestMark:
	var mark := QuestMark.new()
	mark.name = "QuestMark"
	mark.entry = for_entry
	mark.visit = in_visit
	mark.position = at
	target.add_child(mark)
	return mark


func _init() -> void:
	add_to_group(GROUP)
	add_to_group(HoloTable.HIDDEN_GROUP)
	_beam = _make_beam()
	add_child(_beam)


func _process(delta: float) -> void:
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = CHECK
	_beam.visible = is_lit()


## Whether it shows: open, and its quest is the tracked one.
func is_lit() -> bool:
	return is_open and visit != null and visit.is_tracked(entry)


## Its target is done here: the beam goes out for good.
func close() -> void:
	is_open = false
	_beam.visible = false


## The beam (for tests and probes).
func get_beam() -> MeshInstance3D:
	return _beam


func _make_beam() -> MeshInstance3D:
	var beam := MeshInstance3D.new()
	beam.name = "Beam"
	var mesh := CylinderMesh.new()
	mesh.top_radius = BEAM_RADIUS
	mesh.bottom_radius = BEAM_RADIUS
	mesh.height = BEAM_HEIGHT
	mesh.radial_segments = 12
	mesh.rings = 1
	mesh.cap_top = false
	mesh.cap_bottom = false
	beam.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(COLOR, BEAM_ALPHA)
	material.albedo_texture = LateDeposit.fade_texture()
	beam.material_override = material
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position = Vector3.UP * BEAM_HEIGHT * 0.5
	beam.visible = false
	RenderLayers.put(beam, RenderLayers.EFFECTS)
	return beam
