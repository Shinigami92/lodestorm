class_name ItemType
extends Resource
## Anything a player keeps in their hold: ores (`OreType`), later the refinery's alloys. Each is
## recognizable at a glance by its color, its shape (an ore's crystal, its badge's icon) and its
## glow pattern (`glow`) together, so telling them apart never depends on color alone. Costs, the
## hold (`PlayerHold`), cards (`ItemBadge`, `ItemCost`) and tests handle every kind the same way.

## How its glow changes over time (and over the crystal). Nothing flashes faster than 3 times a
## second (photosensitivity).
enum Glow {
	STEADY,
	SLOW_PULSE,
	FAST_PULSE,
	FLICKER,
	WAVE,
	SPARKLE,
	BREATHING,
	HEARTBEAT,
	SHIFTING,
}

## Player-facing name (invented, like the ores' mineral names), translated.
@export var display_name: String = ""
## Strong, distinct color of its glow: on everything filled with it and its badge on holo cards.
@export var color: Color = Color.WHITE
@export var glow: Glow = Glow.STEADY
## Near-black with glowing veins in `color`, instead of glowing all over.
@export var dark_body: bool = false
## Badge icon: a white silhouette with grey facets, tinted in `color` (see `ItemBadge`).
@export var icon: Texture2D

var _glow_material: Material


## Shared material for everything filled with it (an ore's miner column, hose and canisters): its
## color and the glow pattern's rhythm.
func get_glow_material() -> Material:
	if not _glow_material:
		_glow_material = OreGlow.fill_material(self)
	return _glow_material


## Its translated name.
func get_display_name() -> String:
	return tr(display_name)
