# The player during a mission (planned)

Decided 2026-10-17, built in M4 step 5 (see [`PLAN.md`](../PLAN.md)). All values **TBD (playtest)**. The suit ring (health and ammo arcs, spare magazine ticks, the dash, hit marks, the pointers on its edge, its settings, teammates' reduced rings), the target lock's brackets and ore arriving are built (see [UI](../GAME_DESIGN.md#ui-in-the-world-not-on-the-screen)); this file keeps what comes with later features.

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

- **Right arc, other feeds:** the heat of the planned weapons (see [`weapons.md`](weapons.md)) shows on the ammo arc the way a reload does (built for a drained battery and a charge, see [UI](../GAME_DESIGN.md#ui-in-the-world-not-on-the-screen)).
- **Outer edge:** the tracked quest's pointer (see [`quests.md`](quests.md)), an arrow like the ship's and the ore scanner's.
- **Miners left:** show as ticks for 3 s when one is placed or picked up, and while the player stands next to a miner (see [`refinery.md`](refinery.md)).

## Around the ring

- **The suit itself:** its lights stay as looks and for teammates, but nothing needs to be read from them: the collar band (mirroring the health, so teammates see it) and the ore stack on the back (a big shape, the haul shows in the silhouette) stay; the MK pips on the helmet and weapons stay for looks and the stations aboard. The player color on the suit (pauldron stripes, the number) comes with co-op (see [`art.md`](art.md)).
- **Alien telegraphs:** red dashed circles and lines on the ground (see [`aliens.md`](aliens.md)), with the aliens.
- **VR:** the same ring (see [`vr-view.md`](vr-view.md)).
