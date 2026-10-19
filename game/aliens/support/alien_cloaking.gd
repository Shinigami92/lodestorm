class_name AlienCloaking
extends Node
## A stalker's see-through body (`AlienStrain.cloak`, a child of its `Alien`): while no player is
## within its cloak's `reveal_range` it can't be seen or locked on (only its silhouette behind
## cliffs shows), closer it's a shimmer bending what's behind it (`cloak.gdshader`), its eyes a
## faint glint. Once it starts an attack or takes a hit it shows fully for `shown_time`. While it
## hides, its body casts no shadow and has no rim light. Shots and swings hit it all the same.
## Greybox look, TBD (playtest).

const SHADER: Shader = preload("res://game/aliens/support/cloak.gdshader")
## How much its eyes and glands show in the shimmer.
const GLINT: float = 0.35

var cloak: AlienCloak
## 0: hidden or a shimmer, 1: fully seen (fading between).
var shown: float = 0.0
## 0: unseen, 1: a shimmer (fading between).
var shimmer: float = 0.0

var _shown_left: float = 0.0
var _alien: Alien
var _creature: GeometryInstance3D
var _glowing: Array[GeometryInstance3D] = []
var _material := ShaderMaterial.new()


func _ready() -> void:
	_alien = get_parent() as Alien
	var model: Node = _alien.get_node(^"Body/Model")
	_creature = model.find_child("Creature", true, false) as GeometryInstance3D
	for part: String in ["Eyes", "Glands"]:
		var glowing := model.find_child(part, true, false) as GeometryInstance3D
		if glowing:
			_glowing.append(glowing)
	_material.shader = SHADER
	_material.set_shader_parameter(&"bend", cloak.bend)
	var mesh: Mesh = (_creature as MeshInstance3D).mesh
	var base := mesh.surface_get_material(0) as BaseMaterial3D
	if base:
		_material.set_shader_parameter(&"albedo_texture", base.albedo_texture)
	_alien.hit_taken.connect(_on_hit_taken)
	_update_look()


func _process(delta: float) -> void:
	_shown_left = maxf(_shown_left - delta, 0.0)
	var step: float = delta / cloak.fade_time
	var showing: bool = _shown_left > 0.0 or _alien.dead
	shown = move_toward(shown, 1.0 if showing else 0.0, step)
	shimmer = move_toward(shimmer, 1.0 if _player_near() else 0.0, step)
	_update_look()


## Shows it fully for its cloak's `shown_time` (it attacks, it's hit).
func reveal() -> void:
	_shown_left = cloak.shown_time


## Whether it can't be seen or locked on: hidden, no player close enough.
func is_hidden() -> bool:
	return shown < 0.5 and shimmer < 0.5 and _shown_left == 0.0


## Whether it hides at all right now (shimmering or unseen): no rim light.
func is_cloaked() -> bool:
	return shown < 1.0


## Whether a living player outside is within the reveal range.
func _player_near() -> bool:
	for player: Player in _alien.get_tree().get_nodes_in_group(Player.GROUP):
		if Alien.is_prey(_alien.get_tree(), player):
			if _alien.horizontal_distance(player) <= cloak.reveal_range:
				return true
	return false


func _update_look() -> void:
	var override: Material = _material if is_cloaked() else null
	if _creature.material_override != override:
		_creature.material_override = override
	_creature.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if shown >= 0.5
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	_material.set_shader_parameter(&"shown", shown)
	_material.set_shader_parameter(&"shimmer", shimmer)
	for glowing: GeometryInstance3D in _glowing:
		glowing.transparency = 1.0 - maxf(shown, GLINT * shimmer)


func _on_hit_taken(_hit: Hit, _dealt: float, _armored: bool) -> void:
	reveal()
