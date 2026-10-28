class_name LandingRing
extends MeshInstance3D
## A ring on the ground where the weapon's next lobbed shot lands (Tremor's blast, Wick's charge,
## see `LobDelivery`), as wide as its blast or the charge's reach. Only the local player holding
## the weapon sees it, while it's drawn and they may use it. A child of the weapon's scene.

## Width of the ring (m).
const WIDTH: float = 0.08

## The ring's color.
@export var color := Color(1.0, 0.62, 0.28)

var _material := StandardMaterial3D.new()
var _torus := TorusMesh.new()

@onready var _weapon: Weapon = owner as Weapon


func _ready() -> void:
	top_level = true
	layers = RenderLayers.MARKINGS
	_material.albedo_color = Color(color, 0.6)
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_torus.rings = 40
	_torus.ring_segments = 4
	_torus.material = _material
	mesh = _torus
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false


func _process(_delta: float) -> void:
	visible = _shown()
	if not visible:
		return
	var delivery := _weapon.type.delivery as LobDelivery
	var radius: float = delivery.ring_radius(_weapon)
	if not is_equal_approx(_torus.outer_radius, radius):
		_torus.outer_radius = radius
		_torus.inner_radius = radius - WIDTH
	global_transform = Transform3D(
		Basis.from_scale(Vector3(1.0, 0.15, 1.0)),
		delivery.landing_point(_weapon) + Vector3.UP * 0.06
	)


func _shown() -> bool:
	if not _weapon or not _weapon.type or not _weapon.type.delivery is LobDelivery:
		return false
	var player := _weapon.holder as Player
	return (
		player != null
		and player.local
		and player.weapon_allowed
		and not player.fallen
		and _weapon.is_drawn()
		and _weapon.is_visible_in_tree()
	)
