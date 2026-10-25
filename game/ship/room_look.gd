class_name RoomLook
extends Resource
## How a room aboard looks apart from the others (one shared steel look, see
## docs/planned/ship-interior.md): its floor's tint and its accent color (lamp strips, its sign).
## The room's lights stay its scene's own.

## Multiplies the shell's floor plates (around 1: a hue, not a brightness).
@export var floor_tint: Color = Color.WHITE
## The room's accent lights and sign.
@export var accent_color: Color = Color(1.0, 0.85, 0.6)
