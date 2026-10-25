class_name CelestialBody
extends Resource
## A planet, moon or station of the star system, with the regions the ship can land in. A station
## is a handcrafted map (`map`) the ship docks at, from the start (no tier); one without a map
## can't be docked at yet. A gas giant has no regions: the ship lands on its moons.

## Saved by number in resources: add new kinds at the end.
enum Kind { PLANET, MOON, STATION, GAS_GIANT }

## A body's highest MK level is its tier plus this (see `max_mk`).
const MK_ABOVE_TIER: int = 2

## Stable name for saves (where the ship is), unique in its star system.
@export var id: StringName = &""
## Player-facing name.
@export var display_name: String = ""
## What people call it in passing, e.g. "Ostra" for Waypost Ostra (highlighted in spoken lines
## like its name, see `Keywords`); empty: only its full name.
@export var short_name: String = ""
@export var kind: Kind = Kind.PLANET
## How dangerous it is, growing from the outermost planet (1) inwards; a moon has its planet's.
## The ship's heat shield needs this MK level to reach it (see `HeatShield`). Scales its aliens and
## its storm (see `Mission.tier`) and sets its highest MK level (`max_mk`).
@export_range(1, 6, 1, "or_greater") var tier: int = 1
## Its color in the navigator's hologram.
@export var color: Color = Color(0.5, 0.6, 0.7)
## Its size in the system view, relative to the others.
@export var size: float = 1.0
## Where it sits in the system view: distance from the star (relative) and angle in degrees. A
## moon sits around the body it orbits (`orbits`) instead.
@export var orbit_radius: float = 1.0
@export var orbit_angle: float = 0.0
## The body a moon or station orbits, or null (it orbits the star).
@export var orbits: CelestialBody
## Where the ship can land.
@export var regions: Array[Region] = []
## Its own rare ores (usually one), found in all its regions and nowhere else. A moon has its own
## or none.
@export var signature_ores: Array[OreType] = []
## A station's map (a `SpaceStation` scene), docked at instead of landing; null: no docking yet.
@export var map: PackedScene


## The highest MK level of upgrades it brings: reaching it makes them buyable, and in co-op stronger
## gear counts as this level here (the tier sync, later; see GAME_DESIGN.md, Co-op progression).
func max_mk() -> int:
	return tier + MK_ABOVE_TIER


## Its kind's name, translated.
func kind_name() -> String:
	match kind:
		Kind.MOON:
			return tr("Moon")
		Kind.STATION:
			return tr("Station")
		Kind.GAS_GIANT:
			return tr("Gas giant")
	return tr("Planet")


## Whether the ship can go there with heat shield MK `shield_mk`: its tier is at most that, and
## it has regions to land in (a gas giant has none); a station whenever it has a map to dock at.
func is_reachable(shield_mk: int) -> bool:
	if kind == Kind.STATION:
		return map != null
	return tier <= shield_mk and not regions.is_empty()


## Whether the ship docks there instead of landing: a station with a map.
func is_dockable() -> bool:
	return kind == Kind.STATION and map != null
