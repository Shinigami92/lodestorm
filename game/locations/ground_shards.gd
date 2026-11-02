class_name GroundShards
extends GroundHazard
## A patch of glass shards on the ground (the Glass plains' hazard, see
## `LocationBiome.Hazard.SHARDS`): it hurts every player and alien walking over it, a little every
## `TICK` s. Readable and avoidable: the ground under it has its own tint and splinters lie on it.
## Steps on it crunch (`step_sound`). What lies on it is a model (`pieces`: patches of splinters);
## without one, greybox slivers. All values TBD (playtest).

## How often it hurts, in s.
const TICK: float = 0.5
## Slivers per m² of the patch.
const SLIVERS_PER_M2: float = 1.5
## Pieces (`pieces`, about 1 m across each) per m² of the patch.
const PIECES_PER_M2: float = 0.45
const SLIVER_COLOR := Color(0.62, 0.86, 0.9)

## Damage per second to whoever stands on it.
@export var damage_per_second: float = 4.0
## How far the patch reaches, in m (the slivers; the collision shape is set by whoever adds it).
@export var radius: float = 2.5
## What lies on the patch, drawn many times flat on the ground (null: greybox slivers).
@export var pieces: Mesh

## Time until it hurts next, in s.
var _until_hurt: float = TICK


func _ready() -> void:
	super()
	if not step_sound:
		step_sound = preload("res://assets/audio/sfx/player/step_shards.tres")
	_build()


func _physics_process(delta: float) -> void:
	_until_hurt -= delta
	if _until_hurt <= 0.0:
		_until_hurt += TICK
		hurt(damage_per_second * TICK)


func _build() -> void:
	# The same patch looks the same every time (it lies where the location's seed put it).
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(roundi(position.x * 10.0), roundi(position.z * 10.0)))
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	if pieces:
		_lay_pieces(multimesh, rng)
	else:
		_lay_slivers(multimesh, rng)
	var slivers := MultiMeshInstance3D.new()
	slivers.name = "Slivers"
	slivers.multimesh = multimesh
	slivers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(slivers)


## The model's pieces, lying flat, turned and sized at random, spread over the patch.
func _lay_pieces(multimesh: MultiMesh, rng: RandomNumberGenerator) -> void:
	var count: int = maxi(2, roundi(PI * radius * radius * PIECES_PER_M2))
	multimesh.mesh = pieces
	multimesh.instance_count = count
	for i: int in count:
		var at: Vector2 = Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * radius * 0.85
		var turn := Basis(Vector3.UP, rng.randf() * TAU)
		var grown: float = rng.randf_range(0.7, 1.2)
		multimesh.set_instance_transform(
			i, Transform3D(turn.scaled(Vector3.ONE * grown), Vector3(at.x, 0.0, at.y))
		)


## Greybox: thin glass prisms lying about, poking up a little.
func _lay_slivers(multimesh: MultiMesh, rng: RandomNumberGenerator) -> void:
	var sliver := PrismMesh.new()
	sliver.size = Vector3(0.12, 0.5, 0.06)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = SLIVER_COLOR
	glass.metallic = 0.4
	glass.roughness = 0.12
	glass.emission_enabled = true
	glass.emission = SLIVER_COLOR
	glass.emission_energy_multiplier = 0.25
	sliver.material = glass
	var count: int = maxi(4, roundi(PI * radius * radius * SLIVERS_PER_M2))
	multimesh.mesh = sliver
	multimesh.instance_count = count
	for i: int in count:
		var at: Vector2 = Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * radius
		var lean: float = deg_to_rad(rng.randf_range(50.0, 80.0))
		var turn := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, lean)
		var grown: float = rng.randf_range(0.6, 1.4)
		multimesh.set_instance_transform(
			i, Transform3D(turn.scaled(Vector3.ONE * grown), Vector3(at.x, 0.08, at.y))
		)
