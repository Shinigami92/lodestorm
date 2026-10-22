class_name RenderLayers
extends RefCounted
## The render layers, as bits of `VisualInstance3D.layers` and of the cull masks of cameras,
## lights and decals.

## The ground, rocks, props and everything else.
const WORLD: int = 1
## Players' and aliens' bodies: the telegraphs projected onto the ground (a charge's lane) leave
## them out.
const CHARACTERS: int = 2
## The markings the suit draws on the ground (the suit ring, the target brackets): they're pulled
## towards the camera (`ground_marking.gdshaderinc`), so a decal would land on them off its spot.
## Decals leave them out.
const MARKINGS: int = 4


## Puts the visuals under `root` (its own too) on `layer` only.
static func put(root: Node, layer: int) -> void:
	var visuals: Array[Node] = root.find_children("*", "VisualInstance3D", true, false)
	if root is VisualInstance3D:
		visuals.append(root)
	for node: Node in visuals:
		(node as VisualInstance3D).layers = layer
