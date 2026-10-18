class_name GroundMud
extends GroundHazard
## A mud pool in a mire (the Overgrowth's hazard, see `LocationBiome.Hazard.MUD`): players and
## aliens walk slower in it (`speed`); the dash isn't slowed. Readable and avoidable: the pool lies
## a bit lower than its shore, its wet surface shines. Greybox: a flat, glossy sheet fading out at
## its edge; the squelch comes with the sound effects. All values TBD (playtest).

## How high the surface lies above the pool's level ground, in m, and how far inside the pool's edge
## it fades out (so it stays off the shore, which would cut it in the ground's grid squares).
const SURFACE_HEIGHT: float = 0.04
const SURFACE_INSET: float = 0.3
## How far the surface fades out towards its edge, relative to its radius.
const SURFACE_FADE: float = 0.35

## How far the pool reaches, in m (the surface; the collision shape is set by whoever adds it).
@export var radius: float = 5.0
## The mud's color (the surface is a bit darker, and wet).
@export var color: Color = Color(0.25, 0.2, 0.14)


func _ready() -> void:
	super()
	_build()


func _build() -> void:
	# A square with a round, wet sheet on it that fades out towards its edge.
	var sheet := Gradient.new()
	sheet.set_color(0, Color(1.0, 1.0, 1.0, 0.85))
	sheet.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	sheet.add_point(1.0 - SURFACE_FADE, Color(1.0, 1.0, 1.0, 0.85))
	var fade := GradientTexture2D.new()
	fade.gradient = sheet
	fade.fill = GradientTexture2D.FILL_RADIAL
	fade.fill_from = Vector2(0.5, 0.5)
	fade.fill_to = Vector2(0.5, 0.0)
	var wet := StandardMaterial3D.new()
	wet.albedo_color = color.darkened(0.15)
	wet.albedo_texture = fade
	wet.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wet.roughness = 0.45
	wet.metallic_specular = 0.15
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * maxf(radius - SURFACE_INSET, 0.5) * 2.0
	plane.material = wet
	var surface := MeshInstance3D.new()
	surface.name = "Surface"
	surface.mesh = plane
	surface.position.y = SURFACE_HEIGHT
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(surface)
