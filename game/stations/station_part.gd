class_name StationPart
extends Node3D
## A selectable part of a `Station`: a weapon's barrel or magazine on the workbench, a miner's
## drill, a weapon on the rack. The player points at it (or moves the highlight to it), and the
## station's holo card shows it. Hovered and selected, the meshes under `outline` get an amber
## outline (like the highlight on the screens).

enum Highlight { NONE, HOVERED, SELECTED }

const SELECTED_COLOR := Color(1.0, 0.75, 0.3, 1.0)
const HOVERED_COLOR := Color(1.0, 0.75, 0.3, 0.45)
## How far the outline stands out from the meshes, in m.
const OUTLINE_WIDTH: float = 0.02

static var _outlines: Dictionary[Highlight, StandardMaterial3D] = {}

## What it stands for (e.g. an `Upgrade`, a `WeaponType`); up to its station.
@export var item: Resource
## How far from its center (in m) the mouse cursor still points at it.
@export var pick_radius: float = 0.2
## Where the holo card floats while it's selected, from the part, in m: x to the right on screen,
## y up.
@export var card_offset: Vector2 = Vector2(0.9, 0.3)
## The meshes outlined while it's hovered or selected (every `MeshInstance3D` under it, itself
## included); none when not set.
@export var outline: Node3D

var highlight: Highlight = Highlight.NONE


## Shows it hovered, selected or neither.
func set_highlight(value: Highlight) -> void:
	highlight = value
	if not outline:
		return
	var material: Material = _outline(value) if value != Highlight.NONE else null
	var meshes: Array[Node] = outline.find_children("*", "MeshInstance3D", true, false)
	if outline is MeshInstance3D:
		meshes.append(outline)
	for mesh: MeshInstance3D in meshes:
		mesh.material_overlay = material


## Where the holo card floats while it's selected, seen by `camera`.
func card_position(camera: Camera3D) -> Vector3:
	var view: Basis = camera.global_basis
	return global_position + view.x * card_offset.x + view.y * card_offset.y


## How far (in px) the mouse cursor at `screen_position` is from its center, or INF when it's
## farther than `pick_radius`.
func distance_on_screen(camera: Camera3D, screen_position: Vector2) -> float:
	if camera.is_position_behind(global_position):
		return INF
	var center: Vector2 = camera.unproject_position(global_position)
	var edge: Vector2 = camera.unproject_position(
		global_position + camera.global_basis.x * pick_radius
	)
	var distance: float = center.distance_to(screen_position)
	return distance if distance <= center.distance_to(edge) else INF


## An outline shell: the back faces of the meshes, pushed out a little.
static func _outline(value: Highlight) -> StandardMaterial3D:
	if not _outlines.has(value):
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_FRONT
		material.grow = true
		material.grow_amount = OUTLINE_WIDTH
		material.albedo_color = SELECTED_COLOR if value == Highlight.SELECTED else HOVERED_COLOR
		if value == Highlight.HOVERED:
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_outlines[value] = material
	return _outlines[value]
