class_name BodyLight
extends Resource
## How a body's outside looks under the star Kesh: its sun, its ambient light and its sky. Far out
## a weak, cool, low sun with long soft shadows and the star small and pale in the sky; inwards
## stronger, whiter and higher, with hard short shadows, the star big and harsh, its flares as
## glare. The biome adds its fog, ambient tint and weather on top (`BiomeWeather`), the storm dims
## it (`Weather`). A moon also sees the body it orbits large in its sky. All values TBD (playtest).

## The sun's color and energy (the light keeps muted: ore, aliens and lamps must stay brighter).
@export var sun_color := Color(1.0, 0.88, 0.74)
@export_range(0.0, 3.0, 0.01) var sun_energy: float = 0.75
## How high the sun stands above the horizon, in degrees: low far out (long shadows), high
## inwards (short ones). Its compass direction stays the same everywhere, so the shadows fall the
## same way relative to the camera.
@export_range(5.0, 85.0, 0.5, "degrees") var sun_elevation: float = 50.0
## How soft the shadows' edges are (the shadow filter's blur; 1: the project's default).
@export_range(0.0, 4.0, 0.05) var shadow_softness: float = 1.0
## The ambient light outside (no sky ambient: the dark sky would leave the ground black). Its
## energy never drops below the darkness floor (`Weather.min_ambient_energy`).
@export var ambient_color := Color(0.42, 0.46, 0.55)
@export_range(0.0, 2.0, 0.01) var ambient_energy: float = 0.5

@export_group("Sky")
## The sky straight up and at the horizon (the biome's haze tints the horizon).
@export var zenith_color := Color(0.05, 0.05, 0.07)
@export var horizon_color := Color(0.16, 0.15, 0.16)
## The star Kesh: its disc's width in degrees and its color; a glow around it.
@export_range(0.1, 20.0, 0.05, "degrees") var star_size: float = 1.0
@export var star_color := Color(1.0, 0.95, 0.85)
## Kesh's flares: rays and a wide glare around the disc (0: none, far out; 1: harsh, inwards).
@export_range(0.0, 1.0, 0.01) var star_glare: float = 0.0
## A moon's planet in its sky (the body it `orbits`, in that body's color): its width in degrees
## (0: none) and where it stands, as compass angle (degrees from the sun's) and height above the
## horizon.
@export_range(0.0, 120.0, 0.5, "degrees") var planet_size: float = 0.0
@export_range(-180.0, 180.0, 1.0, "degrees") var planet_bearing: float = 140.0
@export_range(0.0, 90.0, 0.5, "degrees") var planet_elevation: float = 30.0
