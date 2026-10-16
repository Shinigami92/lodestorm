class_name OreType
extends Resource
## A kind of resource that ore nodes yield and miners collect. Each type is recognizable at a
## glance by three things together: its color, its crystal shape (`model`) and its glow pattern
## (`glow`), so telling them apart never depends on color alone. Every ore of the game is listed in
## `game/ores/all_ores.tres` (`OreCatalog`), commonest first.

## How widely an ore is found: common and mid ores belong to biomes (on several planets, mid ores
## farther out), a signature ore to one planet (the rarest near the star).
enum Band { COMMON, MID, SIGNATURE }
## How the ore's glow changes over time (and over the crystal). Nothing flashes faster than 3 times
## a second (photosensitivity).
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

## Player-facing name (an invented mineral name), translated.
@export var display_name: String = ""
@export var band: Band = Band.COMMON
## How rare it is: 1 is the commonest, each ore its own. Ammo is made from the commonest carried ore
## first; the hold and the lists order ores by it.
@export var tier: int = 1
## How much ammo one unit makes, compared to the commonest ore (`RangedWeaponSettings.ore_per_round`
## is in units of that). TBD (playtest).
@export var ammo_yield: float = 1.0
## How fast miners fill up with it, relative to the commonest ore (rarer ores mine slower). TBD
## (playtest).
@export var mine_rate: float = 1.0
## How hard it is to drill. Not used yet: crafted miners with drill types will need a drill at
## least this hard (see GAME_DESIGN.md, Miners); 0 means any miner can mine it.
@export var hardness: int = 0
## Strong, distinct color of its glow: the crystals, the miner's column, the hose, the canisters
## and its badge on holo cards.
@export var color: Color = Color.WHITE
@export var glow: Glow = Glow.STEADY
## A near-black crystal with glowing veins in `color`, instead of a glowing crystal.
@export var dark_body: bool = false
## Badge icon: a white crystal silhouette with grey facets, tinted in `color` (see `OreBadge`).
@export var icon: Texture2D
## Model kit (.glb) with the look of this type's ore nodes; the greybox stays without one.
@export var model: PackedScene
## Names of the variants in `model`: each is a node with a `Base*` mesh (the rock the crystals
## grow out of) and `Crystal*` meshes (drawn in the ore's glowing material).
@export var variants: Array[StringName] = []

var _material: Material
var _glow_material: Material


## Shared material of its crystals, in the ore color with its glow pattern over the crystal. It
## glows (and blooms) strongly: in the muted, dark world the ore is one of the few saturated, bright
## things, so it reads from the camera distance.
func get_material() -> Material:
	if not _material:
		_material = OreGlow.crystal_material(self)
	return _material


## Shared material for everything else filled with this ore (the miner's column, the hose, the
## canisters): its color and the glow pattern's rhythm, without the patterns over a crystal.
func get_glow_material() -> Material:
	if not _glow_material:
		_glow_material = OreGlow.fill_material(self)
	return _glow_material


## Its translated name.
func get_display_name() -> String:
	return tr(display_name)
