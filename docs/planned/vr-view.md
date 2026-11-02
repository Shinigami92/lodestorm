# The VR view (planned)

Decided 2026-10-17, built with the VR rig (M6, see [`PLAN.md`](../PLAN.md)); the sky and the far ring are built (M5's art pass, see [Light and weather outside](../design/art.md#light-and-weather-outside) and Beyond the map in [Locations](../design/locations.md)). All values **TBD (playtest)**. Earlier the plan was a "tabletop diorama" (the world as a model on a table in front of the player); instead, the player's head floats where the desktop camera is, but can turn and tilt, so it sees more than the desktop's frame, even the sky. Today the desktop camera never turns (yaw 45°, pitch about 35°, 40 m away with a 30° field of view, about 21 m of height on screen), and the ground and the ship are built for it (see [Perspective & art direction](../design/art.md)).

## The viewpoint

- **Where the head floats:** on the desktop camera's line (the same direction and downward angle, following the character), at real scale, no miniature. Closer than on desktop, since a headset sees about 100° instead of 30°: greybox about 20–25 m from the character, so the area around them fills the middle of the view like the desktop's frame, and the stereo depth still works (at 40 m everything looks flat). The distance can be changed along that line. The view never rotates on its own; only the head turns. So everything built for the desktop's direction (the low rock on the camera's side, the cliffs facing it, the ship's cut-away walls) works in VR unchanged.
- **Following the character:** the viewpoint glides after the character smoothly (slower than on desktop), with an optional comfort vignette while it moves; a comfort option "follow in steps" moves it only when the character nears the edge of the view, with a short fade. Stations and self-framing rooms move the viewpoint with a fade, never by turning the head.
- **How far a VR player sees:** from 20 m up, a VR player could look over the cliffs across the whole location, which a desktop player never can, and finding things is part of the game. So a haze closes in around the character: clear within about 60–80 m (about what the desktop frame shows), thicker beyond, the far map only shapes in the mist. It's tied to the character's position, not to where the head looks, so both players see the same.

## What only VR sees

- **Below and behind:** the camera-side rock (the low terraces) needs a top that looks finished from above (rock tops, low plants, scree); it mostly has that.
- **Aboard:** the same cut-away ship; looking up from aboard shows the sky (or space) above the open roof; the cut edges get a clean cap (a dark trim), so the dollhouse look reads as intended.
- **Flights:** the flight's effects surround the viewpoint, not just a frame: stars streaking past on all sides, clouds rushing up around, the touchdown's dust; no shake.

## Performance

VR renders the whole surroundings twice at 90 FPS, not a narrow frame: the haze also limits what's drawn (scatter, far aliens), the far ring is one cheap mesh, the sky one shader. Budgeted in the VR profiling (M6).
