class_name StarSystem
extends Resource
## The star system the campaign plays in: its planets, moons and stations, each with the regions
## the ship can land in (see GAME_DESIGN.md, Missions). Picked at the bridge's navigator.

## Player-facing name of the star.
@export var display_name: String = ""
@export var star_color: Color = Color(1.0, 0.85, 0.55)
@export var bodies: Array[CelestialBody] = []


## Every region the ship can land in with heat shield MK `shield_mk`, in order: those of the
## bodies it reaches (see `CelestialBody.is_reachable`).
func open_regions(shield_mk: int) -> Array[Region]:
	var open: Array[Region] = []
	for body: CelestialBody in bodies:
		if body.is_reachable(shield_mk):
			open.append_array(body.regions)
	return open


## Whether `region` can be landed in with heat shield MK `shield_mk`.
func is_open(region: Region, shield_mk: int) -> bool:
	var body: CelestialBody = body_of(region)
	return body != null and body.is_reachable(shield_mk)


## The body with `id`, or null.
func body_by_id(id: StringName) -> CelestialBody:
	for body: CelestialBody in bodies:
		if body.id == id:
			return body
	return null


## The ores a visit to `region` finds (see `Region.ores_on`), commonest first.
func ores_of(region: Region) -> Array[OreType]:
	return region.ores_on(body_of(region))


## The body `region` belongs to, or null.
func body_of(region: Region) -> CelestialBody:
	for body: CelestialBody in bodies:
		if region in body.regions:
			return body
	return null
