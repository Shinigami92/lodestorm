# The VR view (planned)

Decided 2026-10-17, built with the VR rig (M6, see [`PLAN.md`](../PLAN.md)); the sky and the far ring with the art pass (M5). All values **TBD (playtest)**. Earlier the plan was a "tabletop diorama" (the world as a model on a table in front of the player); instead, the player's head floats where the desktop camera is, but can turn and tilt, so it sees more than the desktop's frame, even the sky. Today the desktop camera never turns (yaw 45°, pitch about 35°, 40 m away with a 30° field of view, about 21 m of height on screen), and the ground and the ship are built for it (see [Perspective & art direction](../design/art.md)).

## The viewpoint

- **Where the head floats:** on the desktop camera's line (the same direction and downward angle, following the character), at real scale, no miniature. Closer than on desktop, since a headset sees about 100° instead of 30°: greybox about 20–25 m from the character, so the area around them fills the middle of the view like the desktop's frame, and the stereo depth still works (at 40 m everything looks flat). The distance can be changed along that line. The view never rotates on its own; only the head turns. So everything built for the desktop's direction (the low rock on the camera's side, the cliffs facing it, the ship's cut-away walls) works in VR unchanged.
- **Following the character:** the viewpoint glides after the character smoothly (slower than on desktop), with an optional comfort vignette while it moves; a comfort option "follow in steps" moves it only when the character nears the edge of the view, with a short fade. Stations and self-framing rooms move the viewpoint with a fade, never by turning the head.
- **How far a VR player sees:** from 20 m up, a VR player could look over the cliffs across the whole location, which a desktop player never can, and finding things is part of the game. So a haze closes in around the character: clear within about 60–80 m (about what the desktop frame shows), thicker beyond, the far map only shapes in the mist. It's tied to the character's position, not to where the head looks, so both players see the same.

## What only VR sees

- **The sky,** per body: the star Kesh small and pale on the outer planets, bigger and harsher inwards, its flares as glare on the inner planets; on a moon its planet large in the sky (Gaulm fills much of it above Orrel and Iska), the other planets as bright points; the biome's weather overhead (clouds, ash, snow, see [`biomes.md`](biomes.md)); the storm as a towering wall of reddish-brown cloud on one side during the warning, closing over the sky when it hits; in space, stars all around, the planet below, the station when docked. One sky shader with these layers, cheap enough for VR. The desktop sees it only indirectly (reflections, light, the ship's windows).
- **Beyond the map:** past the location's rim the land goes on, a far ring of low-detail terrain in the biome's shapes and colors (mesas, ice, ash ridges) fading into the haze; no visible edge, no void. The generator builds it as one cheap mesh around the location.
- **Below and behind:** the camera-side rock (the low terraces) needs a top that looks finished from above (rock tops, low plants, scree); it mostly has that.
- **Aboard:** the same cut-away ship; looking up from aboard shows the sky (or space) above the open roof; the cut edges get a clean cap (a dark trim), so the dollhouse look reads as intended.
- **Flights:** the flight's effects surround the viewpoint, not just a frame: stars streaking past on all sides, clouds rushing up around, the touchdown's dust; no shake.

## Performance

VR renders the whole surroundings twice at 90 FPS, not a narrow frame: the haze also limits what's drawn (scatter, far aliens), the far ring is one cheap mesh, the sky one shader. Budgeted in the VR profiling (M6).
