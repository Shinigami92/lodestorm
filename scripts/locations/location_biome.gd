class_name LocationBiome
extends Resource
## What kind of place a generated location is: the shape and look of its ground, what grows and
## lies on it, which ores it has and how many nests. The mission picks it (later: the mission
## selection). All values are greybox, TBD (playtest).

@export var display_name: String = ""

@export_group("Ground")
## Height of the rolling hills (from the lowest valley to the highest top), in m.
@export var hill_height: float = 14.0
## Typical width of a hill, in m.
@export var hill_size: float = 160.0
## Height of one plateau step, in m: where the ground is terraced, it rises in flat steps with a
## cliff between them.
@export var plateau_step: float = 4.0
## Share of the ground that is terraced (0 to 1); the rest is smooth slopes that lead up and down.
@export_range(0.0, 1.0) var cliff_share: float = 0.5
## Height of the small bumps on top, in m.
@export var bump_height: float = 0.6
## The ground's material: usually the terrain shader (`assets/shaders/terrain.gdshader`) with the
## biome's texture sets. It gets the vertex colors: RGB a tint, A the share of scree.
@export var ground_material: Material
## Tint of the low ground, fading out towards the high ground (the hilltops are lighter).
@export var low_ground_tint: Color = Color(0.9, 0.9, 0.9)
## How much the ground's brightness varies over large areas (0: not at all, 0.1: by ±10%).
@export_range(0.0, 0.5) var tint_variation: float = 0.08
## How much loose scree lies at the foot of cliffs and slopes and in patches (0: none, 1: a lot).
@export_range(0.0, 1.0) var scree: float = 0.5

@export_group("Scatter")
@export var scatter: Array[ScatterType] = []

@export_group("Ores")
## Ore types from common to rare: rarer ones lie farther away from the ship.
@export var ores: Array[OreType] = []
## Number of ore fields; each has `ore_nodes_per_field` nodes of one type.
@export var ore_fields: int = 12
@export var ore_nodes_per_field: Vector2i = Vector2i(1, 3)

@export_group("Aliens")
@export var nests: int = 6
## Closest a nest is to the landing site, in m.
@export var nest_min_distance: float = 80.0
