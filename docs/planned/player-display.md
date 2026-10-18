# The player during a mission (planned)

Decided 2026-10-17, built in M4 step 5 (see [`PLAN.md`](../PLAN.md)). All values **TBD (playtest)**. The suit ring with its health and ammo arcs, the spare magazine ticks, the dash and the hit marks is built (see [UI](../GAME_DESIGN.md#ui-in-the-world-not-on-the-screen)); this file keeps what's still to come.

## Why

The camera shows about 21 m of height, so the player (1.86 m) is about 100 px tall at 1080p and a 5 cm light on the suit only a few pixels. Lights on the suit and the weapon can't carry what a player has to read in a fight, and more is coming (new weapons' heat and charge, miners left, quest items, hit directions, alien telegraphs, teammates).

## The suit ring, still to come

```text
          ship ▲ 12:40          (pointers on the outer edge)
       .-~~~~~~~~-.
     /  HEALTH | AMMO \        left arc: health    right arc: ammo
    |          |       |       inner thin ring: dash recharging
     \         | ▪ ▪ ▪ /       ticks under the ammo arc: spare magazines
       '-~~~~~~~~-'
```

- **Right arc, other feeds:** the heat, charge or belt of the planned weapons (see [`weapons.md`](weapons.md)) show on the ammo arc the way a reload does.
- **Outer edge:** the pointers: the arrow to the ship with the countdown, the ore scanner's arrow, later the tracked quest (see [`quests.md`](quests.md)), as arrows on the ring's edge.
- **Miners left:** show as ticks for 3 s when one is placed or picked up (see [`refinery.md`](refinery.md)).

## Around the ring

- **The suit itself:** its lights stay as looks and for teammates, but nothing needs to be read from them: the collar band (mirroring the health, so teammates see it) and the ore stack on the back (a big shape, the haul shows in the silhouette) stay; the MK pips on the helmet and weapons stay for looks and the stations aboard.
- **Ore arriving:** when a hose delivers, a small badge of that ore with the amount ("+180") rises above the player for 2 s (several ores in one line), and the stack on the back fills.
- **Every kind of ground marking has its own shape:** the player's ring solid arcs, the target lock four corner brackets around the alien in the player's color (today a ring), alien telegraphs red dashed circles and lines (see [`aliens.md`](aliens.md)), giving ammo a green fill around the ring, pointers arrows on the ring's edge.
- **Teammates** (co-op): other players' rings show only their health arc and an outline in their player color, so four players don't cover the ground.
- **Settings** (in the pause panel and on the settings terminal, see [`menu-pause.md`](menu-pause.md)): ring size (small, medium, large) and "Always show" (no fading). Health never relies on color alone: it blinks below a quarter, and the arc's length shows the share.
- **VR:** the same ring (see [`vr-view.md`](vr-view.md)).
