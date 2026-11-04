# The VR view

Lodestorm plays the same in VR (Steam Frame, through OpenXR) as on the desktop: the same isometric game, seen from where the desktop camera is, with the head free to turn and tilt. VR is started with a launch option (see [`technical/vr.md`](../technical/vr.md)). What's still to come (the comfort options, the haze around the character, what only VR sees, the flights' surrounding effects, haptics) is in [`planned/vr-view.md`](../planned/vr-view.md). All values **TBD (playtest)**.

## The viewpoint

- **Where the head floats:** on the desktop camera's line (the same direction and downward angle, following the character), at real scale, no miniature. Closer than on desktop, since a headset sees about 100° instead of 30°: 22 m from what the desktop camera looks at, so the area around the character fills the middle of the view and the stereo depth still works (at 40 m everything looks flat). The view itself never turns or tilts; the player looks down onto the character (about 35°) like onto a table. So everything built for the desktop's direction (the low rock on the camera's side, the cliffs facing it, the ship's cut-away walls) works in VR unchanged.
- **Centered on the head:** seated or standing, the head starts on that line: the view centers on the head when the session starts and whenever the player recenters (the headset's own recenter).
- **Following the character:** the viewpoint glides after where the desktop camera is going, slower than on desktop.
- **Framing:** where the desktop camera moves in to frame something (a station, the pause panel, a room like the shooting range), the head moves in along the same line by the same share (a menu's panel ends up about an arm and a half away, filling about half the view). These jumps, and any jump farther than 8 m (a respawn, the title view, a new scene), blink: a short fade to black, the jump, a fade back in, never a long glide. The boot screen puts the head where its camera is.
- **Fades:** the game's fades to black (quitting, a new scene fading in) close around the head too.
- **What's laid out for the view** (cards, bubbles, panels turned to the camera, the suit ring's "screen up", walking and aiming directions) follows the desktop camera's fixed direction, not the head: turning the head never turns the world's layout. The sound's ears turn with the head.

## Controls

The Steam Frame's controllers are a gamepad split in two (left: stick, d-pad, trigger, bumper, view button; right: stick, A/B/X/Y, trigger, bumper, menu button), so in VR they are the gamepad: every action has its gamepad binding (see [Input](../technical/engine.md)), the left stick walks, the right stick aims, the right trigger attacks, the menu button pauses, and menus can be used with the stick and A like with a gamepad. Other controllers are bound as close as they come (grips as bumpers; Touch has no d-pad, Index no menu button but its left trackpad pressed). Planned: haptics.

**Pointing at menus:** while the player uses a menu (a screen, a station and its card, the pause panel), a thin amber beam comes out of the controller with a dot where it points, and pointing works like the mouse: over a card's buttons, a station's parts (hovered when the beam passes near them, as the cursor does), and the trigger clicks (dragging pans where the mouse drags, e.g. the skill graph). The right hand points; pulling the other trigger hands the beam over. While a menu is open the triggers only click (no zooming with them in the navigator, which steps back with B instead).
