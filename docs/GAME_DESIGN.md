# Lodestorm — Game Design Document

> Status: draft / pre-production. Values marked **TBD (playtest)** are intentionally left open and will be tuned once the systems are playable.

## 1. Pitch

A stylized 3D isometric action/mining game. The player lives on a spaceship that acts as the hub. From the ship they pick a mission, the ship flies there, and the player heads out to place miners on resource nodes, fight off aliens, collect the mined resources via a hose, and get back to the ship before the storm hits. Resources are spent on upgrades in the ship.

## 2. Platform & technical constraints

| Topic | Decision |
|---|---|
| Engine | Godot (version pinned in [`.godot-version`](../.godot-version)) |
| Language | GDScript |
| Primary platform | Desktop (Windows) |
| Secondary platform | VR (Steam Frame, via OpenXR) |
| Input | Keyboard + mouse, gamepad (PS5 controller), VR controllers (Steam Frame, gamepad-like layout) |
| Performance | Desktop: 60 FPS minimum, 120–144 FPS target. VR: 90 FPS minimum |
| Players | Solo first; optional co-op up to 4 players |
| Asset pipeline | Blender (via Blender MCP) → glTF → Godot |
| License | CC BY-NC-SA 4.0 (own code + assets; third-party addons keep their licenses), CLA for contributors |
| Distribution | Source-available on GitHub (Releases via CI); later Steam, possibly Epic and GOG |
| Achievements | Yes — Steam achievements + in-game list (see [`TECHNICAL.md`](TECHNICAL.md)) |

### Architecture implications

- **Multiplayer-ready from day one:** game state changes go through host-authoritative code paths, solo = local host. Co-op is enabled later without rewriting gameplay.
- **Camera abstraction:** desktop uses an isometric camera; VR uses a "tabletop diorama" view (world in front of the player, looking down onto the character). Same gameplay, swappable camera rig. The rig also supports camera transitions (see below).
- **Input abstraction:** all gameplay reads Godot input actions only, so keyboard/mouse, gamepad and VR controllers map onto the same actions.

## 3. Perspective & art direction

- 3D, isometric camera.
- **The core loop is played in the isometric view** (desktop) / **tabletop diorama** (VR). Camera transitions away from it are allowed for specific moments, e.g. moving closer to a terminal for a 3D menu, the ship taking off and landing, or the ramp opening at mission start. They always return to the main view. In VR, transitions must stay comfortable (e.g. fades or moving the diorama, never the player's head); details **TBD (playtest)**.
- **Desktop camera:** fixed angle looking along the map's diagonal, following the player. Projection (orthographic vs. perspective), angle, distance and follow speed are **TBD (playtest)**; they live in `scenes/camera/iso_camera_settings.tres` (current: perspective, chosen over orthographic after a first comparison).
- **Controls (twin-stick):** movement is relative to the screen ("up" walks up the screen, whatever the camera angle). The player faces the aim direction: the point on the ground under the mouse cursor, or the right stick. Without aim input (gamepad, stick released) the player faces the movement direction. Whichever of mouse and right stick was used last wins.
- **Target lock:** an alien under the mouse cursor (within 4% of the screen height, let go beyond 7%), or the nearest one within 12° of the right stick and 25 m, gets locked on: a ring in the player's color lies under it, the player turns to it and shots fly straight at it, so aliens up or down a slope can be hit too (`scenes/player/player_settings.tres`, **TBD (playtest)**). Without a lock, shots fly level. The mouse aims at the ground under the cursor, also on hills.
- Stylized art (low-poly / clean shapes, readable silhouettes, strong colors per resource type).
- Readability over detail: ore types, aliens and miners must be recognizable at a glance from the isometric distance (and in the VR diorama).
- Players stay visible behind cliffs, trees and walls: the hidden part of their body shows as a see-through silhouette in their color (`assets/shaders/occluded_silhouette.gdshader`).

### UI: in the world, not on the screen

- **No 2D HUD** where it can be avoided. Game information is shown in the world or on the player (diegetic UI). This also keeps desktop and VR the same: a screen-space HUD doesn't work in VR anyway.
- **Ideas (not final):** health and armor on the player's suit (lights, gauges), carried resources visible on the player (backpack / canisters filling up), ammo on the weapon, miner fill level on the miner itself, mission time via the environment (storm building up, ship beacon) or a display on the player's wrist.
- **3D menus are fine** where a menu is needed: mission selection, upgrade vendors, etc. are panels in the world (e.g. a terminal screen in the ship), not screen overlays.
- **Exceptions:** developer tools (debug overlay for tuning) are allowed in 2D. Whether system menus (main menu, pause, settings) can be 3D too is open.
- How 3D menus work technically (rendering, input with mouse / gamepad / VR controllers, text readability at isometric distance) is to be found out in a spike.

## 4. Core loop

```
Ship hub ──► select mission ──► ship flies to location ──► first player steps out = mission starts (timer)
   ▲                                                                    │
   │                                                                    ▼
   │                                                  place miners on resource nodes
   │                                                  fight aliens
   │                                                  collect from miners via hose
   │                                                                    │
   ├── everyone back aboard ──► resources saved ──► spend on upgrades ┘
   │
   └── die ──► lose everything carried this run ──► respawn in medical bay
```

## 5. Spaceship (hub)

- Multiple rooms with NPCs. The ship is big: the whole hub is its interior.
- **No loading screens:** the ship and the planet outside are one world. Players walk from the hub down the ramp straight into the mission. That's also why the weather outside matters: while the ship flies and lands, a storm around it hides the next location being loaded, so it acts as the loading screen.
- **Landing gear:** the landed ship stands on six legs along its sides (greybox: the hull 1.5 m above the ground, **TBD (playtest)**); nobody walks under it. The ramp is 5 m long and reaches the ground at 30°.
- **The ramp always leads out to the right** (screen right): players walk from the inside to the right into the mission, and come back from the right.
- **Ramp button:** the ramp is closed by default. A button on the inner wall next to the door lowers it; this also locks the selected mission (once mission selection exists). Pressing it again before anyone stepped out raises the ramp again. Once everyone is back aboard, the ramp goes up; the next press starts a new run with a reset timer and a fresh outside world.
- **No weapons inside the ship:** weapons are holstered aboard, except in the shooting range, where players try them without a mission. They only work inside the range (not in its doorway), and a force field in the doorway stops every shot, so nothing leaves the range. Targets stand at its far end.
- **Camera inside:** while a player is aboard, the roof and the walls facing the camera are cut away (they still cast shadows), so the camera can see inside. Inner walls between the camera and the corridor keep a low stub, so the rooms stay outlined. On the lower deck, the whole upper deck is cut away too; on the upper deck, the lower deck is hidden under its floor. Some rooms frame themselves: in the shooting range the camera looks at the whole room instead of the player, so the targets stay on screen from the firing line.
- **Two decks**, nose on the left, tail with the ramp on the right (like a cargo plane's rear ramp). A corridor runs along the middle of each deck; lifts join the decks at both ends, one by the bridge and one in the double-height cargo bay, so a run is a loop: ramp → cargo bay → lower deck (upgrades, armory) → lift → bridge (pick a mission) → upper deck → cargo bay lift → ramp.
  - **Upper deck (command and living):** cockpit at the nose, the bridge next to it, then the player cabins, the crew cabins and the mess hall.
  - **Lower deck (work):** medical bay (respawn point) and engine room at the nose, the shooting range, the armory (loadout) and one upgrade room per vendor (weapons, armor, skills, miners).
- **Lifts:** a platform for up to four players in a shaft beside the corridor. Stepping on it sends it to the other deck (greybox: after 0.6 s, 2 s ride, **TBD (playtest)**); riders who came along have to step off before it leaves again. Waiting at the gate on the other deck calls it. Gates close the shaft on every deck the platform isn't at.
- **Walking the ship:** the bridge sits at the nose, far from the ramp. Picking a mission starts the flight, and players walk aft and gear up while the ship flies and lands, so the walk isn't dead time (flight time **TBD (playtest)**).
- **Bridge:** missions are selected here. A holo table in the middle projects a hologram of the mission location (a small copy of the location, spinning slowly, the ship's spot highlighted), so players gather around it to see where they're going.
- **Cabins:** one per player (up to 4, cabin 1 closest to the bridge for solo play) with a bed and a locker; eight crew cabins for the NPCs with a bed each. Whether the locker becomes a private inventory is open.
- **Windows:** every room along the outer walls has windows on its deck (one per ~9 m of wall), and the cockpit looks out over the nose. From inside, they show the outside (light falls in through them); from outside, they show into the ship. Windows in walls cut away for the camera go with their wall.
- **Finding the way:** every room's name is painted on its floor by the door. Amber floor markings with arrows at the corridors, lobbies and lifts point to the rooms further on (and which lift leads where).
- **Greybox layout** (top view, camera at the bottom; about 96 × 30 m plus a nose cone below the cockpit and two thrusters on the roof at the tail, sizes **TBD (playtest)**; the real hull shape comes with the art pass):

  ```text
  UPPER  +-------+--------+------+----+----+----+----+----+----+-------+---------+
         |       |        | LIFT | C1 | C3 | N1 | N2 | N3 | N4 |    LIFT ↕       |
        <|COCK-  = BRIDGE =lobby =  corridor                   = MESS  |         |
         | PIT   | [holo] |      | C2 | C4 | N5 | N6 | N7 | N8 | HALL  |         |
         +-------+--------+------+----+----+----+----+----+----+-------+  CARGO  |
  LOWER  |  Medical bay   | LIFT | Shooting range   |  Armory          |   BAY   |
        <|     = corridor =lobby =        corridor                     =         = ramp
         |  Engine room   |      | Weapons | Armor  | Skills | Miners  |         |
         +----------------+------+---------+--------+--------+---------+---------+
  ```

  C = player cabins, N = crew cabins. Each room has its own floor tint and light.
- **NPCs:** shopkeepers / upgrade vendors, quest givers, and story characters (about eight to start: e.g. pilot, medic, quartermaster, one vendor per upgrade room, cook), each with a crew cabin.
- **Mission selection:** on the bridge, at the holo table. Target can be another location on the current planet or a new planet. The ship then flies there.
  - Idea: the hologram already shows where the ore fields are, each in its ore color, so players can plan their route and pick a mission by the ores they need.
- **Ship states:**
  - *In space:* windows show space; ramp cannot be opened.
  - *Landed, no mission started:* windows/ramp area show the local environment (e.g. storm).
  - The player **cannot go outside without a selected mission**; the ramp button only works with one. The **first player stepping out of the ship starts the mission** and its timer.

## 6. Missions

- A mission is defined by: **location**, **timer/duration**, **difficulty**.
- Target duration: about 15–30 min per mission; exact timers **TBD (playtest)**.
- Harder planets have rarer resources.
- **Generated outside world:** the world outside the ship is generated for every run from a seed and a **biome** (`scenes/locations/generated_location.tscn`, biomes in `scenes/locations/biomes/`). Later the mission selection picks the biome (with the location and difficulty); until then every run picks one at random. Greybox, all values **TBD (playtest)**:
  - 500 × 500 m (about 80 s to cross on foot). The ship lands near the middle on a flat landing site with room in front of the ramp.
  - Ground: rolling hills, terraced in places into plateaus with cliffs between them that nobody can climb; smooth slopes lead up and down elsewhere. A mountain rim closes off the edges (invisible walls behind it).
  - Plants and rocks per biome, scattered in patches. Big ones (trees, boulders) block players, aliens and shots; small ones (bushes, grass) are only looks and fade out in the distance. Ground and plant colors stay muted so ores and aliens stand out.
  - Ore fields of 1–3 nodes of one type. The first two lie 25–55 m from the ramp, so they're found right away, and have the biome's most common ore; rarer ores lie farther away. 10 nests, at least 80 m from the landing site, so the start is quiet. Ore fields and nests only appear where players can walk to from the ship.
  - Biomes so far: *Dust flats* (sandy, high plateaus with cliffs, boulders, spire plants, dry shrubs) and *Overgrowth* (olive ground, gentler hills, funnel trees, puffball bushes, grass, mossy boulders).
  - Generating takes about 1.5 s, a hitch when the ramp button starts a new run; later it happens while the ship flies, hidden by the storm (see [Spaceship](#5-spaceship-hub)).
  - The tests use the small hand-built test location (`scenes/locations/test_location.tscn`) instead: fixed spots, quick to set up.
- Other objectives (beyond mining) are a possible extension, to be explored by playtesting.

### Timer and return

- Greybox: the test map has a 15 min timer (finding ore in the 500 m world takes a while) (`scenes/mission/mission_settings.tres`), **TBD (playtest)**.
- The mission is **over when every player is back aboard**, in time or after the timer ran out. Dead players don't count: once everyone alive is aboard and at least one player made it, the mission ends (see [Death & persistence](#11-death--persistence)).
- The time shows in the world: the ship's beacon (a light column above the roof, seen from far away) is green, turns amber after half the time, red and blinking in the last minute (**TBD (playtest)**) and steady red once the storm hits. A countdown hangs above the door.
- Outside, when the door is farther away (greybox: 12 m, **TBD (playtest)**), an arrow on the ground around the player points to it in the beacon's color, with the countdown next to its tip, so the way back, the urgency and the exact time are visible while the ship is off-screen.

### Timer expiry

- When the timer runs out, the storm becomes lethal: everyone outside the ship takes damage that grows every second. Greybox: 2 HP/s, +2 HP/s per second, so an unhurt player (100 HP) lasts about 9 s (`scenes/mission/mission_settings.tres`, **TBD (playtest)**). Aboard is safe. A grace period is open.
- The storm shows in the world: in the last minute the light dims and a reddish-brown haze builds up in the distance; when the timer runs out it gets thick within a few seconds. Inside the ship the haze fades out (it's an inner room), only the dim light outside still shows the storm. It stays while the players are aboard and clears for the next run.

## 7. Miners

- Placed by the player on ore / mineral / resource nodes.
- One miner per node. The player places it on the nearest free node in range (`place_miner`); a ring on the ground marks that node.
- Fill slowly over time; the player needs to place several for a good haul. Target: an empty miner takes about 2–5 min to fill (so a few fills per mission); exact values **TBD (playtest)**.
- **Stop when full.** Capacity and speed can be upgraded / better miner types.
- Fill level is shown on the miner itself: a glass column fills up in the ore color, and a lamp on top lights up when it's full.
- Art pass: the miner model gets a small display showing the fill counter (amount / capacity) and a timer (time until full).
- **Attacked by aliens** (raiders, see [Combat & aliens](#10-combat--aliens)): a miner has health (greybox 100); the frame flashes white when hit and turns rusty with damage. At zero it **breaks down**: it stops mining and the hose disconnects, so its ore can't be taken out until it's repaired, but it keeps the ore. The frame blinks red while broken.
- **Repair:** a player standing next to a miner (greybox 2.5 m) repairs it automatically, 25 health/s; a broken miner works again only once it's repaired completely (4 s from broken). Damaged miners that still work get repaired too. Values **TBD (playtest)**.
- Defense options like shields and sentry turrets are possible later.
- Whether miners are lost (re-buy) or always available: **TBD (playtest)**.

## 8. Hose transfer

- When the player is within a miner's radius, a hose automatically connects the miner to the player and transfers resources.
- Player can move and shoot while connected.
- Leaving the radius disconnects the hose and stops transfer; re-entering reconnects.
- Each miner has its own hose, so several miners in range transfer at once. In co-op a miner connects to the nearest player in range.
- The hose sags between the miner and the player's back, rests on the ground when it's long, and has the ore color.
- Radius and transfer speed are miner values (upgradable with the miner): greybox 5 m and 30 units/s, so a full miner (180 units) empties in 6 s. **TBD (playtest)**.
- Player carry limit: leaning towards **no limit** (everything is carried until returning to the ship). **TBD (playtest)**.
- Carried resources show on the player's back: one column of canisters per ore type, in the ore color. A canister holds a fixed amount (greybox: one full miner, 180 units, **TBD (playtest)**); full canisters stack up and the top one fills. Without a carry limit the columns keep growing, which also shows how much is at stake.

## 9. Resources

- Several resource types.
- Greybox: three ore types named after their color (cyan, green, violet); real names come with the art pass.
- Different ore types feed different upgrade trees.
- Rarer ores appear on harder planets.

## 10. Combat & aliens

- Aliens outside the ship try to kill the player; player fights back with weapons.
- **Weapons:** several kinds, ranged (projectiles) and melee. The player can't carry all of them: before a mission they pick a **loadout** of a few weapons in the ship and play the mission with it.
- **Attacking:** one attack button; the equipped weapon decides what it does (shoot, swing). Whether melee gets its own button instead is open.
- Number of loadout slots and switching weapons during a mission: **TBD (playtest)**.
- Aliens likely get stronger over time and may be attracted by miners (risk vs. reward). **TBD (playtest)**.
- **Greybox alien** (`scenes/aliens/alien_settings.tres`, all values **TBD (playtest)**): a crimson blob with glowing yellow eyes that show where it faces. It waits until a living player outside the ship comes within 18 m, then chases the nearest one at 4.5 m/s (slower than the player, so running away works) and lunges at it once per second for 10 damage when in reach. A player gets away beyond 20 m or by going aboard: aliens don't hunt inside the ship. 30 HP; it flashes white when hit and shrinks away when it dies. The blaster deals 10 damage per shot, so three hits kill one. Shots don't hurt other players (no friendly fire).
- **Greybox nests** (`scenes/aliens/alien_nest.tscn`, values in `alien_nest_settings.tres`, all **TBD (playtest)**): dark crimson mounds on a slimy patch with a glowing mouth. When the outside world appears, 2 guards hatch around each nest and wait there like any alien. Once the mission starts, each nest also sends out **hunters**: aliens that go for the nearest player outside however far away and don't give up because of distance (only by the player going aboard or dying). The hive escalates with the mission's progress, from the start until the storm hits: a nest hatches a hunter every 45 s at first and every 15 s at the end, with at most 1 and later 4 of its hunters out at once; after a hunter dies, the next one comes a full interval later. The glow in the mouth pulses faster as the hive escalates. Escalation by mining (miners drawing aliens in) and destroying nests are open.
- **Raiders:** nests also send out raiders, a darker strain that goes for the nearest working miner however far away and ignores players on the way, attacking the miner until it breaks down and then moving on to the next one. Once no miner works, they hunt players like hunters. They only hatch while at least one miner works, the first one a full interval after that, and escalate like hunters with their own values: one every 60 s → 25 s, at most 1 → 2 per nest at once (**TBD (playtest)**). Defending miners means shooting raiders before they get there, or repairing behind them.
- **Pathfinding:** aliens walk around rocks and nests along a navigation mesh that the outside world bakes when it appears (miners placed later aren't part of it, aliens steer around them instead), and steer around each other, so swarms spread around their target instead of stacking.

### Alien look and behavior (direction for the art pass)

- **A hive of bio-organic beasts**, not soldiers or machines: insect- and reptile-like creatures with chitin plates over sinewy flesh, claws, mandibles and teeth, several legs, no tech, no clothes. They are one species in many strains, all sharing the same body language and colors, so any alien reads as "one of them" at a glance.
- **Swarms:** most aliens are small and come in numbers; they scuttle low over the ground, fast and erratic. Danger comes from many at once more than from a single one.
- **Strains (ideas):** small fast swarmers (claws, bites), bigger armored brutes that soak up shots, spitters that attack from range with acid or spines, and rare huge monsters. Strains unlock as the hive escalates.
- **Nests:** they live in organic nests / hives grown into the ground, from which they spawn. The ground around a nest can be covered by a living, slimy layer, which also marks their territory.
- **Escalation and attraction:** the longer a mission runs and the more the players mine, the more aliens come and the stronger the strains get; miners draw them in (see Combat above).
- **Readability:** silhouettes with clear head, legs and claws, glowing eyes or glands that show where they face, colors that don't clash with the ore colors (cyan, green, violet) and stand out on the ground. Death should read clearly too (collapse, splatter).

## 11. Death & persistence

- Health shows on the suit: a light band around the collar is green, amber below half, red and blinking below a quarter, and flashes white on damage. Greybox: 100 HP, **TBD (playtest)**.
- On death: the body drops where it stands, **everything carried this run is lost**, and the player respawns in the medical bay with full health.
- When every player is dead, the mission is lost: the beacon turns grey, the countdown says LOST, and after a few seconds (greybox: 3 s, **TBD (playtest)**) everyone respawns aboard and the ramp goes up. The ramp button then starts the next run.
- Co-op: the mission ends when every player is either back aboard or dead, as long as at least one made it back. The dead lose what they carried and respawn aboard when it ends.
- **Later:** players can try to revive each other. Solo needs a balancing mechanic so playing alone isn't unfair without anyone to revive you (**TBD**).
- Back aboard (before the storm gets you): carried resources go into the ship's hold and can be spent. The hold shows as big canisters by the back wall of the cargo bay (greybox: 900 units each, **TBD (playtest)**) and keeps growing over runs (not saved yet, see M3).
- Players are healed for each new run (until the medical bay and armor exist).

## 12. Progression / upgrades

Bought in the ship with resources:

- Weapons
- Armor
- Player skills (idea: an ore scanner that points to ore nodes in range, like the arrow back to the ship)
- Miners (capacity, speed, better types)
- Miner defenses (shields, sentry turrets) — possible

## 13. Development approach

Proof of concept first: make the systems work and be enjoyable using greybox (primitive) visuals, then iterate toward the full game. Art via Blender MCP comes after the loop is fun.

See the milestone plan in [`PLAN.md`](PLAN.md).

## 14. Open questions

- Storm: grace period after the timer runs out, damage curve.
- Reviving other players, and balancing solo play without it.
- Miner ownership (consumable vs. permanent).
- Carry limit yes/no.
- Alien behavior and scaling.
- Generated outside world: which mission values drive it (difficulty, planet), and whether aliens behind cliffs need a silhouette too.
- Weapons: switching during a mission, melee on the attack button or its own.
- Additional mission objectives.
- Private inventory (the locker in each player cabin): a mechanic or not.
- Diegetic UI: how to show off-screen information (a miner is full, aliens attacking a miner elsewhere), text size and readability, and whether main / pause / settings menus can be 3D too.
