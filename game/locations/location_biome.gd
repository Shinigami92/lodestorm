class_name LocationBiome
extends Resource
## What kind of place a generated location is: how its areas and passes are laid out, the shape
## and look of its ground, what grows and lies on it, which ores it has and how many nests. The
## mission picks it (from the region). All values are greybox, TBD (playtest).

@export var display_name: String = ""
## Its color on the navigator's globes: muted, like its ground, so the regions' danger borders
## and the ores' badges stand out.
@export var map_color: Color = Color(0.6, 0.6, 0.6)

@export_group("Layout")
## Radius of an open area (smallest, largest), in m.
@export var area_radius: Vector2 = Vector2(18.0, 38.0)
## Width of a pass between areas (narrowest, widest), in m.
@export var pass_width: Vector2 = Vector2(9.0, 16.0)
## Rock between two areas at least, in m.
@export var area_spacing: float = 16.0
## How far the areas spread: the side of the square they lie in is this times the square root of
## their number, in m.
@export var area_spread: float = 85.0
## Loops per area (a share of the areas): passes that lead around instead of to a dead end.
@export var loops_per_area: float = 0.2

@export_group("Ground")
## Height of the gentle swells on the open ground, in m.
@export var floor_relief: float = 2.0
## Typical width of a swell, in m.
@export var floor_relief_size: float = 60.0
## How high the rock rises above the open ground at least, in m: its cliffs nobody can climb.
@export var wall_height: float = 8.0
## Width of the cliff between the open ground and the rock, in m (steep: much less than the wall's
## height).
@export var cliff_width: float = 4.0
## How high the rock on the camera's side of the open ground rises at first, in m: a ledge
## nobody can climb either; behind it, it rises no steeper than the camera looks down (see
## `GeneratedLocation.view_direction`).
@export var near_wall_height: float = 3.5
## How much higher the rock rises in places beyond the walls, in m.
@export var rock_relief: float = 10.0
## Height of one step of the rock, in m: it rises in flat layers.
@export var plateau_step: float = 4.0
## Height of the small bumps on top, in m.
@export var bump_height: float = 0.6
## The ground's material: usually the terrain shader (`assets/shaders/terrain.gdshader`) with the
## biome's texture sets. It gets the vertex colors: RGB a tint, A the share of scree.
@export var ground_material: Material
## Tint of the low ground, fading out towards the high ground (the rock's top is lighter).
@export var low_ground_tint: Color = Color(0.9, 0.9, 0.9)
## How much the ground's brightness varies over large areas (0: not at all, 0.1: by ±10%).
@export_range(0.0, 0.5) var tint_variation: float = 0.08
## How much loose scree lies at the foot of cliffs and slopes and in patches (0: none, 1: a lot).
@export_range(0.0, 1.0) var scree: float = 0.5

@export_group("Scatter")
@export var scatter: Array[ScatterType] = []

@export_group("Points of interest")
## Map parts its locations pick their points of interest from.
@export var part_pool: Array[PartPlacement] = []
## Points of interest per area (besides the region's set pieces).
@export var parts_per_area: float = 0.25

@export_group("Ores")
## Ore types from common to rare: rarer ones lie farther away from the ship.
@export var ores: Array[OreType] = []
## Ore fields per area; each has `ore_nodes_per_field` nodes of one type.
@export var ore_fields_per_area: float = 1.1
@export var ore_nodes_per_field: Vector2i = Vector2i(1, 3)

@export_group("Aliens")
## Nests per area (scaled by the mission's difficulty).
@export var nests_per_area: float = 0.9
## Closest a nest is to the landing site along the passes, in m (in a straight line, through the
## rock, it may be a bit closer: `GeneratedLocation.NEST_STRAIGHT_SHARE`).
@export var nest_min_distance: float = 80.0
