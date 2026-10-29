class_name MinerPreview
extends Node3D
## The miner a player would place right now (see `MinerPicker`), standing on that ore node as a
## faint hologram (`miner_preview.gdshader`: fainter than one being placed, slowly breathing, no
## scan lines), so it also shows that a miner can go there. It wears the miner's number plate (a
## plain grey one for standard-issue) above a strip in its owner's color, a label with its drill's
## and tank's MK levels, and its color says how its drill fits the ore: cyan at full speed, amber
## when it's too soft. The ring under it has a tick for how long it would take to fill there (the
## full circle `DIAL_TIME`). `show_choice` puts it on a node (fading in, again on another node),
## clearing `wanted` fades it out, `hide_now` hides it at once (when it's placed). Only its own
## player sees it (the picker makes it for the local player).

## The hologram's cyan (see `MinerRing.PROGRESS_COLOR`) and the amber of a drill too soft.
const FULL_SPEED_COLOR := Color(0.3, 0.85, 1.0)
const TOO_SOFT_COLOR := Color(1.0, 0.6, 0.15)
## Seconds it takes to fade in or out.
const FADE_TIME: float = 0.3
## The fill time a full circle of the ring stands for, in s (beyond it, the tick stays at the top).
## TBD (playtest).
const DIAL_TIME: float = 600.0
## The ring's circle: its radius and half its width, in m (the miner's own arcs lie around it).
const RING_RADIUS: float = 1.83
const RING_HALF_WIDTH: float = 0.03
const RING_ALPHA: float = 0.8
## How much the plate and the label show, at full fade.
const PLATE_ALPHA: float = 0.85

## The miner scene whose model it shows (the holder's `Player.miner_scene`).
var miner_scene: PackedScene
## Whether it shows (it fades towards it).
var wanted: bool = false
## The node it stands on, and the miner it shows.
var node: OreNode
var choice: MinerChoice
## How far it has faded in (0–1).
var fade: float = 0.0
## Its color right now.
var tint: Color = FULL_SPEED_COLOR

var _model: Node3D
var _parts: Array[MeshInstance3D] = []
var _plate: Node3D
var _number: Label3D
var _label: Label3D
var _strip := StandardMaterial3D.new()
var _ring := MeshInstance3D.new()
var _ring_material := ShaderMaterial.new()


func _ready() -> void:
	top_level = true
	visible = false
	var miner := miner_scene.instantiate() as Miner
	_model = miner.get_node(^"Model") as Node3D
	miner.remove_child(_model)
	miner.free()
	add_child(_model)
	_dress_model()
	_add_ring()


func _process(delta: float) -> void:
	var showing: bool = wanted and is_instance_valid(node)
	fade = move_toward(fade, 1.0 if showing else 0.0, delta / FADE_TIME)
	visible = fade > 0.0 and is_instance_valid(node)
	if not visible:
		return
	Miner.face_camera(_model)
	_ring.global_basis = Basis.looking_at(
		SuitRing.screen_up(get_viewport().get_camera_3d()), Vector3.UP
	)
	for part: MeshInstance3D in _parts:
		part.set_instance_shader_parameter(&"tint", tint)
		part.set_instance_shader_parameter(&"fade", fade)
	_ring_material.set_shader_parameter(&"fade", fade)
	var alpha: float = fade * PLATE_ALPHA
	_number.modulate.a = alpha
	_number.outline_modulate.a = alpha
	_label.modulate = Color(tint, alpha)
	_label.outline_modulate.a = alpha
	_strip.albedo_color.a = alpha


## Shows `choice` (a miner still to place of the player in `owner_color`) on `on_node`: it fades in,
## from nothing again when it moves to another node.
func show_choice(on_node: OreNode, shown_choice: MinerChoice, owner_color: Color) -> void:
	if on_node != node:
		fade = 0.0
		node = on_node
		global_position = node.get_mount_position()
	wanted = true
	if not shown_choice.same_as(choice):
		choice = shown_choice
		_number.text = choice.crafted.plate() if choice.crafted else ""
		_show_parts()
		_strip.albedo_color = Color(
			Miner.COLOR_STANDARD_PLATE if choice.is_standard() else owner_color, 0.0
		)
	tint = FULL_SPEED_COLOR if choice.full_speed(node.ore_type) else TOO_SOFT_COLOR
	_ring_material.set_shader_parameter(&"color", Color(tint, RING_ALPHA))
	_ring_material.set_shader_parameter(
		&"share", clampf(choice.fill_time(node) / DIAL_TIME, 0.0, 1.0)
	)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and choice:
		_show_parts()


## Hides it at once (it's placed: the building hologram takes over).
func hide_now() -> void:
	wanted = false
	fade = 0.0
	visible = false
	node = null
	choice = null


## Every part as the preview hologram, the fill and the lamp hidden, the plate and a label on its
## side box.
func _dress_model() -> void:
	var material := ShaderMaterial.new()
	material.shader = preload("res://game/mining/miner_preview.gdshader")
	_plate = _model.get_node(^"Plate") as Node3D
	for part: String in ["Fill", "FullLamp"]:
		(_model.find_child(part, true, false) as Node3D).visible = false
	for found: Node in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh := found as MeshInstance3D
		if _plate.is_ancestor_of(mesh):
			continue
		mesh.material_override = material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_parts.append(mesh)
	RenderLayers.put(_model, RenderLayers.EFFECTS)
	_plate.visible = true
	_number = _plate.get_node(^"Number") as Label3D
	_strip.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_strip.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	(_plate.get_node(^"Strip") as MeshInstance3D).material_override = _strip
	_label = _number.duplicate() as Label3D
	_label.name = "Parts"
	_label.font_size = 40
	_label.outline_size = 10
	_label.position = Vector3(0.0, -0.3, 0.0)
	_plate.add_child(_label)


func _show_parts() -> void:
	_label.text = tr("Drill MK%d · Tank MK%d") % [choice.drill_mk(), choice.tank_mk()]


func _add_ring() -> void:
	var outer: float = RING_RADIUS + 0.25
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * outer * 2.0
	_ring.name = "Ring"
	_ring.mesh = plane
	_ring_material.shader = preload("res://assets/shaders/miner_preview_ring.gdshader")
	_ring_material.set_shader_parameter(&"radius", outer)
	_ring_material.set_shader_parameter(
		&"circle_band", Vector2(RING_RADIUS - RING_HALF_WIDTH, RING_RADIUS + RING_HALF_WIDTH)
	)
	_ring_material.set_shader_parameter(
		&"tick_band", Vector2(RING_RADIUS - 0.15, RING_RADIUS + 0.17)
	)
	_ring.material_override = _ring_material
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.layers = RenderLayers.MARKINGS
	_ring.position.y = 0.05
	add_child(_ring)
