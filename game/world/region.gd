class_name Region
extends Resource
## A fixed region of a planet or moon (like a country): its biome, how dangerous it is and how long
## a run there lasts. Every visit generates a new section of it (a new seed, see `MissionBrief`);
## later its handcrafted set pieces (landmarks, quest sites) are placed in that section.

## Player-facing name.
@export var display_name: String = ""
@export var biome: LocationBiome
## Sets how many of the biome's nests a visit has (see `MissionSettings.nest_factors`).
@export var danger: MissionBrief.Difficulty = MissionBrief.Difficulty.NORMAL
## The timer, relative to the standard mission (`MissionSettings.duration`). TBD (playtest).
@export var length: float = 1.0
## Where its marker sits on the body's globe: latitude and longitude in degrees.
@export var globe_position: Vector2 = Vector2.ZERO
## Whether it can be visited yet (later unlocked by the story or quests).
@export var unlocked: bool = true
## Ores found here besides its biome's and its body's (e.g. for a quest site).
@export var extra_ores: Array[OreType] = []
## Ores of its biome or body that aren't found here.
@export var missing_ores: Array[OreType] = []


## The ores a visit finds here, commonest first: its biome's (common and mid ores), its `body`'s
## signature ores and its extra ores, without the missing ones.
func ores_on(body: CelestialBody) -> Array[OreType]:
	var found: Array[OreType] = []
	var sources: Array[Array] = [extra_ores]
	if biome:
		sources.push_front(biome.ores)
	if body:
		sources.insert(sources.size() - 1, body.signature_ores)
	for source: Array in sources:
		for ore_type: OreType in source:
			if ore_type not in found and ore_type not in missing_ores:
				found.append(ore_type)
	return OreCatalog.sorted(found)
