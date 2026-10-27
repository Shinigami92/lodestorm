# Light and player colors (planned)

Decided 2026-10-17. Built in parts (see [`PLAN.md`](../PLAN.md)): the palette check in M4 step 5 D (built: the palette viewer, see [`technical/engine.md`](../technical/engine.md)), the light per body and the storm's steps with the art pass (M5), the player colors with co-op (M7). All values **TBD (playtest)**. Today: a dim warm sun, a faint cool back light, low ambient light, bloom only on emissive parts, the storm dimming the light in its last minute, players' silhouettes orange (see [Art direction](../design/art.md#art-direction)).

## Light

- **By the star:** each body has its light (data on the body): far out a weak, cool, low sun with long soft shadows (Torvane, Lisk, Vehra), getting stronger, whiter and higher inwards, with hard short shadows and a harsh glare on Skelde and Zairen. The biome adds its fog, ambient tint and weather on top (see [`biomes.md`](biomes.md)). So every planet looks different before any texture, and the story's threat is in the light itself (see [`story.md`](story.md)); the sky matches it (see [`vr-view.md`](vr-view.md)).
- **How dark:** dark and moody, but the ground's shapes never vanish: a floor for the ground's brightness (the cliffs, passes and the ramp stay readable at a glance from the camera, checked with a probe per biome), and everything the player must read stays emissive or rim-lit, so it doesn't depend on the light. No day and night (a run is 15–30 min); a region may have a fixed mood (dusk, overcast), as data.
- **The storm:** in the warning (longer inwards, see Tiers in [Missions](../design/missions.md)) the sun dims step by step to about 40 % and the haze thickens from the storm's side; when it hits, about 25 % and the reddish-brown roar all around. Emissives and rim light don't dim, so players, aliens, ore and the suit ring stay readable to the end.
- **Aboard:** as today (warm work lights, each room its own tint and light), plus the outside light coming in through the windows in the body's color, so the ship feels the planet it stands on.

## Player colors

- **Four colors from a colorblind-safe set,** each always paired with the player's **number** (1–4), so color is never the only cue: **1 orange, 2 sky blue, 3 yellow, 4 reddish purple**. Solo is always player 1, orange (as today).
- **Only on what belongs to a player:** the suit's stripes, the silhouette, the suit ring's outline in co-op, the target lock brackets, the locker's strip, the name plate, their crafted miners' number plates; never on ground objects, so they don't compete with the ores (some share a hue family, but the player's shape and number tell them apart).
- **On the suit:** a wide stripe in the player color on the pauldrons and the number on the back of the helmet (the camera sees both from every side); the collar band stays the health light, the chest light stays blue for everyone. The crew keep their darker suit with their own collar color.
