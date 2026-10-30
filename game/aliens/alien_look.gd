class_name AlienLook
extends RefCounted
## How an alien's model looks beyond its pose (`Alien`'s helper): the hit flash and the rim light
## laid over it, seen behind cliffs as a red silhouette, a little bigger and outlined in the hive's
## yellow-green while a scream boosts it or a tender's link holds it (`AlienStatus.is_buffed`),
## and its eyes and glands (the model's `Eyes` and `Glands`) flaring during a wind-up and while
## it's faster than its strain.

## How much brighter the eyes glow when fully crouched for an attack, and while it's faster than
## its strain (a scream's boost, the hive's frenzy).
const EYE_FLARE: float = 4.0
const EYE_FLARE_FAST: float = 0.8
## The rim light is weaker than on players and machines: the alien's many thin, curved parts
## would glow all over.
const RIM_STRENGTH: float = 0.45
## While buffed: how much bigger it gets, how fast it grows and shrinks back (per second), and its
## outline's strength.
const BUFFED_SCALE: float = 1.15
const BUFFED_GROW_SPEED: float = 6.0
const BUFFED_RIM_STRENGTH: float = 1.6
## A hit flash covers the model in white.
const COLOR_FLASH := Color(1.0, 1.0, 1.0, 0.85)
## Seconds a hit flash lasts.
const FLASH_DURATION: float = 0.1

## Shared by all aliens (see `RIM_STRENGTH`).
static var _rim: ShaderMaterial
static var _buffed_rim: ShaderMaterial

var _alien: Alien
var _model: Node3D
## Laid over the model: the hit flash, and the rim light as its next pass.
var _overlay := StandardMaterial3D.new()
## The eyes' and glands' own materials, flaring during a wind-up, and their usual energy.
var _glows: Array[BaseMaterial3D] = []
var _glow_energies: Array[float] = []
var _flash_left: float = 0.0


## Sets up `alien`'s `model`, whose body's mesh is `creature`.
func _init(alien: Alien, model: Node3D, creature: GeometryInstance3D) -> void:
	_alien = alien
	_model = model
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if not _rim:
		_rim = preload("res://assets/shaders/rim_light.tres").duplicate() as ShaderMaterial
		_rim.set_shader_parameter(&"strength", RIM_STRENGTH)
		_buffed_rim = _rim.duplicate() as ShaderMaterial
		_buffed_rim.set_shader_parameter(&"color", Alien.COLOR_GLOW)
		_buffed_rim.set_shader_parameter(&"strength", BUFFED_RIM_STRENGTH)
	_overlay.next_pass = _rim
	creature.material_overlay = OccludedSilhouette.overlay(OccludedSilhouette.ALIEN_COLOR, _overlay)
	OccludedSilhouette.mark_visible(model)
	RenderLayers.put(model, RenderLayers.CHARACTERS)
	for part: String in ["Eyes", "Glands"]:
		var glowing := model.find_child(part, true, false) as MeshInstance3D
		if glowing and glowing.mesh.surface_get_material(0) is BaseMaterial3D:
			var glow := glowing.mesh.surface_get_material(0).duplicate() as BaseMaterial3D
			_glows.append(glow)
			_glow_energies.append(glow.emission_energy_multiplier)
			glowing.material_override = glow


## Flashes it white (a hit).
func flash() -> void:
	_flash_left = FLASH_DURATION


## Moves the look on by `delta` seconds, `winding` (0 to 1) into a wind-up.
func update(delta: float, winding: float) -> void:
	_flash_left = maxf(_flash_left - delta, 0.0)
	var status: AlienStatus = _alien.status
	var buffed: bool = status.is_buffed() and not _alien.dead
	var size: float = BUFFED_SCALE if buffed else 1.0
	_model.scale = _model.scale.lerp(Vector3.ONE * size, 1.0 - exp(-BUFFED_GROW_SPEED * delta))
	var rim: ShaderMaterial = _buffed_rim if buffed else _rim
	if _alien.cloaking and _alien.cloaking.is_cloaked():
		rim = null
	# Only on a change: every change updates the material on the renderer.
	if _overlay.next_pass != rim:
		_overlay.next_pass = rim
	var shade: Color = COLOR_FLASH if _flash_left > 0.0 else Color(0.0, 0.0, 0.0, 0.0)
	if _overlay.albedo_color != shade:
		_overlay.albedo_color = shade
	var fast: float = EYE_FLARE_FAST if status.is_fast() else 0.0
	var flare: float = (1.0 + fast + EYE_FLARE * winding) * status.eye_glow()
	for i: int in _glows.size():
		if _glows[i].emission_energy_multiplier != _glow_energies[i] * flare:
			_glows[i].emission_energy_multiplier = _glow_energies[i] * flare
