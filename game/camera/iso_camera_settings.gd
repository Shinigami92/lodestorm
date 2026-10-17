class_name IsoCameraSettings
extends Resource
## Isometric camera tuning values. All values TBD (playtest).

## Rotation around the vertical axis; 45° looks along the map's diagonal.
@export_range(0.0, 360.0, 0.1, "degrees") var yaw: float = 45.0
## Downward tilt; 35.264° (arctan(1/√2)) is true isometric.
@export_range(10.0, 89.0, 0.1, "degrees") var pitch: float = 35.264
## Distance from the camera to the followed target, in m.
@export var distance: float = 40.0
## Orthographic (true isometric) or perspective projection.
@export var orthographic: bool = true
## Visible height in m (orthographic only).
@export var size: float = 20.0
## Vertical field of view (perspective only).
@export_range(5.0, 90.0, 0.1, "degrees") var fov: float = 30.0
## How fast the camera catches up with the target (higher = tighter, 0 = no follow).
@export var follow_speed: float = 8.0
## Radius of the cut-away around the line from the camera to the target, in m: the outside world's
## ground in between (a cliff on the camera's side of a narrow pass) is dithered out. 0: none.
@export var cutaway_radius: float = 7.0
## Where on the target the cut-away aims: this high above its origin (the feet), in m. The ground
## below it (where it stands) stays.
@export var cutaway_height: float = 1.2
