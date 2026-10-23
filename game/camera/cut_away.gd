class_name CutAway
extends RefCounted
## Cuts away what stands between the camera and an interior (the ship's decks, a station's rooms):
## the roof and the walls facing the camera only cast shadows while the viewer is inside, so the
## camera sees in. Their lights, holograms and window panes (`HIDE_GROUP`) turn off instead.

## Nodes hidden with their wall rather than left casting shadows: window panes (they never cast
## shadows, light comes in), holograms.
const HIDE_GROUP: StringName = &"cutaway_hide"


## Shows `root`'s geometry, or only lets it cast shadows; its lights and the nodes in
## `HIDE_GROUP` turn off.
static func show(root: Node, shown: bool) -> void:
	for child: Node in root.get_children():
		if child is Light3D or child.is_in_group(HIDE_GROUP):
			(child as Node3D).visible = shown
			continue
		if child is GeometryInstance3D:
			(child as GeometryInstance3D).cast_shadow = (
				GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				if shown
				else GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			)
		show(child, shown)
