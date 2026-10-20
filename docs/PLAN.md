# Lodestorm — Development Plan

Goal: reach a playable, fun core loop as early as possible with greybox visuals, then layer hub, art, VR and co-op on top. Each milestone ends with something playable.

How this file works: **Done** lists what's built (described in [`GAME_DESIGN.md`](GAME_DESIGN.md) and [`TECHNICAL.md`](TECHNICAL.md)), **Todo** the work still to do, in order. Where a design round already decided the details, the step links to its file in [`planned/`](planned/README.md); a step without one gets its own question round first. A finished pull request moves its line from Todo to Done, and the built part of its design moves from `planned/` into `GAME_DESIGN.md`.

## Done

### M0 — Project setup ✓

- Git repo + Godot `.gitignore`, `.gitattributes` (LFS), `.editorconfig`, LICENSE (CC BY-NC-SA 4.0), CONTRIBUTING + CLA, README
- Godot project (version pinned in `.godot-version`), folder structure (one folder per feature in `game/`, `assets/`, `docs/`, `tests/`, see [Project layout](TECHNICAL.md#project-layout))
- gdtoolkit (`gdlint`, `gdformat`) and ruff config, enforced by CI (no local git hooks); every GDScript warning is an error
- GUT tests, run headless; GitHub Actions `ci.yml` (lint, tests) and `build.yml` (Windows/Linux exports); Renovate for dependency updates
- Input map: keyboard/mouse + gamepad actions; rendering settings with the performance targets in mind

### M1 — Outside loop (greybox) ✓

- Player movement, twin-stick aiming, the isometric camera; one ranged weapon on a weapon base class ready for more, incl. melee
- Miners on ore nodes filling over time; the hose transferring while moving
- The ship with its ramp on the right and the ramp button; the mission (and its timer) from the first player stepping out to everyone back aboard; the storm when the timer runs out; win (resources kept) and lose (resources lost)
- Feedback in the world, no 2D HUD: miner fill level, carried resources, timer and storm; the debug overlay for tuning

### M2 — Aliens ✓

- The swarmer chasing and attacking players; nests with hunters escalating over a run; raiders going for the miners; health, death and respawn

### M3 — Ship hub ✓

- The greybox ship interior with its rooms, lifts and floor signs; the outside world generated per run from a seed and a biome
- 3D menus (screens and stations); mission selection at the holo table; the loadout at the armory's lockers (blaster, shotgun, hammer, switching); ship states (space, flight, landed, take-off)
- Medical bay respawn; localization (English and German); upgrade stations (MK1–MK3 from the hold, MK pips); saving and "Reset progress"

### M4 — Progression & quests (so far)

- Ammo made from carried ore, spare magazines, the timing reload, magazine upgrades, handing a teammate ammo; loadout slots for any weapon type
- The skill graph with the first eight skills in four clusters (dash, reload on the move, reinforced suit, regeneration, spare magazines, careful reload, ore scanner, damage readout)
- In-world menus instead of flat terminals: holo cards beside selectable parts, `tab_prev`/`tab_next`, the minimum text size and the fit test in every language; the weapons rack and workbench, the fitting frame, the miners' maintenance pad, the lockers, the bed to quit
- Step 1: the NPC template, with the quartermaster (Brannik) explaining ammo, spare magazines and the timing reload
- Step 2: 14 ores in three bands (color, crystal shape, glow pattern), spread over biomes and planets; the cargo on the back as layered tubes; the hold as silo clusters in the cargo bay
- Step 3: mission locations from map parts (areas and passes, points of interest, set pieces, crates with supply caches; the low rock on the camera's side, silhouettes behind cliffs); **A** the star system's data (six planets with a gas giant, four moons, 25 regions, tiers, four new biomes as greybox); **B** the navigator as a campaign map, and setting course at the cockpit's flight console
- Step 4 A: the drive core's heat shield station in the engine room (one plate per planet inwards, the ship's project paid from the hauls or from the hold, host only), the shield's level and where the ship is in the save (replacing `Region.unlocked`), the locked body's card, longer flights to another body, debug actions (install the next plate, open all)
- Step 4 B: each opened planet raising the highest MK level (MK3 to MK8, a body's tier + 2), aliens (health, damage, nests) and the storm (warning, growth) scaling per tier, the ore-cost rule for every upgrade (a common and a mid ore, from MK3 the signature ore of the level's planet) and for the skills by their depth
- Step 5 A: the title view in the world instead of a main menu (the ship from outside, the name, "Press any button", the credits after a while), the pause panel beside the player in the wrist display's frame (resume, settings, quit; the world stops solo, also on focus loss; the wrist display and its `wrist` action removed), the settings in one component (pause panel and settings terminal), quitting from the panel like the bed, the credits page
- Step 5 B: the suit ring on the ground (health with the hit directions, ammo with reloads and the timing window, spare magazine ticks, the dash, the green band for handing ammo; fixed to the screen, dimming when quiet, tilting with the ground, hidden by cliffs and props), replacing the reload ring, the backpack's spare cells and the dash strip; a probe with shots of crowded moments
- Step 5 C: ore arriving as badges with amounts above the player, the ship's and the ore scanner's arrows on the ring's edge, the target lock as corner brackets in the player's color, players' numbers and colors with teammates' reduced rings (only the local player takes input; debug teammates), the ring's size and "Always show" in the settings
- Step 5 D: the palette viewer (every color the game uses, read from where the game keeps it, normal and for the three common color blindnesses, with the pairs that look closest)
- Step 6 A: the biome framework (barrier, pass style, own area kinds and hazard as data on the biome; gaps with blocked edges and the navigation mesh around them; the location viewer and seed sweeps) with the *Frost fields* (crevasses, snow bridges, ice shelf, frozen lake, slick ice)
- Step 6 B: the *Salt pans* (low walls with sinkholes, raised causeways, sinkhole fields, brine flats) and the *Ash fields* (lava channels before sharp ridges, crust crossings, lava islands, vent fields with bursting vents); gaps with the rock behind them, round pits, filled gaps
- Step 6 C: the *Dust flats* (slot canyons between the mesas, butte fields, dry washes) and the *Glass plains* (terraces on their own levels with ramps between them, shard fences along the drops, slabs beyond, terrace stairs, shard gardens with spires and shards that hurt); plants and rocks limited to some kinds of areas
- Step 6 D: the *Overgrowth* (growth walls: a band of giant stalks and roots before low rock that stops walking and shots; trails with a trodden path and many loops; mires with mud pools that slow walking, not the dash; fungal groves with giant stalks as cover)
- Step 7 A: alien strains and their attacks as data (the role stays on the alien), armor (front-only possible) and stagger, hits that push, jolt and spray ichor or sparks, telegraphs (the wind-up), the swarmer faster and pouncing, the blaster at 8 shots a second, the cap on living aliens
- Step 7 B: the mite (packs, one hit kills), the spitter (keeping away, lobbing acid with a ring where it lands, burning puddles) and the burrower (under the ground, bursting up under its target), modeled; packs of hunters from recipes, which strains hatch where by tier (new ones late in a run, a preview in hard regions), the first biome leanings; guards and raiders as their own strains (the warden with its leash and slam, the gnawer), modeled, instead of a darker tint; a shared creature kit for the aliens' build scripts and six-legged steps
- Step 7 C: the brute (front plates, a soft back, its charge with the lane on the ground), the shrieker (staying back, its scream speeding up the aliens around it and calling a pack), the bloater (a grub that bursts next to players into an acid cloud hurting everyone) and the tender (healing and hardening links), modeled, with their packs; buffed aliens bigger and outlined; working miners drawing raiders to their nearest nest; the hive's frenzy from the storm's warning on
- Step 7 D: the darter (flying over rock at 3 m where only locked shots reach it, diving along a lane and staying low), the stalker (a hunched biped with scything talons, see-through and not lockable from afar, a shimmer close by, its first strike from hiding hitting hard, flesh hooks that slow once it's seen, hit and run), the skimmer on tier 6 (a winged ray circling out of reach of flat shots and spitting acid bolts on the move) and the apex, the Ravager (roaming some locations from tier 3, its steps shaking the view and throwing up dust, shedding swarmers, a charge and a slam), modeled, with the tier 5 and 6 packs and their biomes; players and aliens no longer tinted by a lane
- Step 7 E: debug tools for the aliens: god mode (players lose no health) and switching the aliens' AI off and on, as switches on the debug overlay
- Step 8: destroyable nests (health and armor scaled per tier and player, every weapon and the target lock reaching them, guards defending them, two bursts with their warning, cracks and a dimming glow per stage, the collapse into a husk, its hunters and raiders stopping, the hive's surge, a signal for the quests' "clear nests" goal, a debug shortcut)
- Step 9 A: performance with many aliens, profiled in a late, frenzied tier 6 run with the cap full (46 fps before, 53–66 after with about 75 aliens, 30–40 of them on screen, on the development PC): nests at the cap no longer try to hatch every tick, a pack hatches one alien after another and the hive at most one per physics frame, aliens look up paths less often and only two per frame (a look-up costs about 0.5 ms on a generated world), burrowers and backing-off aliens no longer search the navigation mesh every tick, aliens off screen stop their legs, clips and pose, standing aliens don't move, fliers only push apart from fliers
- Step 9 B1: the audio setup (the buses Master, Effects and Ambience with a volume slider each in the settings, the game heard from the local player, sounds with variants and a random pitch, a limit per sound dropping the farthest, critical cues ducking the rest, menu sounds while paused), the synthesis scripts with takes and a listening page, the manifest of recordings and its license test; the weapons' sounds (shots, the hammer, reloads, the empty click, the timing window's tick and result), the player's (hits, the low-health pulse, the dash, steps on the ground and on the ship's deck); the settings terminal's screen taller
- Step 9 B2: the aliens' sounds (a chitter on noticing and while chasing, strikes, hits in the flesh and on armor, death, in each strain's voice), a telegraph sound for every heavy attack's wind-up and the shrieker's scream; the nests' pulse growing with the escalation, hatching, the burst's warning and the collapse; mining (placing, the drill, the hose, full, breakdown, repair); the ramp, the storm's warning as a critical cue, the last minute's countdown beeps, the storm hitting and the storm all around on the Ambience bus; the vents' rumble and burst, steps on shards and in mud; seamless loops (loop points in the WAV)
- Step 10 A: the weapon framework: a weapon composed of Resources (its feed: magazines or single rounds; its delivery: projectiles or a swing; its effects: damage with stagger and push; its upgrade parts as a list; its origin and draw time), one folder per weapon; the blaster, the shotgun and the hammer renamed Harl, Brask and Dray with their class words ("Harl — Assault rifle"), three parts each (damage, capacity or swing speed, and Harl's fire rate, Brask's pellets, Dray's arc width) with a pip row each; the draw after switching (the weapon swings up from the hip and can't attack meanwhile); blueprints (saved; the debug overlay's "Give blueprints") and building a weapon from its blueprint at the workbench for a fixed ore cost; Harl's ammo warm white; the debug overlay tunes every weapon's resources
- Step 10 B: the armory's weapon wall (free-standing in the middle of the armory; every weapon once in rows by origin, each row named, an origin without weapons gets no row; the player's slot numbers under their loadout's weapons) and the lockers keeping only their two cradles, the camera following the selected weapon to the wall and back, the card floating above the wall; the workbench rack in rows by origin too, right of the weapons room's door, three weapons to a line and growing up; the keyboard and gamepad moving over both racks as a grid, `tab_prev`/`tab_next` jumping a row, the cradle selected last (or an empty one) the slot filled next; for any number of weapons
- Step 10 C1: Pinner (rivet pistol: one shot per press, a battery recharging by itself for no ore, drained when run empty), Grindle (rotary gun: barrels spinning up before the first shot and on for a moment after, walking slower while they spin, a belt of 120) and Quill (rail rifle: hold to charge, let go to fire, a partial charge weaker, a full one piercing every alien in its line, a sight line while charging); the trigger as a Resource of its own (per press, spin, charge), the battery feed, piercing projectiles, the suit ring and gauges the same for every feed (a drained battery, a charge), greybox models, their sounds, parts (recharge, spin-up, charge time) and build costs; the debug overlay tunes them

## Todo

### M4 — Progression & quests (the rest, in order)

Each step builds on the ones before it (steps 1–9 are done).

- [ ] **Step 10 — more weapons** ([`planned/weapons.md`](planned/weapons.md)); until the quests hand out blueprints, the debug overlay unlocks them; greybox meshes, models with the art pass
  - [ ] **C2** ranged weapons 1, the rest (Tremor, Wick)
  - [ ] **D** ranged weapons 2 (Scald, Fulgen, Kith, Nadir, Zenith)
  - [ ] **E** melee weapons (Riven, Auger, Jag, Clout, Mantle)
- [ ] **Step 11 — refinery, crafted miners, timed upgrades** ([`planned/refinery.md`](planned/refinery.md))
  - [ ] **A** `ItemType`, every player's own hold in their own save (moved from the ship's, see [`planned/coop-ore.md`](planned/coop-ore.md)), the eight alloys as data, the refinery at the cargo bay's far end (furnaces unlocked one by one, up to four, one alloy in any amount each, on the wall clock; the ingot rack; recipe discovery; debug unlock until the quests; the engineer's topics on it come with the crew, step 13)
  - [ ] **B** upgrades and skills taking real time (1 min to 6 h each, paid when started, any number at once, shown on the pips and the skill graph)
  - [ ] **C** crafted miners (the miner bay, building, per-miner parts with plating, up to 6 per run, standard-issue miners filling up, picking up and losing them)
  - [ ] **D** drill hardness, alloys in the MK4+ costs and the prototypes' build cost
- [ ] **Step 12 — the station** ([`planned/station.md`](planned/station.md)); concept images first
  - [ ] **A** docking (the navigator, the flight's docking end, the ramp into the hangar, the saved position) and the greybox station map with the camera cut-away and floor signs
  - [ ] **B** the named NPCs with their first topics, ambient colonists
  - [ ] **C** the ore exchange counter (deliveries and requests come with the quests, step 16)
- [ ] **Step 13 — more crew** ([`planned/crew.md`](planned/crew.md))
  - [ ] **A** the seven new crew members at their posts (profiles, greybox accessories, greetings and first topics, the engineer's on the refinery)
  - [ ] **B** health carrying over, the med bed, the medic's topics, the ramp card's hint
  - [ ] **C** reactions to events and the pilot's two radio lines (crew joining through the story waits for the quests)
- [ ] **Step 14 — reasons to move on** ([`planned/risk-reward.md`](planned/risk-reward.md)); after the crafted miners (dry nodes matter once miners are picked up again) and the nests (the rich fields between them)
  - [ ] **A** nodes running dry (amounts, three stages, the dry look, the miner's amber blink, the scanner skipping them) and the rich fields in nest hollows
  - [ ] **B** the late deposit (timing, the meteor's streak, boom and beam, the impact site reserved at generation, the radio line, the nest's pack)
  - [ ] **C** the cargo hatch at the ramp (independent: can come any time earlier)
- [ ] **Step 15 — more skills** ([`planned/skills.md`](planned/skills.md)): one PR with the rescue drone, the hardened canister, rebuilding spares and the miner radar (its amber pointer shows dry nodes too; the sentries with co-op, M7)
- [ ] **Step 16 — quests** ([`planned/quests.md`](planned/quests.md))
  - [ ] **A** quests as data (quest, steps, goals, rewards, story flags), offering with the diamond marker, accepting, hand-ins, the goals deliver (filled from the hauls), reach a site, mine and build, the quest board on the bridge (quests, logs, jobs), tracking
  - [ ] **B** quest sites in regions, the goals clear nests, recover fragments, recover an item and hunt, the navigator's diamonds, amber beams, radio lines
  - [ ] **C** first content: the quartermaster's chain ending in Brask's blueprint, the engineer's first furnace (the other furnaces through later quests), the depot master's requests, reputation pips
  - [ ] **D** and on: the main story act by act ([`planned/story.md`](planned/story.md); a writing round per act first), the expedition's logs

### M5 — Art pass (Blender MCP)

- Models in the art direction ([`GAME_DESIGN.md`](GAME_DESIGN.md#art-direction)): player, miner (with a display for fill counter and time until full, placing and pickup animations, damage states), hose, ore nodes, aliens, ship exterior/interior, weapons
- Leftovers of the first models: dress the generated cliffs with the cliff chunks (`Cliff_*` in `assets/rocks/rocks.glb`) and the wall ore clusters (`Ore_<ore>_wall` in `assets/ores/<ore>.glb`), which needs placement along the cliff edges
- Leftovers of the player model: the death pose assumes flat ground (on slopes the body clips into the ground), the cargo canisters and other props on the player don't hide the occlusion silhouette behind them yet, no hit reaction or turn-in-place clips
- Leftovers of the swarmer: the body stays level on slopes (only the feet follow the ground), no hit reaction or turning clips, its death pose clips into slopes like the player's; every strain is modeled; the spitter's sac and the burrower's ripple need their effects (the glob, the puddle and the mound are greybox, like the brute's lane, the scream's ring, the bloater's acid cloud, the tender's strands, the stalker's shimmer and the Ravager's dust; the bloater's husk keeps glowing after it bursts; the darter's wings beat in the clips only, the swarmers the Ravager sheds appear beside it instead of climbing off its back); the leg IK runs in GDScript (about 40 µs per alien and frame on screen; off screen it stops since M4 step 9 A)
- Leftovers of the loadout: model Brask (with a shell per round in its strip, up to 20 with the capacity upgrade) and Dray (greybox meshes so far) and give Dray a swing animation (its head only sweeps sideways through the arc now; the player holds it in the rifle pose)
- The biomes' textures and meshes (from M4 step 6, see [`planned/biomes.md`](planned/biomes.md)): per biome a ground texture set (floor, barrier, the barrier's lip), its scatter (5–8 rocks and plants) and its feature meshes (snow bridge, crust crossing, shard spikes, fungal stalks, lava), with parallel Blender agents (heavy on the GPU: ask first)
- The sky per body and the far ring of land beyond the map ([`planned/vr-view.md`](planned/vr-view.md)); each body's light, the darkness floor and the storm's light steps ([`planned/art.md`](planned/art.md))
- Basic VFX for mining, shooting, reloading, storm (the sound effects come earlier, M4 step 9)
- Voice-over, after the models ([`planned/voice.md`](planned/voice.md)): **A** the spike (the candidates rendered, the listening page, the comparison and decision written into `TECHNICAL.md`); **B** the pipeline tool, the Voice and Radio buses and "Voice on/off", playback from the bubbles and the radio filter, Brannik voiced; the other NPCs with the tool

### M6 — VR

- OpenXR setup for Steam Frame
- The VR viewpoint ([`planned/vr-view.md`](planned/vr-view.md)): the head on the desktop camera's line, following the character (with the comfort options), the haze around the character, the surrounding flight effects, the ship's cut edges capped
- VR controller mapping onto existing input actions
- 90 FPS profiling; what M4 step 9 A left: with about 100 aliens (many mites) and 60 of them on screen a late frenzy still drops to 44–51 fps on the development PC, mostly what each alien on screen costs (leg IK, animation, rendering) and every moving one (physics, avoidance). Options then: a limit on living bodies besides the cap shares, no leg IK for tiny aliens, far aliens off screen thinking less often

### M7 — Co-op

- Godot high-level multiplayer (host + up to 3 clients), drop-in: friends join a player's session any time, no separate solo mode
- Comms station on the bridge: invites through the platform (Steam overlay), and the comms log (radio lines to listen to again)
- Sync players, miners, aliens, resources
- Player colors with numbers on the suit, silhouettes, rings, lockers and miners ([`planned/art.md`](planned/art.md))
- Reviving each other ([`planned/coop-revive.md`](planned/coop-revive.md)): going down, reviving by standing close, shorter bleed-outs, respawning after 30 s
- Shared ship hub
- Co-op progression: host save plus each player's own gear, tier sync (see [Co-op progression](GAME_DESIGN.md#co-op-progression))

### M8 — Platform services & release

- `PlatformService` abstraction + GodotSteam backend
- Achievements (in-game list + Steam)
- `release.yml` (GitHub Releases on tag) and `steam-deploy.yml`
- Steam store page / Early Access preparation (see [`TECHNICAL.md`](TECHNICAL.md#steam-publishing--first-timer-checklist))

### Afterwards

Epic / GOG ports. Iterate based on playtesting: more planets, alien types, miner types/defenses, mission objectives, NPC/story content.

Not placed in a milestone yet (see [`GAME_DESIGN.md`](GAME_DESIGN.md)): the full story campaign, the second station (the lost expedition's base) and the inhabited outposts, voice-over for all lines, more languages, AI-driven NPCs (experiment).
