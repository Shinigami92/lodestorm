# Lodestorm — Game Design Document

> Status: draft / pre-production. Values marked **TBD (playtest)** are intentionally left open and will be tuned once the systems are playable.

## 1. Pitch

A 3D isometric action/mining game with a dark, realistic sci-fi look. The player lives on a spaceship that acts as the hub. From the ship they pick a mission, the ship flies there, and the player heads out to place miners on resource nodes, fight off aliens, collect the mined resources via a hose, and get back to the ship before the storm hits. Resources are spent on upgrades in the ship. A story campaign leads from planet to planet: better ores open the way to the next planet, where rarer ores wait.

### Story and setting (draft)

- **Setup:** a colony in a newly opened star system runs short of supplies. The players are a prospecting crew supplying it, next to other crews, stations and outposts.
- **The mystery:** a first expedition went missing. Following its trail reveals bit by bit what the players don't know at the start: the storms come from the system's star, which is becoming unstable, and they keep growing stronger. The rare ores only form where its radiation is strongest.
- **The ending:** the colony has to leave the system before a big flare, which needs something built from the rarest ores near the star (a jump drive or shielding, open). So the campaign moves inward, planet by planet.
- **How it's told:** NPCs and their quests drive the main story, in conversations aboard that the players start themselves. During runs, NPCs speak over the radio (quest updates, warnings, short story bits). Players in co-op may talk over it (e.g. on voice chat), so nothing important is only said over the radio: radio lines stay short and can be listened to again aboard (a comms log). The expedition's logs, found as handcrafted pieces on the planets, are optional lore for players who want to dig deeper; the main story never depends on reading them. Cutscenes are unlikely (costly); key moments can use the camera transitions that exist anyway (e.g. the ship taking off and landing).
- **One star system** for the campaign: planets (number open), moons, stations and outposts; built so more systems can follow later.
- **Length:** about 40 h to beat the game; play can go on afterwards (post-game, e.g. higher difficulties with rarer ores, open).

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
| Languages | English and German first, more later (see [Localization and voice](#localization-and-voice)) |
| Asset pipeline | Blender (via Blender MCP) → glTF → Godot |
| License | CC BY-NC-SA 4.0 (own code + assets; third-party addons keep their licenses), CLA for contributors |
| Distribution | Source-available on GitHub (Releases via CI); later Steam, possibly Epic and GOG |
| Achievements | Yes — Steam achievements + in-game list (see [`TECHNICAL.md`](TECHNICAL.md)) |

### Architecture implications

- **Multiplayer-ready from day one:** game state changes go through host-authoritative code paths, solo = local host. Co-op is enabled later without rewriting gameplay.
- **Camera abstraction:** desktop uses an isometric camera; VR uses a "tabletop diorama" view (world in front of the player, looking down onto the character). Same gameplay, swappable camera rig. The rig also supports camera transitions (see below).
- **Input abstraction:** all gameplay reads Godot input actions only, so keyboard/mouse, gamepad and VR controllers map onto the same actions.

### Localization and voice

- **Languages:** English and German first, more later. All player-facing text goes through translations from the start, also the text in the world (3D menus, labels, the room names painted on the floors). German runs about a third longer than English, so panels and labels leave room for it. The game follows the system language; the settings terminal in cabin 1 picks another one and saves it (resetting keeps it). How it works: [`TECHNICAL.md`](TECHNICAL.md#localization).
- **Translations by contributors:** the project is on GitHub, so new languages and fixes come in as pull requests (one translation file per language, readable in a diff; the CLA applies).
- **Subtitles for every spoken line**, in every language, shown in the world, not on the screen: a speech bubble above the speaking NPC, radio lines next to the player. They work the same in VR (in the diorama).
- **Voice-over** (wanted, English only is fine): generated with a free AI text-to-speech model that runs locally, like the concept images. Lines are generated ahead of time (per scripted line, an audio file), not while playing. The model needs good English (German is a bonus), a license that allows selling the game, and distinct voices per NPC that aren't cloned from real people without their consent. Which model: a spike (see [`PLAN.md`](PLAN.md)). Steam asks to disclose AI-generated content on the store page.
- **AI-driven NPCs** (idea for later, an optional experiment): a local language model writing NPC dialogue on the fly. Open: it shares the GPU with rendering (VR needs 90 FPS), it must stay consistent with the quests, it needs content guardrails (Steam asks for them with live-generated content), and its lines would need live voice. Scripted quest dialogue stays the backbone.

## 3. Perspective & art direction

- 3D, isometric camera.
- **The core loop is played in the isometric view** (desktop) / **tabletop diorama** (VR). Camera transitions away from it are allowed for specific moments, e.g. moving closer to a terminal for a 3D menu, the ship taking off and landing, or the ramp opening at mission start. They always return to the main view. In VR, transitions must stay comfortable (e.g. fades or moving the diorama, never the player's head); details **TBD (playtest)**.
- **Desktop camera:** fixed angle looking along the map's diagonal, following the player. Projection (orthographic vs. perspective), angle, distance and follow speed are **TBD (playtest)**; they live in `scenes/camera/iso_camera_settings.tres` (current: perspective, chosen over orthographic after a first comparison).
- **Controls (twin-stick):** movement is relative to the screen ("up" walks up the screen, whatever the camera angle). The player faces the aim direction: the point on the ground under the mouse cursor, or the right stick. Without aim input (gamepad, stick released) the player faces the movement direction. Whichever of mouse and right stick was used last wins.
- **Target lock:** an alien under the mouse cursor (within 4% of the screen height, let go beyond 7%), or the nearest one within 12° of the right stick and 25 m, gets locked on: a ring in the player's color lies under it, the player turns to it and shots fly straight at it, so aliens up or down a slope can be hit too (`scenes/player/player_settings.tres`, **TBD (playtest)**). Without a lock, shots fly level. The mouse aims at the ground under the cursor, also on hills.
- Readability over detail: ore types, aliens and miners must be recognizable at a glance from the isometric distance (and in the VR diorama).
- Players stay visible behind cliffs, trees and walls: the hidden part of their body shows as a see-through silhouette in their color (`assets/shaders/occluded_silhouette.gdshader`).

### Art direction

Found by rating four rounds of concept images (generated locally, not part of the repo); the art pass (M5) refines it per asset.

- **Realistic, dark sci-fi:** PBR materials (painted metal, rubber, glass) with wear: scratches, rust, grime and dust. Real proportions; toy-like, chunky, pastel and cartoon looks are out.
- **Rim light for readability:** players, aliens and machines get a strong rim light (fresnel on their materials), so their silhouettes stay readable on dark ground and from the isometric distance. It's the main tool that keeps the realistic look from turning into mush.
- **Muted world, glowing accents:** ground, rocks, plants and hulls stay desaturated (greys, browns, olive). Saturated color is kept for what the player has to read: glowing ore in its type color, alien eyes and glands, lamps, the hose, the suit's collar band and other status lights. These emissive accents also carry most of the diegetic UI.
- **Human tech vs. the hive:** human gear (ship, miners, suits, weapons) is industrial and weathered; the aliens and their nests are biopunk and organic (chitin, sinew, wet surfaces, glowing glands), see [Alien look](#alien-look-and-behavior-direction-for-the-art-pass).
- **Per asset** (from the concept rounds):
  - **Miner:** a big machine, about twice the player's height, with the glowing glass column and the lamp on top. First model in the game (`assets/miners/miner_glow.glb`): a column on four mechanical legs with two equipment boxes, 3.6 m tall, legs standing around the ore crystals; its body (collision) has a 1.5 m radius, **TBD (playtest)**. When placed, it turns its front toward the camera's view (25° past straight on), so the fill column is never hidden behind its equipment boxes.
  - **Player:** a bulky, dark armored suit; the collar band and the ore canisters on the back glow. First model in the game (`assets/player/player.glb`): helmet with a dark visor, pauldrons, gauntlets and greaves over a padded undersuit, a backpack frame the cargo canisters hang from, a blue chest light; 1.86 m. Animated: idle, running in four directions relative to where the player faces (blended by the velocity, played faster or slower with the speed), the upper body holding the blaster at the hip while armed (relaxed arms aboard the ship, where the weapon is holstered), and falling face down on death.
  - **Ore nodes:** crystal clusters in many shapes and sizes, also growing sideways out of rock walls; each ore type has its own crystal shape besides its color. Modeled in `assets/ores/ores.glb`: per type two ground variants (cyan: long prisms, green: chunky blocks, violet: thin shards, on a cracked rock pad of the deposit's size, crystals at most 1 m tall so they fit between the miner's legs) and one wall cluster for dressing cliffs later.
  - **Ground:** textured per biome with three tileable sets made from real geometry in Blender: the open ground (*Dust flats*: sandy regolith with patches of cracked crust and sparse pebbles; *Overgrowth*: dark damp soil under mats of moss, with roots, stones and pale fungus buds), scree (loose stones at the foot of cliffs and in patches) and rock on the cliffs (*Dust flats*: sandstone strata; *Overgrowth*: dark blocky rock with moss in the joints). Small stones are scattered on top as 3D models, so the ground has real silhouettes up close. Details in [`TECHNICAL.md`](TECHNICAL.md#4-asset-pipeline) (Terrain textures).
  - **Rocks:** jagged and cracked, never smooth. Modeled in `assets/rocks/rocks.glb` (boulders, rubble, outcrops, and cliff chunks for dressing cliffs later), the plants and debris of both biomes in `assets/plants/plants.glb`.
  - **Ship:** stands on landing skids (no wheels); the ramp is at the rear between the thrusters.
  - **Weapons:** glowing parts show their state (the rifle's ammo counter, the power core in the hammer's head). The blaster is modeled as that rifle (`assets/weapons/blaster.glb`); its ammo counter doesn't show the ammo yet. The shotgun (glowing shell strip on its side) and the hammer (glowing core in its head) are greybox meshes so far.
  - **Swarmer:** the first alien model (`assets/aliens/swarmer/swarmer.glb`), close to the concept: a lean runner on four clawed legs, back 0.72 m high (about the player's hip), nose to rump 1.5 m plus a long whip tail; a long head with a toothed jaw and glowing yellow-green eye slits, dark crimson chitin plates over sinew, and two bone scythes rising from its shoulders that arch forward over the head (1.5 m up). Its legs step on their own over the ground, in a trot (the diagonal pairs together); the body breathes while it waits, runs with the head low and the tail streaming, rears back and snaps forward with the jaw open and the blades striking when it attacks, and collapses onto its side when it dies. Guards, hunters and raiders all use it for now; raiders are shaded darker.
  - **Alien nest:** a mound of chitin plates and sinew with tendrils spreading over a slime layer and a glowing mouth on top (`assets/aliens/nest/nest.glb`); the mouth and the glands pulse with the hive's escalation.
- **Cost and performance:** realistic PBR is the most expensive look to build and to render. Texture sizes and LODs are planned per asset type in the art pass, with the VR budget (90 FPS, two views) in mind; **TBD (profiling in M5/M6)**.
- Open: how dark the lighting gets (per biome, as the storm builds up), player colors on the suit, and whether the VR diorama gets a scale-model look (a terrain block with cut edges).

### UI: in the world, not on the screen

- **No 2D HUD** where it can be avoided. Game information is shown in the world or on the player (diegetic UI). This also keeps desktop and VR the same: a screen-space HUD doesn't work in VR anyway.
- **Ideas (not final):** health and armor on the player's suit (lights, gauges), carried resources visible on the player (backpack / canisters filling up), ammo on the weapon, miner fill level on the miner itself, mission time via the environment (storm building up, ship beacon) or a display on the player's wrist.
- **3D menus are fine** where a menu is needed: mission selection, upgrade vendors, etc. are panels in the world (e.g. a terminal screen in the ship), not screen overlays.
- **Using a 3D menu** (from the spike, values **TBD (playtest)**): a player walks up to a terminal and uses it (`interact`). They stand still, and their camera moves in to frame the screen (keeping the isometric angle), so its text reads like a normal menu (the screen fills about half the view's height); nobody standing in front of it hides it. Leaving the menu moves the camera back.
  - **Mouse:** the cursor points at the screen and clicks its buttons, like a 2D menu.
  - **Gamepad and keyboard:** movement (left stick, WASD, also the d-pad and arrow keys) moves the highlight between buttons, `interact` presses the highlighted one; `pause` (Escape, Menu) or B closes the menu.
  - **VR (later):** a controller points at the screen like the mouse does.
  - Screens lean back to face the camera, glow in the dark rooms (cyan text and frames, the highlight in amber like the floor markings) and leave room for longer German texts. One player uses a terminal at a time.
- **System menus:** settings are a terminal in the ship too (so far the language, in cabin 1). Whether the main menu and pause can be 3D is open.
- **Exceptions:** developer tools (debug overlay for tuning) are allowed in 2D.

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
- **Ramp button:** the ramp is closed by default. A button on the inner wall next to the door lowers it, once a mission is picked at the holo table; this also locks the mission and resets its timer. Pressing it again before anyone stepped out raises the ramp again. Once everyone is back aboard, the ramp goes up and the mission is done: the next run needs a newly picked mission.
- **No weapons inside the ship:** weapons are holstered aboard, except in the shooting range, where players try them without a mission. They only work inside the range (not in its doorway), and a force field in the doorway stops every shot, so nothing leaves the range. Targets stand at its far end.
- **Camera inside:** while a player is aboard, the roof and the walls facing the camera are cut away (they still cast shadows), so the camera can see inside. Inner walls between the camera and the corridor keep a low stub, so the rooms stay outlined. On the lower deck, the whole upper deck is cut away too; on the upper deck, the lower deck is hidden under its floor. Some rooms frame themselves: in the shooting range the camera looks at the whole room instead of the player, so the targets stay on screen from the firing line.
- **Two decks**, nose on the left, tail with the ramp on the right (like a cargo plane's rear ramp). A corridor runs along the middle of each deck; lifts join the decks at both ends, one by the bridge and one in the double-height cargo bay, so a run is a loop: ramp → cargo bay → lower deck (upgrades, armory) → lift → bridge (pick a mission) → upper deck → cargo bay lift → ramp.
  - **Upper deck (command and living):** cockpit at the nose, the bridge next to it, then the player cabins, the crew cabins and the mess hall.
  - **Lower deck (work):** medical bay (respawn point) and engine room at the nose, the shooting range, the armory (loadout) and one upgrade room per vendor (weapons, armor, skills, miners), each with a console (see [Upgrade stations](#upgrade-stations)).
- **Armory:** a console by the lockers picks the loadout: one row per weapon of the game with its name, a line on how it plays, ranged or melee, and a button per slot. Weapons the player doesn't own yet are greyed out ("Locked"), which hints at what's still to find. Pressing a slot puts the weapon there (if it's in the other slot, the two swap) or takes it out again; a slot may stay empty. The loadout is locked from the ramp going down until the run is won or lost.
- **Lifts:** a platform for up to four players in a shaft beside the corridor. Stepping on it sends it to the other deck (greybox: after 0.6 s, 2 s ride, **TBD (playtest)**); riders who came along have to step off before it leaves again. Waiting at the gate on the other deck calls it. Gates close the shaft on every deck the platform isn't at.
- **Walking the ship:** the bridge sits at the nose, far from the ramp. Picking a mission starts the flight, and players walk aft and gear up while the ship flies and lands, so the walk isn't dead time (flight time **TBD (playtest)**).
- **Bridge:** missions are selected here. A holo table in the middle projects a hologram of the mission location (a small copy of the location, spinning slowly, the ship's spot highlighted), so players gather around it to see where they're going.
- **Cabins:** one per player (up to 4, cabin 1 closest to the bridge for solo play) with a bed and a locker, and in cabin 1 the settings terminal; the game starts with the player in cabin 1; eight crew cabins for the NPCs with a bed each. Whether the locker becomes a private inventory is open.
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
- **NPCs:** shopkeepers / upgrade vendors, quest givers, and story characters (about eight: e.g. pilot, medic, quartermaster, one vendor per upgrade room, cook), each with a crew cabin. They join the crew as the story goes on, and each one runs a station (armory, medical bay, engineering, ...): recruiting crew is how stations unlock. NPCs give quest chains and have a reputation; finishing their quests unlocks new items and upgrades from them.
- **Stations and outposts:** besides the ship, the players can visit stations and outposts in the system: handcrafted places to walk around in, with NPCs, story, quests, a meeting point for co-op, and maybe exchanging one ore type for another at a bad rate (a safety valve when an ore is missing).
- **Mission selection:** on the bridge, at the holo table. Target can be another location on the current planet or a new planet. The ship then flies there.
  - Greybox: a console beside the holo table offers three missions, one per difficulty (easy, normal, hard), each with its location (biome and a sector code), timer and the biome's ores (from common to rare). While it's used, the camera frames the console and the hologram together. Picking one only shows its location on the hologram, with every ore node as a beam in its ore's color, so players compare the offers, plan their route and pick a mission by the ores they need; "Set course" then confirms it and the ship flies there. Nothing can be picked during the flight. Once landed, another one can be picked until the ramp goes down (the ship takes off and flies there); after the run (won or lost) three new missions are offered.
  - Mission values so far (all **TBD (playtest)**): the timer is 1, 1.5 or 2 times the standard 15 min; the difficulty sets how many of the biome's nests the location has (0.6, 1 and 1.4 times). Planets, rarer ores and quests per mission come later.
  - Later: the bridge gets a full rework. Players first pick a planet or moon, then a location on it. The difficulty is either picked separately, or tied to the location, with far more locations to pick from (open, see [Open questions](#14-open-questions)).
- **Ship states:**
  - *In space:* black space with stars all around and the planet's glow far below; windows show space; the ramp cannot be opened. The game starts here.
  - *Flight:* setting course flies the ship there in three phases (greybox about 40 s, all **TBD (playtest)**): the departure in space (10 s, stars streak past), the descent through thick clouds (25 s; the clouds rush up past the hull and the camera shakes) and the touchdown (5 s, the clouds clear and the ground shows). The ship itself never moves, the world changes around it. The location is generated in the background from the moment its mission is picked at the holo table (no freeze) and goes under the ship in the clouds; if it isn't ready yet, the descent lasts until it is. From a location, the ship first takes off (10 s, climbing through the clouds into space, where the location is left behind).
  - *Landed, no mission started:* windows/ramp area show the local environment (e.g. storm). Weather per biome (dust, rain) comes with the art pass.
  - The player **cannot go outside without a selected mission**; the ramp button only works with one and while landed. The **first player stepping out of the ship starts the mission** and its timer.
  - After a run (won or lost), once the ramp is up and everyone is alive aboard, the ship takes off into space on its own after a few seconds (greybox 5 s, **TBD (playtest)**), unless a new course was set before.

## 6. Missions

- A mission is defined by: **location**, **timer/duration**, **difficulty**, and the quests that can be done there.
- Target duration: about 15–30 min per mission; exact timers **TBD (playtest)**.
- Harder planets have rarer resources.
- **Generated outside world:** the world outside the ship is generated for every run from a seed and a **biome** (`scenes/locations/generated_location.tscn`, biomes in `scenes/locations/biomes/`). The picked mission sets the biome, the seed and (by its difficulty) the number of nests; the world the ship stands in before the first mission is picked has a random biome. Greybox, all values **TBD (playtest)**:
  - 500 × 500 m (about 80 s to cross on foot). The ship lands near the middle on a flat landing site with room in front of the ramp.
  - Ground: rolling hills, terraced in places into plateaus with cliffs between them that nobody can climb; smooth slopes lead up and down elsewhere. A mountain rim closes off the edges (invisible walls behind it). Steep ground shows rock, scree collects at the foot of cliffs and in patches, the high ground is a bit lighter (see [Art direction](#art-direction), Ground).
  - Plants and rocks per biome, scattered in patches. Big ones (trees, boulders) block players, aliens and shots; small ones (bushes, grass) are only looks and fade out in the distance. Ground and plant colors stay muted so ores and aliens stand out.
  - Ore fields of 1–3 nodes of one type. The first two lie 25–55 m from the ramp, so they're found right away, and have the biome's most common ore; rarer ores lie farther away. 10 nests, at least 80 m from the landing site, so the start is quiet. Ore fields and nests only appear where players can walk to from the ship.
  - Biomes so far: *Dust flats* (sandy with a cracked crust, high plateaus with layered sandstone cliffs, boulders, rock outcrops, rubble, small stones, thorny spire plants, dry shrubs, pebbles and bones) and *Overgrowth* (dark soil under olive moss, gentler hills, fleshy tube plants, mushrooms, puffball fungi, fronds, a few boulders and stones).
  - Generating takes about 1.3 s on a worker thread, started when the mission is picked at the holo table; putting the world under the ship costs a short hitch (about 0.2 s) in the clouds during the descent, and its navigation mesh bakes in the background (see [Spaceship](#5-spaceship-hub), Ship states).
  - The tests use the small hand-built test location (`scenes/locations/test_location.tscn`) instead: fixed spots, quick to set up.
- Story missions use the same generated worlds with handcrafted pieces placed in them (e.g. the lost expedition's sites); only stations and outposts are fully handcrafted.

### Quests

- NPCs hand out quests: the main (story) quest and several side quests can be active at once, e.g. destroy a nest, recover something, extract an amount of one ore, find an expedition log.
- A quest is tied to a planet, location or kind of mission, so it can't be done in just any run.
- **Quests can't be missed:** a run that fails one or skips it leaves it open, and it's available again in a later run.
- Optional bonus goals pay off for staying longer (see below).
- Rewards: ores, weapon blueprints, and reputation with the NPC.

### Reasons to move and to stay (risk vs. reward)

Standing at one spot until the timer runs low must not pay off. Directions to try in playtests:

- **Nodes run dry:** each holds a limited amount (e.g. one or two miner fills), so the players have to move on.
- **A mining site draws aliens** the longer it runs (raiders and hunters prefer it).
- **Richer and rarer ore** lies farther from the ship or right next to nests.
- **A late deposit:** a rare one that only appears late in the run, announced in the world (e.g. a meteor strike).
- **Quest goals** elsewhere on the map, and optional bonus goals.
- Maybe a soft carry limit (see [Hose transfer](#8-hose-transfer)).
- Not planned: the storm closing in from the edges before the timer runs out.

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
- **Stop when full.** Capacity and speed can be upgraded (see [Upgrade stations](#upgrade-stations)) / better miner types.
- Fill level is shown on the miner itself: a glass column fills up in the ore color, and a lamp on top lights up when it's full. Aliens attack it from its surface: their reach counts from the edge of its body, not its center.
- Art pass: the miner model gets a small display showing the fill counter (amount / capacity) and a timer (time until full).
- **Attacked by aliens** (raiders, see [Combat & aliens](#10-combat--aliens)): a miner has health (greybox 100); the frame flashes white when hit and turns rusty with damage. At zero it **breaks down**: it stops mining and the hose disconnects, so its ore can't be taken out until it's repaired, but it keeps the ore. The frame blinks red while broken.
- **Repair:** a player standing next to a miner (greybox 2.5 m) repairs it automatically, 25 health/s; a broken miner works again only once it's repaired completely (4 s from broken). Damaged miners that still work get repaired too. Values **TBD (playtest)**.
- Defense options like shields and sentry turrets are possible later.
- **Ownership:** miners are built in the ship and kept. Each crafted miner is upgraded on its own (capacity, speed, drill type), so it's worth protecting. Aliens only break it down (repairable, see above); it's **lost only when it's left on the planet** when the ship lifts off, or when every player dies.
- **Placing and picking up** takes a few seconds (3–10 s, **TBD (playtest)**), with animations for both, so collecting the miners at the end of a run is a decision against the clock. The model also needs damage states for the art pass.
- **Never stuck:** the ship always has a few standard-issue miners, refilled for free between runs: weaker and not upgradable.
- **Drill types:** harder and rarer ores need better drills, so miners have their own progression.

## 8. Hose transfer

- When the player is within a miner's radius, a hose automatically connects the miner to the player and transfers resources.
- Player can move and shoot while connected.
- Leaving the radius disconnects the hose and stops transfer; re-entering reconnects.
- Each miner has its own hose, so several miners in range transfer at once. In co-op a miner connects to the nearest player in range.
- The hose sags between the miner and the player's back, rests on the ground when it's long, and has the ore color.
- Radius and transfer speed are miner values (upgradable with the miner): greybox 5 m and 30 units/s, so a full miner (180 units) empties in 6 s. **TBD (playtest)**.
- Player carry limit: leaning towards **no limit** (everything is carried until returning to the ship); a soft limit (a full load slows the player down) is an option. **TBD (playtest)**.
- Carried resources show on the player's back: one column of canisters per ore type, in the ore color. A canister holds a fixed amount (greybox: one full miner, 180 units, **TBD (playtest)**); full canisters stack up and the top one fills. Without a carry limit the columns keep growing, which also shows how much is at stake.

## 9. Resources

- **Many ore types:** about 10–15, with invented, mineral-like names. Greybox: three named after their color (cyan, green, violet); real names come with the art pass.
- **Each ore is identifiable at a glance** by its color, its crystal shape and its glow pattern (steady, pulsing, flickering, ...), so telling them apart never depends on color alone.
- **Spread over the planets:** common ores everywhere, 2–3 new ones per planet, the rarest near the star. A single run has about 3–5 types.
- **Refinery** (a station in the ship): combines 2–3 ores into alloys. Higher upgrades cost alloys, so early ores stay useful. Refining takes real time, passing while playing and while away ("come back tomorrow"), and never blocks the story.
- **Ores are the only currency:** everything is bought with ores and alloys; there are no experience levels.

## 10. Combat & aliens

- Aliens outside the ship try to kill the player; player fights back with weapons.
- **Weapons:** a fixed set of unique weapons, ranged (projectiles) and melee, each with its own in-game name: e.g. assault rifle, shotgun, minigun, hammer, sword, power fist. New ones unlock as blueprints from quests and the story. Ranged weapons use **ammo** (shown on the weapon); a bigger magazine is an upgrade, and a player can refill teammates' ammo, a support role in co-op. During a run the suit makes ammo from carried ore; any ore type works, so it never depends on what a location has (rates per ore type **TBD (playtest)**). The player can't carry all of them: before a mission they pick a **loadout** of a few weapons in the ship and play the mission with it.
- **Enemies:** only aliens for now, one species in several roles (strains, see below).
- **Attacking:** one attack button; the equipped weapon decides what it does (shoot, swing). Whether melee gets its own button instead is open.
- **Loadout slots take any weapon type**, so a melee-only loadout is a real choice. Melee is never required to get on in a run (nothing that only a melee weapon can do).
- **Starting weapons:** a new player owns the blaster (ranged) and the hammer (melee), and both are in the loadout. The others are unlocked through the game (blueprints, M4); the first one to find is the shotgun. Owned weapons and the loadout belong to each player (see [Co-op progression](#co-op-progression)).
- **First weapons** (`scenes/weapons/`, values **TBD (playtest)**): the **blaster** fires fast single shots that reach far; the **shotgun** fires a fan of pellets (7 over 30°) that only reaches 12 m; the **hammer** swings at everything within 2.5 m in a 120° arc in front of the player (also several aliens at once), unless something solid is in the way, about 1.5 times a second.
- **Loadout slots:** 2 (`PlayerSettings.loadout_slots`, **TBD (playtest)**). `switch_weapon` (Q, gamepad Y / Triangle) equips the weapon in the next filled slot, also during a mission.
- Aliens likely get stronger over time and may be attracted by miners (risk vs. reward). **TBD (playtest)**.
- **Alien** (`scenes/aliens/alien_settings.tres`, all values **TBD (playtest)**): the swarmer (see [Art direction](#art-direction)); its glowing eyes show where it faces. It waits until a living player outside the ship comes within 18 m, then chases the nearest one at 4.5 m/s (slower than the player, so running away works) and strikes at it once per second for 10 damage when in reach. A player gets away beyond 20 m or by going aboard: aliens don't hunt inside the ship. 30 HP; it flashes white when hit; when it dies it collapses, lies still for a moment and sinks into the ground. The blaster deals 10 damage per shot, so three hits kill one. Shots don't hurt other players (no friendly fire).
- **Greybox nests** (`scenes/aliens/alien_nest.tscn`, values in `alien_nest_settings.tres`, all **TBD (playtest)**): dark crimson mounds on a slimy patch with a glowing mouth. When the outside world appears, 2 guards hatch around each nest and wait there like any alien. Once the mission starts, each nest also sends out **hunters**: aliens that go for the nearest player outside however far away and don't give up because of distance (only by the player going aboard or dying). The hive escalates with the mission's progress, from the start until the storm hits: a nest hatches a hunter every 45 s at first and every 15 s at the end, with at most 1 and later 4 of its hunters out at once; after a hunter dies, the next one comes a full interval later. The glow in the mouth pulses faster as the hive escalates. Escalation by mining (miners drawing aliens in) and destroying nests are open.
- **Raiders:** nests also send out raiders, a darker strain that goes for the nearest working miner however far away and ignores players on the way, attacking the miner until it breaks down and then moving on to the next one. Once no miner works, they hunt players like hunters. They only hatch while at least one miner works, the first one a full interval after that, and escalate like hunters with their own values: one every 60 s → 25 s, at most 1 → 2 per nest at once (**TBD (playtest)**). Defending miners means shooting raiders before they get there, or repairing behind them.
- **Pathfinding:** aliens walk around rocks and nests along a navigation mesh that the outside world bakes when it appears (miners placed later aren't part of it, aliens steer around them instead), and steer around each other, so swarms spread around their target instead of stacking.

### Alien look and behavior (direction for the art pass)

- **A hive of bio-organic beasts**, not soldiers or machines: insect- and reptile-like creatures with chitin plates over sinewy flesh, claws, mandibles and teeth, several legs, no tech, no clothes. They are one species in many strains, all sharing the same body language and colors, so any alien reads as "one of them" at a glance.
- **Swarms:** most aliens are small and come in numbers; they scuttle low over the ground, fast and erratic. Danger comes from many at once more than from a single one.
- **Strains (ideas):** small fast swarmers (claws, bites), bigger armored brutes that soak up shots, spitters that attack from range with acid or spines, and rare huge monsters. Strains unlock as the hive escalates. Looks from the concept rounds:
  - **Swarmer:** a lean, dog-sized runner on four clawed legs with a long toothed jaw and scythe-like bone blades on its back. Modeled close to the concept (see Art direction above).
  - **Brute:** a four-legged rhino-beetle with heavy layered armor plates and horns. The plates are chitin and must not read as riveted metal.
  - **Spitter:** a beetle body with a swollen, glowing acid sac on its back; the acid glows in flight.
- **Nests:** they live in organic nests / hives grown into the ground, from which they spawn. The ground around a nest can be covered by a living, slimy layer, which also marks their territory. Look: a low, wide mound of chitin and sinew with a glowing opening on top and tendrils spreading over the slime.
- **Escalation and attraction:** the longer a mission runs and the more the players mine, the more aliens come and the stronger the strains get; miners draw them in (see Combat above).
- **Readability:** silhouettes with clear head, legs and claws, glowing eyes or glands that show where they face, colors that don't clash with the ore colors (cyan, green, violet) and stand out on the ground. Death should read clearly too (collapse, splatter).

## 11. Death & persistence

- Health shows on the suit: a light band around the collar is green, amber below half, red and blinking below a quarter, and flashes white on damage. Greybox: 100 HP, **TBD (playtest)**.
- On death: the body drops where it stands, **everything carried this run is lost**, and the player respawns in the medical bay with full health.
- When every player is dead, the mission is lost: the beacon turns grey, the countdown says LOST, and after a few seconds (greybox: 3 s, **TBD (playtest)**) everyone respawns aboard and the ramp goes up. The next run starts with a newly picked mission.
- Co-op: the mission ends when every player is either back aboard or dead, as long as at least one made it back. The dead lose what they carried and respawn aboard when it ends.
- When every player dies, the miners on the planet are lost too (see [Miners](#7-miners)).
- **Not too punishing:** losses should hurt, but not set players back for long.
- **Rescue drone** (a skill): once per run it revives a player where they fell, in solo and in co-op, so playing alone isn't unfair without anyone to revive you.
- A skill or upgrade keeps part of the carried ore on death (e.g. a canister that survives).
- Back aboard (before the storm gets you): carried resources go into the ship's hold and are spent at the upgrade stations. The hold shows as big canisters by the back wall of the cargo bay (greybox: 900 units each, **TBD (playtest)**) and keeps growing over runs.
- Players are healed for each new run (until the medical bay exists).
- **Saving:** automatic, no save button. Progress (the hold, the owned weapons, the loadout, the upgrade levels) is saved whenever it changes aboard; what changes during a mission is saved once it's over, so quitting mid-mission loses that run like dying (the game starts aboard in space again). There is one save. **Reset progress** on the settings terminal wipes it: it asks three times, each time saying that all progress is lost for good, and each confirm button waits a moment (greybox: 1 s, **TBD (playtest)**) so quick repeated presses can't get through. The settings (language) stay. Only while the player is alone: with others in the session the button is disabled with a hint, and everyone keeps their progress.

## 12. Progression / upgrades

Bought in the ship with ores and alloys (no experience levels, no player classes):

- **Weapons:** each one upgraded on its own, also part by part, in MK levels (e.g. MK1–MK5).
- **Armor:** the suit, in MK levels.
- **Skills:** e.g. dash, more health, health regeneration, the rescue drone, unlocking the miner radar or an ore scanner (points to ore nodes in range, like the arrow back to the ship), unlocking sentries. Skill trees can be maxed out completely; the choice is what to get first. A run's role comes from the loadout (e.g. a healer loadout), not from a class.
- **Miners:** capacity, speed, drill types, defenses (shields, sentry turrets).
- **New planets:** better ores open the way to the next planet (see [Story](#story-and-setting-draft)).

### Upgrade stations

- One console per upgrade room on the lower deck: **weapons, armor and miners** (the skills room stays empty until the skills exist, M4). Each one lists its upgrades with the MK level, how much the next level improves (compared to MK1), the next level's cost in ore and an "Upgrade" button; the header shows what the hold has of the ores they cost. Costs the hold can't pay show in red and can't be bought; upgrades of weapons the player doesn't own yet are greyed out ("Locked"). Like the loadout, buying is locked while a mission is underway.
- **Paid from the ship's hold.** Each level costs more and asks for rarer ores: MK2 costs cyan, a weapon's MK3 cyan and green, the armor's and the miners' MK3 green and violet.
- **Greybox upgrades** (`scenes/upgrades/`, MK1–MK3, multipliers and costs **TBD (playtest)**): every weapon's damage (+25 % / +50 %), the suit armor's health (+25 % / +50 %: 100 → 125 → 150 HP), and for the miners the drill (fill rate +25 % / +50 %), the ore tank (capacity +50 % / +100 %) and the hose (range and transfer rate +25 % / +50 %). Buying armor adds the extra health right away.
- **Each player has their own levels** (like their weapons). Until crafted miners exist (M4, each upgraded on its own), the miner upgrades apply to every miner the player places.
- **Shown in the world:** a row of small pips, one per MK level, the reached ones glowing: on each weapon (behind the blaster's sight, on the shotgun's receiver, on the hammer's head) and on top of the helmet for the armor (the isometric camera always sees it).

### Co-op progression

- The **host's save** holds the ship, story, crew and quests. Each player keeps their **own weapons, skills and loadout** and brings them along; players can inspect each other's gear. No trading for now.
- Everyone gets the full haul in their own save; nothing is split.
- **Drop-in:** friends can join a player's session at any time, also while they're alone on their ship; solo and co-op aren't separate modes, solo just means nobody else is in the session. Progress can only be reset then (see [Death & persistence](#11-death--persistence)).
- Each player places **their own miners**; a lost miner is lost for its owner.
- **Tier sync:** each planet and difficulty has a maximum MK level, and stronger gear counts as that level, so guests with better gear don't carry the host through. Weapon types and unlocked skills stay. Alien numbers and health scale with the player count.

## 13. Development approach

Proof of concept first: make the systems work and be enjoyable using greybox (primitive) visuals, then iterate toward the full game. Art via Blender MCP comes after the loop is fun.

See the milestone plan in [`PLAN.md`](PLAN.md).

## 14. Open questions

- Storm: grace period after the timer runs out, damage curve.
- Story: the crew and characters in detail, what the colony builds to escape (jump drive or shielding), number of planets, the post-game.
- Reviving each other in co-op beyond the rescue drone.
- Carry limit: none or soft (slower with a full load).
- Alien behavior and scaling.
- Generated outside world: which mission values drive it (difficulty, planet), and whether aliens behind cliffs need a silhouette too.
- Mission selection: difficulty picked separately or tied to the location (then with far more locations to pick from); how picking a planet or moon and then a location on it works on the reworked bridge.
- Weapons: whether switching during a mission stays free or takes time (or is limited), melee on the attack button or its own.
- Refinery: how it works in co-op.
- Voice-over: which local text-to-speech model; whether AI-driven NPCs are worth an experiment.
- Co-op: where a guest's haul goes and what it buys besides their own gear: the hold is the host's ship and only in the host's save, yet everyone gets the full haul in their own save, so what do guests pay their upgrades with (their own ship's hold back home, a personal stash, ...)?
- Private inventory (the locker in each player cabin): a mechanic or not.
- Cockpit: setting course at a flight console in the cockpit instead of at the holo table (the holo table picks and previews the mission, the cockpit confirms it and launches the flight), which gives the cockpit a purpose.
- Armory rework once there are many more weapons: each player picks the loadout at their own locker, from the weapons inside it, instead of one console listing every weapon.
- Diegetic UI: how to show off-screen information (a miner is full, aliens attacking a miner elsewhere), and whether the main menu and pause can be 3D too.
