class_name LocationBiome
extends Resource
## What kind of place a generated location is: the shape and colors of its ground, what grows and
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
@export var ground_color: Color = Color(0.5, 0.45, 0.38)
## Ground color on the high ground (blends in with the height).
@export var high_ground_color: Color = Color(0.58, 0.52, 0.42)
@export var cliff_color: Color = Color(0.36, 0.32, 0.3)

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
