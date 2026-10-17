class_name CelestialBody
extends Resource
## A planet, moon or station of the star system, with the regions the ship can land in. Stations
## are handcrafted maps (later); until they exist they can't be docked at. A gas giant has no
## regions: the ship lands on its moons.

## Saved by number in resources: add new kinds at the end.
enum Kind { PLANET, MOON, STATION, GAS_GIANT }

## Player-facing name.
@export var display_name: String = ""
@export var kind: Kind = Kind.PLANET
## How dangerous it is, growing from the outermost planet (1) inwards; a moon has its planet's.
## Scales its aliens and caps the MK levels in co-op (later, see GAME_DESIGN.md, Co-op
## progression).
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


## Whether the ship can go there now: a station can't be docked at yet, a body needs an open
## region.
func is_reachable() -> bool:
	if kind == Kind.STATION:
		return false
	for region: Region in regions:
		if region.unlocked:
			return true
	return false
