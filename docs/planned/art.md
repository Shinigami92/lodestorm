# Light and player colors (planned)

Decided 2026-10-17. Built in parts (see [`PLAN.md`](../PLAN.md)): the palette check in M4 step 5 D (built: the palette viewer, see [`technical/engine.md`](../technical/engine.md)), the light per body, the darkness floor and the storm's steps with the art pass (M5, built: see [Light and weather outside](../design/art.md#light-and-weather-outside)), the player colors with co-op (M7). All values **TBD (playtest)**.

## Light

- **A region's mood:** a region may have a fixed mood (dusk, overcast), as data on top of its body's light.
- **Aboard:** as today (warm work lights, each room its own tint and light), plus the outside light coming in through the windows in the body's color, so the ship feels the planet it stands on.

## Player colors

- **Four colors from a colorblind-safe set,** each always paired with the player's **number** (1–4), so color is never the only cue: **1 orange, 2 sky blue, 3 yellow, 4 reddish purple**. Solo is always player 1, orange (as today).
- **Only on what belongs to a player:** the suit's stripes, the silhouette, the suit ring's outline in co-op, the target lock brackets, the locker's strip, the name plate, their crafted miners' number plates; never on ground objects, so they don't compete with the ores (some share a hue family, but the player's shape and number tell them apart).
- **On the suit:** a wide stripe in the player color on the pauldrons and the number on the back of the helmet (the camera sees both from every side); the collar band stays the health light, the chest light stays blue for everyone. The crew keep their darker suit with their own collar color.
