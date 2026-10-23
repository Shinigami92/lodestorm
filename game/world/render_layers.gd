class_name RenderLayers
extends RefCounted
## The render layers, as bits of `VisualInstance3D.layers` and of the cull masks of cameras,
## lights and decals.

## The ground, rocks, props and everything else.
const WORLD: int = 1
## Players' and aliens' bodies, what players carry (the weapon, the cargo tubes, the armor pips)
## and what floats around them (the ship pointer, arriving ore, the pause panel): the decals
## projected onto the ground (a charge's lane, the aim reticle) leave them out.
const CHARACTERS: int = 2
## Markings on the ground: the suit's (the suit ring, the target brackets: they're pulled towards
## the camera, `ground_marking.gdshaderinc`, so a decal would land on them off its spot), the
## highlights of what a player would use (`Interactable`) and the stand rings of the stations, the
## rooms' names and the floor guides, a lobbed weapon's landing ring and a throw's sight line.
## Decals leave them out, so they stay readable on top.
const MARKINGS: int = 4
## Light, not surfaces: holograms (the holo table's location, the navigator's star system and
## globes, the skill graph, the miners' bay's ghost miners, holo cards), fields (the shooting
## range's barrier, Mantle's), weapons' and aliens' effects (blasts, beams, bolts, flames, clouds,
## sprays), the flight's clouds and streaks, and text and plates. Decals leave them out.
const EFFECTS: int = 8


## Puts the visuals under `root` (its own too) on `layer` only.
static func put(root: Node, layer: int) -> void:
	var visuals: Array[Node] = root.find_children("*", "VisualInstance3D", true, false)
	if root is VisualInstance3D:
		visuals.append(root)
	for node: Node in visuals:
		(node as VisualInstance3D).layers = layer
