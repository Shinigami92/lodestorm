class_name VrSettings
extends Resource
## The VR view's tuning values (see docs/design/vr.md). All values TBD (playtest).

## How far the head floats from what the desktop camera looks at, in m, along that camera's line
## (desktop: 40 m with a 30° field of view; a headset sees about 100°).
@export var distance: float = 22.0
## How fast the head glides after the view (higher = tighter); slower than the desktop camera.
@export var follow_speed: float = 4.0
## A jump of the view farther than this (m) blinks: fade to black, jump, fade in.
@export var blink_distance: float = 8.0
## How long the blink's fade out and in each take, in s.
@export var blink_time: float = 0.15
## How long after the session starts the view centers on the head the first time, in s (the first
## poses can be off).
@export var center_delay: float = 0.5
