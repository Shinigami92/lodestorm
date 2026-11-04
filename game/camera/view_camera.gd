class_name ViewCamera
extends RefCounted
## The camera that what's laid out for the view goes by (billboards, menus framed on the screen,
## "screen up" on the ground, walking relative to the view): the viewport's camera, but in VR the
## desktop rig's (`IsoCameraRig`), whose head floats on that camera's line (`VrRig`). The head turns
## freely; the layout and the directions stay where the desktop has them.
## Sound uses the viewport's camera itself, so the ears turn with the head.


## The view's camera for `node` (null outside the tree or without a camera).
static func of(node: Node) -> Camera3D:
	if not node.is_inside_tree():
		return null
	var camera: Camera3D = node.get_viewport().get_camera_3d()
	if camera is XRCamera3D:
		var rig := node.get_tree().get_first_node_in_group(IsoCameraRig.GROUP) as IsoCameraRig
		if rig:
			return rig.get_camera()
	return camera
