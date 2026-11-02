class_name BiomeWeather
extends Resource
## A biome's weather, on top of its body's light (`BodyLight`): its haze in the distance, the mist
## in its hollows, the tint it gives the ambient light and the sky, what hangs overhead and the
## particles around the viewer. Cheap enough for VR: depth fog and a few particle kinds. The
## storm takes over at the end (`Weather`). All values TBD (playtest).

## The haze's color, and how much it covers the distance (0–1): clear near the camera (from
## `haze_begin`), thickest from `haze_end`, so the far land fades into it and the view around the
## player stays clear.
@export var haze_color := Color(0.3, 0.27, 0.25)
@export_range(0.0, 1.0, 0.01) var haze: float = 0.3
@export var haze_begin: float = 70.0
@export var haze_end: float = 400.0
## How much the haze lights up towards the sun (glare off a bright crust; 0: not at all).
@export_range(0.0, 1.0, 0.01) var glare: float = 0.0
## Mist lying in the hollows: everything below this height (relative to the landing site) fades
## into the haze's color, thicker the deeper (`mist_density` per m); 0 density: no mist.
@export var mist_height: float = -1.0
@export_range(0.0, 1.0, 0.01) var mist_density: float = 0.0
## Tints the body's ambient light (white: unchanged).
@export var ambient_tint := Color(1.0, 1.0, 1.0)
## Overhead: the color of the cloud, ash or snow layer in the sky and how much of it covers it
## (0: clear).
@export var cloud_color := Color(0.2, 0.19, 0.18)
@export_range(0.0, 1.0, 0.01) var cloud_cover: float = 0.0
## The wind's compass direction, in degrees (the particles drift with it).
@export_range(-180.0, 180.0, 1.0, "degrees") var wind_bearing: float = 60.0
## The particles around the viewer.
@export var particles: Array[WeatherParticles] = []
## The far ring of land beyond the map (`LocationFarRing`): its ground's and its rock's colors,
## matching the biome's textures from afar.
@export var far_ground_color := Color(0.3, 0.27, 0.23)
@export var far_rock_color := Color(0.36, 0.32, 0.28)
