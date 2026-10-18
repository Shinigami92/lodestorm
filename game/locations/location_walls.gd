class_name LocationWalls
extends RefCounted
## The walls of a generated location (`LocationBiome.Barrier.WALLS`, or behind the gaps): rock
## beside the open ground, rising in a cliff nobody can climb and higher behind it, in flat layers,
## sharp ridges or slabs (`LocationBiome.RockShape`), higher beside slot canyons. On the camera's
## side it starts as a ledge and rises no steeper than the camera looks down, so the camera sees
## over it. Plain data, planned with the location.

## Share of the wall's height the cliff rises on its first grid square: much more than players
## can step up (`MAX_WALK_SLOPE`).
const FIRST_STEP: float = 0.6
## The least the cliff rises on its first grid square, in m (low walls on the camera's side too):
## more than players step up even where bumps and swells of the ground lean towards it.
const MIN_CLIFF_STEP: float = 3.0
## Share of the view's drop the rock on the camera's side rises at most, so the camera also sees
## a bit of the open ground beyond the cliff's foot.
const VIEW_MARGIN: float = 0.85
## How narrow the ridges are: their rock rises where the noise is within 1 / this of zero.
const RIDGE_SHARPNESS: float = 5.0
## How wide a slab is, about, in m (`LocationBiome.RockShape.SLABS`).
const SLAB_SIZE: float = 22.0

## Grid points on the rock on the camera's side of the open ground (1 = only low scatter).
var camera_side: PackedByteArray
## How much higher the rock rises at each grid point, in m (beside slot canyons); empty: nowhere.
var deeper: PackedFloat32Array

var _terrain: LocationTerrain
var _biome: LocationBiome
## Where the rock rises higher.
var _rock: FastNoiseLite
## Which slab a grid point lies on (`LocationBiome.RockShape.SLABS`): a value per slab.
var _slabs: FastNoiseLite
## Where the camera looks, location-local (see `GeneratedLocation.view_direction`).
var _view: Vector3


func _init(
	terrain: LocationTerrain, biome: LocationBiome, rock: FastNoiseLite, view: Vector3
) -> void:
	_terrain = terrain
	_biome = biome
	_rock = rock
	_view = view
	camera_side.resize(terrain.heights.size())
	if biome.rock_shape == LocationBiome.RockShape.SLABS:
		_slabs = rock.duplicate() as FastNoiseLite
		_slabs.noise_type = FastNoiseLite.TYPE_CELLULAR
		_slabs.fractal_type = FastNoiseLite.FRACTAL_NONE
		_slabs.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
		_slabs.cellular_jitter = 0.9
		_slabs.frequency = 1.0 / SLAB_SIZE


## How high the rock rises at grid point `x`, `z` above the open ground (0 on it; `outside`: the
## distance from it): a cliff nobody can climb, then the rock's shape (lower on the camera's side,
## see `_view_cap`), or a flat `top` (a butte's). Marks the rock on the camera's side.
func rise(x: int, z: int, outside: PackedFloat32Array, top: float = INF) -> float:
	var at: Vector3 = _terrain.point(x, z)
	var index: int = _terrain.index(x, z)
	var walls: float = share(outside[index])
	var rock_height: float = top
	if is_inf(top):
		rock_height = _biome.wall_height + _relief(Vector2(at.x, at.z))
		if not deeper.is_empty():
			rock_height += deeper[index]
		var cap: Vector2 = _view_cap(x, z, outside)
		rock_height = lerpf(rock_height, minf(rock_height, cap.x), cap.y)
		if walls > 0.0 and cap.y > 0.1:
			camera_side[index] = 1
	var lift: float = walls * rock_height
	if walls > 0.0:
		# However bumpy the ground, the first step onto the rock is too high to climb.
		lift = maxf(lift, minf(rock_height, MIN_CLIFF_STEP))
	return lift


## How much of the wall stands at `distance` m from the open ground: 0 on it, 1 on the rock. The
## first grid point off the open ground already has `FIRST_STEP` of it, so no step from the open
## ground onto the rock is walkable, however the grid lies along the cliff.
func share(distance: float) -> float:
	if distance <= 0.0:
		return 0.0
	var full: float = maxf(_biome.cliff_width, _terrain.cell * 1.5)
	return lerpf(FIRST_STEP, 1.0, smoothstep(_terrain.cell, full, distance))


## How high the rock at grid point `x`, `z` may rise so the camera sees over it to the open ground
## (`outside`: the distance from it), and how much that applies (by how much the rock lies on the
## camera's side): (height, weight); weight 0 without a view direction.
func _view_cap(x: int, z: int, outside: PackedFloat32Array) -> Vector2:
	var forward := Vector2(_view.x, _view.z)
	var distance: float = outside[_terrain.index(x, z)]
	if forward.length() < 0.01 or distance <= 0.0:
		return Vector2(INF, 0.0)
	# How much the view drops per m it goes forward.
	var drop: float = -_view.y / forward.length()
	var toward: Vector2 = Vector2(
		(
			outside[_terrain.index(maxi(x - 1, 0), z)]
			- outside[_terrain.index(mini(x + 1, _terrain.cells), z)]
		),
		(
			outside[_terrain.index(x, maxi(z - 1, 0))]
			- outside[_terrain.index(x, mini(z + 1, _terrain.cells))]
		)
	)
	if toward.length() < 0.001:
		return Vector2(INF, 0.0)
	var facing: float = toward.normalized().dot(forward.normalized())
	var weight: float = smoothstep(0.1, 0.5, facing)
	if weight <= 0.0:
		return Vector2(INF, 0.0)
	# Along the view, the open ground is this far ahead.
	var ahead: float = distance / maxf(facing, 0.3)
	return Vector2(_biome.near_wall_height + _terrace(drop * VIEW_MARGIN * ahead), weight)


## How much higher the rock rises at location-local `at`: in flat layers, in long, sharp spines
## along the rock noise's zero line, or a slab's level (from `rock_relief` below to the wall's
## height, `plateau_step` apart).
func _relief(at: Vector2) -> float:
	match _biome.rock_shape:
		LocationBiome.RockShape.RIDGES:
			var spine: float = maxf(1.0 - absf(_rock.get_noise_2dv(at)) * RIDGE_SHARPNESS, 0.0)
			return pow(spine, 1.5) * _biome.rock_relief
		LocationBiome.RockShape.SLABS:
			var levels: int = roundi(_biome.rock_relief / _biome.plateau_step) + 1
			var level: int = mini(
				floori((_slabs.get_noise_2dv(at) + 1.0) * 0.5 * levels), levels - 1
			)
			return level * _biome.plateau_step - _biome.rock_relief
	return _terrace(maxf(_rock.get_noise_2dv(at) + 0.2, 0.0) * _biome.rock_relief)


## Flat steps of `_biome.plateau_step`, with a steep rise between them.
func _terrace(height: float) -> float:
	var steps: float = height / _biome.plateau_step
	var base: float = floorf(steps)
	return (base + smoothstep(0.8, 1.0, steps - base)) * _biome.plateau_step
