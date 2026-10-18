# The player during a mission (planned)

Decided 2026-10-17, built in M4 step 5 (see [`PLAN.md`](../PLAN.md)). All values **TBD (playtest)**. Today the player shows their state through lights on the suit and the weapon, and a reload ring (see [UI](../GAME_DESIGN.md#ui-in-the-world-not-on-the-screen) and [Ammo and reloading](../GAME_DESIGN.md#ammo-and-reloading)).

## Why

The camera shows about 21 m of height, so the player (1.86 m) is about 100 px tall at 1080p and a 5 cm light on the suit only a few pixels. Lights on the suit and the weapon can't carry what a player has to read in a fight, and more is coming (new weapons' heat and charge, miners left, quest items, hit directions, alien telegraphs, teammates).

## Three layers

- **Critical** (low health, an empty or reloading weapon, the storm countdown, a hit) is always readable and big.
- **Situational** (spare magazines, the dash, miners left, ore arriving) shows when it changes or matters, then fades after about 3 s.
- **Details** (exact amounts, MK levels, cargo by type) are never needed in a fight and stay aboard (the silos, the stations, the quest board).

## The suit ring

The suit projects one ring on the ground around the player's feet (about 1.4 m radius, wider than the body; its lines keep a minimum thickness on screen). It replaces the separate reload ring, the spare magazine cells on the backpack and the dash strip. Its halves stay fixed to the screen, not to where the player faces:

```text
          ship ▲ 12:40          (pointers on the outer edge)
       .-~~~~~~~~-.
     /  HEALTH | AMMO \        left arc: health    right arc: ammo
    |          |       |       inner thin ring: dash recharging
     \         | ▪ ▪ ▪ /       ticks under the ammo arc: spare magazines
       '-~~~~~~~~-'
```

- **Left arc, health:** green, amber below half, red and blinking below a quarter, flashing white on damage; a short red mark on its outer edge points to where a hit came from.
- **Right arc, ammo:** the equipped weapon's fill in its ammo color; reloading and its timing window, and the heat, charge or belt of the other feeds (see [`weapons.md`](weapons.md)), show the way the reload ring shows them today.
- **Ticks under the ammo arc:** the spare magazines.
- **Inner thin ring:** the dash, only while it's recharging.
- **Outer edge:** the pointers: the arrow to the ship with the countdown (as today), the ore scanner's arrow, later the tracked quest (see [`quests.md`](quests.md)).
- **Fading:** at full health and with a full magazine the arcs dim to a faint outline, so the ring is quiet when nothing's going on; they light up fully when something changes (a hit, firing, reloading, low values) and dim again after 3 s. Critical states (below a quarter of health, empty) never dim. The spare magazine ticks show on a reload and when a spare is used; the miners left show as ticks for 3 s when one is placed or picked up (see [`refinery.md`](refinery.md)).
- **Drawn over** the ground, grass and low plants, following slopes; only cliffs and props hide it, like the body (the silhouette shows the player then).

## Around the ring

- **The suit itself:** its lights stay as looks and for teammates, but nothing needs to be read from them: the collar band (mirroring the health, so teammates see it) and the ore stack on the back (a big shape, the haul shows in the silhouette) stay; the MK pips on the helmet and weapons stay for looks and the stations aboard.
- **Ore arriving:** when a hose delivers, a small badge of that ore with the amount ("+180") rises above the player for 2 s (several ores in one line), and the stack on the back fills.
- **Every kind of ground marking has its own shape:** the player's ring solid arcs, the target lock four corner brackets around the alien in the player's color (today a ring), alien telegraphs red dashed circles and lines (see [`aliens.md`](aliens.md)), giving ammo a green fill around the ring, pointers arrows on the ring's edge.
- **Teammates** (co-op): other players' rings show only their health arc and an outline in their player color, so four players don't cover the ground.
- **Settings** (in the pause panel and on the settings terminal, see [`menu-pause.md`](menu-pause.md)): ring size (small, medium, large) and "Always show" (no fading). Health never relies on color alone: it blinks below a quarter, and the arc's length shows the share.
- **VR:** the same ring (see [`vr-view.md`](vr-view.md)).
