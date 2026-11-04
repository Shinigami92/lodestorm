extends Node
## Autoload `Vr`: starts the VR view when the game runs in VR. VR is a launch option
## (`--xr-mode on`, see docs/technical/vr.md): starting OpenXR on every launch would start SteamVR
## on desktop too. Once OpenXR runs, the main viewport draws to the headset, the head is a `VrRig`
## (kept across scenes, it lives here), the controllers are a gamepad (`VrGamepad`) and point at
## menus (`VrPointer`). Without OpenXR (desktop, the tests) it does nothing.

var _xr: OpenXRInterface
var _rig: VrRig


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_xr = XRServer.find_interface("OpenXR") as OpenXRInterface
	if not _xr or not _xr.is_initialized():
		return
	print("VR: OpenXR runs (%s)" % _xr.get_system_info().get("XRRuntimeName", "?"))
	# Picking physics objects with the mouse doesn't work in stereo (nothing here uses it).
	get_viewport().physics_object_picking = false
	get_viewport().use_xr = true
	# The headset paces the frames, not the monitor.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_rig = VrRig.new()
	add_child(_rig)
	var gamepad := VrGamepad.new()
	add_child(gamepad)
	var pointer := VrPointer.new()
	pointer.rig = _rig
	pointer.gamepad = gamepad
	add_child(pointer)
	_xr.session_begun.connect(_rig.center_soon)
	_xr.pose_recentered.connect(_rig.center)
	_xr.session_stopping.connect(get_tree().quit)
