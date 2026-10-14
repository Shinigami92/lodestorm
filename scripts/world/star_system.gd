class_name StarSystem
extends Resource
## The star system the campaign plays in: its planets, moons and stations, each with the regions
## the ship can land in (see GAME_DESIGN.md, Missions). Picked at the bridge's navigator.

## Player-facing name of the star.
@export var display_name: String = ""
@export var star_color: Color = Color(1.0, 0.85, 0.55)
@export var bodies: Array[CelestialBody] = []


## Every region the ship can land in now, in order.
func open_regions() -> Array[Region]:
	var open: Array[Region] = []
	for body: CelestialBody in bodies:
		if body.kind == CelestialBody.Kind.STATION:
			continue
		for region: Region in body.regions:
			if region.unlocked:
				open.append(region)
	return open


## The body `region` belongs to, or null.
func body_of(region: Region) -> CelestialBody:
	for body: CelestialBody in bodies:
		if region in body.regions:
			return body
	return null
