# The VR view (planned)

Decided 2026-10-17; the viewpoint on the desktop camera's line, following the character, the blinks, the controllers as a gamepad and pointing at menus are built (M6 step A, see [The VR view](../design/vr.md)); the sky and the far ring are built (M5's art pass, see [Light and weather outside](../design/art.md#light-and-weather-outside) and Beyond the map in [Locations](../design/locations.md)). What's left comes with M6 (see [`PLAN.md`](../PLAN.md)). All values **TBD (playtest)**.

## The viewpoint

- **The distance** can be changed along the camera's line (a setting).
- **Comfort options:** an optional comfort vignette while the viewpoint moves; "follow in steps" moves it only when the character nears the edge of the view, with a short fade.
- **How far a VR player sees:** from 20 m up, a VR player could look over the cliffs across the whole location, which a desktop player never can, and finding things is part of the game. So a haze closes in around the character: clear within about 60–80 m (about what the desktop frame shows), thicker beyond, the far map only shapes in the mist. It's tied to the character's position, not to where the head looks, so both players see the same.

## What only VR sees

- **Below and behind:** the camera-side rock (the low terraces) needs a top that looks finished from above (rock tops, low plants, scree); it mostly has that.
- **Aboard:** the same cut-away ship; looking up from aboard shows the sky (or space) above the open roof; the cut edges get a clean cap (a dark trim), so the dollhouse look reads as intended.
- **Flights:** the flight's effects surround the viewpoint, not just a frame: stars streaking past on all sides, clouds rushing up around, the touchdown's dust; no shake.

## Controls

- **Haptics:** hits, the dash, recoil (the action map has the haptic output).

## Performance

VR renders the whole surroundings twice at 90 FPS, not a narrow frame: the haze also limits what's drawn (scatter, far aliens), the far ring is one cheap mesh, the sky one shader. Budgeted in the VR profiling (M6).
