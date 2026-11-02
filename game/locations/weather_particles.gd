class_name WeatherParticles
extends Resource
## One kind of particles of a biome's weather (or the storm's), drawn around the viewer: sand
## drifting low, spores floating, snow or ash falling, embers rising, mist lying in the hollows,
## glints on the ground, heat shimmer. Kept small and sparse (VR draws them twice at 90 fps), so
## they never hide the player or compete with the ore. All values TBD (playtest).

## How the particles move and look.
enum Motion {
	## Falling from above, blown sideways by the wind (snow, ash).
	FALL,
	## Streaking low over the ground with the wind, stretched along it (drifting sand, the storm).
	DRIFT,
	## Floating and wandering slowly in the air (spores).
	FLOAT,
	## Rising from the ground, fading as they go (embers).
	RISE,
	## Flat sheets lying low on the ground, drifting slowly (mist in the hollows).
	MIST,
	## Specks on the ground flashing up for a moment (glints).
	GLINT,
	## Low wavering patches that bend the view behind them (heat shimmer).
	SHIMMER,
}

@export var motion: Motion = Motion.FALL
## How many are alive at once around the viewer.
@export_range(1, 4000, 1) var amount: int = 300
## Their color (alpha: how opaque); `glow` above 0 makes them emissive (embers, glints).
@export var color := Color(0.8, 0.8, 0.8, 0.5)
@export_range(0.0, 8.0, 0.05) var glow: float = 0.0
## Their size, smallest and largest, in m.
@export var size := Vector2(0.05, 0.1)
## How long one lives, in s.
@export_range(0.2, 30.0, 0.1) var lifetime: float = 6.0
## Their speed along their motion, in m/s (falling, drifting, rising).
@export_range(0.0, 40.0, 0.1) var speed: float = 1.0
## The wind's push sideways, in m/s (its direction is the weather's, the same for all kinds).
@export_range(0.0, 40.0, 0.1) var wind: float = 1.0
## How long a streak is compared to its width (`Motion.DRIFT`; 1: round).
@export_range(1.0, 20.0, 0.1) var stretch: float = 1.0
## How far around the viewer they appear, in m (half the box's side), and from which height to
## which, above the viewer's feet.
@export_range(2.0, 80.0, 0.5) var reach: float = 24.0
@export var heights := Vector2(0.0, 12.0)
