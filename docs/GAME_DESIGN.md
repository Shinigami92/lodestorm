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
- Stylized art (low-poly / clean shapes, readable silhouettes, strong colors per resource type).
- Readability over detail: ore types, aliens and miners must be recognizable at a glance from the isometric distance (and in the VR diorama).

### UI: in the world, not on the screen

- **No 2D HUD** where it can be avoided. Game information is shown in the world or on the player (diegetic UI). This also keeps desktop and VR the same: a screen-space HUD doesn't work in VR anyway.
- **Ideas (not final):** health and armor on the player's suit (lights, gauges), carried resources visible on the player (backpack / canisters filling up), ammo on the weapon, miner fill level on the miner itself, mission time via the environment (storm building up, ship beacon) or a display on the player's wrist.
- **3D menus are fine** where a menu is needed: mission selection, upgrade vendors, etc. are panels in the world (e.g. a terminal screen in the ship), not screen overlays.
- **Exceptions:** developer tools (debug overlay for tuning) are allowed in 2D. Whether system menus (main menu, pause, settings) can be 3D too is open.
- How 3D menus work technically (rendering, input with mouse / gamepad / VR controllers, text readability at isometric distance) is to be found out in a spike.

## 4. Core loop

```
Ship hub ──► select mission ──► ship flies to location ──► open ramp = mission starts (timer)
   ▲                                                                    │
   │                                                                    ▼
   │                                                  place miners on resource nodes
   │                                                  fight aliens
   │                                                  collect from miners via hose
   │                                                                    │
   ├── return to ship in time ──► resources saved ──► spend on upgrades ┘
   │
   └── die ──► lose everything carried this run ──► respawn in medical bay
```

## 5. Spaceship (hub)

- Multiple rooms with NPCs.
- **Rooms (initial idea):** bridge / mission terminal, medical bay (respawn point), upgrade rooms (weapons, armor, player skills, miners), ramp / cargo bay.
- **NPCs:** shopkeepers / upgrade vendors, quest givers, and story characters.
- **Mission selection:** at a terminal somewhere in the ship. Target can be another location on the current planet or a new planet. The ship then flies there.
- **Ship states:**
  - *In space:* windows show space; ramp cannot be opened.
  - *Landed, no mission started:* windows/ramp area show the local environment (e.g. storm).
  - The player **cannot go outside without a selected mission**. Opening the ramp starts the mission and its timer.

## 6. Missions

- A mission is defined by: **location**, **timer/duration**, **difficulty**.
- Target duration: about 15–30 min per mission; exact timers **TBD (playtest)**.
- Harder planets have rarer resources.
- Other objectives (beyond mining) are a possible extension, to be explored by playtesting.

### Timer expiry

- When the timer runs out, the storm / weather conditions become lethal and start killing the player. Details (instant vs. escalating damage, grace period) **TBD (playtest)**.

## 7. Miners

- Placed by the player on ore / mineral / resource nodes.
- One miner per node. The player places it on the nearest free node in range (`place_miner`); a ring on the ground marks that node.
- Fill slowly over time; the player needs to place several for a good haul. Target: an empty miner takes about 2–5 min to fill (so a few fills per mission); exact values **TBD (playtest)**.
- **Stop when full.** Capacity and speed can be upgraded / better miner types.
- Fill level is shown on the miner itself: a glass column fills up in the ore color, and a lamp on top lights up when it's full.
- Art pass: the miner model gets a small display showing the fill counter (amount / capacity) and a timer (time until full).
- Can probably be attacked by aliens → defense options like shields and sentry turrets.
- Whether miners are lost (re-buy) or always available: **TBD (playtest)**.

## 8. Hose transfer

- When the player is within a miner's radius, a hose automatically connects the miner to the player and transfers resources.
- Player can move and shoot while connected.
- Leaving the radius disconnects the hose and stops transfer; re-entering reconnects.
- Each miner has its own hose, so several miners in range transfer at once. In co-op a miner connects to the nearest player in range.
- The hose sags between the miner and the player's back, rests on the ground when it's long, and has the ore color.
- Radius and transfer speed are miner values (upgradable with the miner): greybox 5 m and 30 units/s, so a full miner (180 units) empties in 6 s. **TBD (playtest)**.
- Player carry limit: leaning towards **no limit** (everything is carried until returning to the ship). **TBD (playtest)**.

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

## 11. Death & persistence

- On death: the round is lost, **everything carried this run is lost**, player respawns in the medical bay.
- Returning to the ship in time: carried resources are saved and can be spent.

## 12. Progression / upgrades

Bought in the ship with resources:

- Weapons
- Armor
- Player skills
- Miners (capacity, speed, better types)
- Miner defenses (shields, sentry turrets) — possible

## 13. Development approach

Proof of concept first: make the systems work and be enjoyable using greybox (primitive) visuals, then iterate toward the full game. Art via Blender MCP comes after the loop is fun.

See the milestone plan in [`PLAN.md`](PLAN.md).

## 14. Open questions

- Timer expiry behavior details.
- Miner ownership (consumable vs. permanent).
- Carry limit yes/no.
- Alien behavior and scaling.
- Weapons: switching during a mission, melee on the attack button or its own.
- Additional mission objectives.
- Diegetic UI: how to show off-screen information (a miner is full, aliens attacking a miner elsewhere), text size and readability, and whether main / pause / settings menus can be 3D too.
