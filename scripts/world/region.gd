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
