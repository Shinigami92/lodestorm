class_name LocationBiome
extends Resource
## What kind of place a generated location is: how its areas and passes are laid out, the shape
## and look of its ground, what grows and lies on it, which ores it has and how many nests. The
## mission picks it (from the region). Besides its numbers, a biome is made by four things: its
## barrier (what keeps players out between the areas), its passes, its own kinds of areas and at
## most one hazard; the same layout generator serves every biome. All values are greybox, TBD
## (playtest).

## What keeps players out between the open areas.
enum Barrier {
	## High rock nobody can climb (`wall_height`).
	WALLS,
	## Ground lowered below the floor nobody can enter (crevasses): players and aliens see and
	## shoot across but walk around to the next pass. Its edge is blocked by invisible walls behind
	## a visible lip, so nobody falls in. Beyond it the ground comes back up to the floor's level.
	GAPS,
	## Gaps beside the open ground (lava channels, sinkholes) with the rock rising behind them.
	GAPS_AND_WALLS,
}

## The shape of the gaps beside the open ground.
enum GapShape {
	## Bands along the open ground's edge, their width varying (crevasses, lava channels).
	BANDS,
	## Round pits bitten into the barrier along the edge (sinkholes), the rock between them.
	PITS,
}

## The shape of the rock behind the cliffs.
enum RockShape {
	## Rising in flat layers (`plateau_step`): mesas.
	LAYERS,
	## Long, sharp spines.
	RIDGES,
	## Broken into slabs (`plateau_step` apart), one step below, at or above the open ground
	## nearest to them.
	SLABS,
}

## What the ways between the areas look like.
enum PassStyle {
	## Long, winding ways through the barrier.
	WINDING,
	## Short, straight crossings (snow bridges): the areas lie close together, at most
	## `longest_bridge` apart. Between areas at different levels (`terrace_step`) they ramp up.
	BRIDGES,
	## Slot canyons: narrow, S-shaped ways, the rock beside them `canyon_depth` higher than beside
	## the areas.
	SLOT_CANYONS,
}

## The one hazard of the biome's ground: mild, readable and avoidable, never in the landing yard or
## on a pass's lane, and it hinders aliens too.
enum Hazard {
	NONE,
	## Slick ice on the frozen lakes: feet grip less (`hazard_grip`), so players and aliens slide a
	## little when they start, turn and stop.
	SLICK_ICE,
	## Vents in the vent fields: they glow and rumble for a moment, then burst, hurting whoever
	## stands on them (`hazard_damage`).
	VENTS,
	## Glass shards on the ground in the shard gardens: they hurt whoever walks over them
	## (`hazard_damage` per second).
	SHARDS,
}

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
@export var pass_style: PassStyle = PassStyle.WINDING
## How much a pass's outline wobbles, relative to its half width.
@export_range(0.0, 0.5) var pass_wobble: float = 0.3
## Longest bridge (`PassStyle.BRIDGES`): the most open ground between two areas a pass crosses,
## in m.
@export var longest_bridge: float = 24.0
## How high a bridge's middle rises above the areas it joins, in m (raised causeways), with a ramp
## at each end.
@export var bridge_rise: float = 0.0
## How much higher the rock beside a slot canyon rises than beside the areas, in m
## (`PassStyle.SLOT_CANYONS`).
@export var canyon_depth: float = 0.0
## Terraces: every area lies on a slab of its own level, this many m apart (a level between one
## step below and two above the landing yard, at most one step from the areas its passes lead
## to), and the passes ramp between them. 0: no levels.
@export var terrace_step: float = 0.0

@export_group("Barrier")
@export var barrier: Barrier = Barrier.WALLS
@export var gap_shape: GapShape = GapShape.BANDS
## How wide a gap is beside the open ground (narrowest, widest), in m; a pit's radius. Farther out
## the ground comes back up to the floor's level (land nobody reaches), up to the rim at the edges,
## or the rock rises (`Barrier.GAPS_AND_WALLS`).
@export var gap_width: Vector2 = Vector2(10.0, 16.0)
## How deep a gap is below the floor, in m.
@export var gap_depth: float = 9.0
## How high the lip along a gap's edge rises, in m.
@export var lip_height: float = 0.4
## Tint of a gap's bottom (deeper ground fades towards it) and of the lips and bridges.
@export var gap_tint: Color = Color(0.3, 0.38, 0.5)
@export var lip_tint: Color = Color(1.0, 1.0, 1.0)
## What fills the gaps up to `gap_fill_level` above their bottom (lava, brine): a flat surface,
## only looks (null: nothing). The gaps' bottom is level then.
@export var gap_fill: Material
@export var gap_fill_level: float = 1.0
## What stands along the gaps' edges, on the walls there (shard fences): only looks, drawn many
## times (null: nothing).
@export var fence: Mesh

@export_group("Areas")
## Kinds of areas only this biome has (`LocationLayout.Kind`), on top of the shared ones.
@export var area_kinds: Array[LocationLayout.Kind] = []
## How many of each of them a layout has, per area.
@export var area_kinds_per_area: float = 0.1

@export_group("Hazard")
@export var hazard: Hazard = Hazard.NONE
## How well feet grip on the hazard's ground: the share of the usual acceleration.
@export_range(0.0, 1.0) var hazard_grip: float = 0.15
## Tint of the hazard's ground, so it reads from afar.
@export var hazard_tint: Color = Color(0.75, 0.9, 1.0)
## Damage the hazard deals to whoever stands in it: a vent's burst, the shards' per second.
@export var hazard_damage: float = 0.0

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
@export var rock_shape: RockShape = RockShape.LAYERS
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


## Whether its barrier has gaps.
func has_gaps() -> bool:
	return barrier != Barrier.WALLS


## Whether rock rises beyond the open ground (walls, or rock behind the gaps).
func has_walls() -> bool:
	return barrier != Barrier.GAPS
