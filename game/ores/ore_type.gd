class_name OreType
extends ItemType
## A kind of resource that ore nodes yield and miners collect: an item (`ItemType`) whose shape is
## its crystal (`model`). Every ore of the game is listed in `game/ores/all_ores.tres`
## (`OreCatalog`), commonest first.

## How widely an ore is found: common and mid ores belong to biomes (on several planets, mid ores
## farther out), a signature ore to one planet (the rarest near the star).
enum Band { COMMON, MID, SIGNATURE }

@export var band: Band = Band.COMMON
## How rare it is: 1 is the commonest, each ore its own. Ammo is made from the commonest carried ore
## first; the hold and the lists order ores by it.
@export var tier: int = 1
## How much ammo one unit makes, compared to the commonest ore (`WeaponFeed.ore_per_round`
## is in units of that). TBD (playtest).
@export var ammo_yield: float = 1.0
## How fast miners fill up with it, relative to the commonest ore (rarer ores mine slower). TBD
## (playtest).
@export var mine_rate: float = 1.0
## How hard it is to drill: a miner whose drill mines up to a lower hardness (`Upgrade.hardness_at`)
## mines it at `MinerSettings.soft_drill_share` of the speed. 0: every drill mines it at full speed.
@export var hardness: int = 0
## Model kit (.glb) with the look of this type's ore nodes; the greybox stays without one.
@export var model: PackedScene
## Names of the variants in `model`: each is a node with a `Base*` mesh (the rock the crystals
## grow out of) and `Crystal*` meshes (drawn in the ore's glowing material).
@export var variants: Array[StringName] = []

var _material: Material


## Shared material of its crystals, in the ore color with its glow pattern over the crystal. It
## glows (and blooms) strongly: in the muted, dark world the ore is one of the few saturated, bright
## things, so it reads from the camera distance.
func get_material() -> Material:
	if not _material:
		_material = OreGlow.crystal_material(self)
	return _material
