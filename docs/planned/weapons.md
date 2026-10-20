# Weapons (planned)

Decided 2026-10-17, built in M4 step 10 (see [`PLAN.md`](../PLAN.md)), after the aliens (see [`aliens.md`](aliens.md)), whose strains these weapons are tuned against. All values **TBD (playtest)**; greybox meshes until the art pass. Built so far (steps 10 A, B, C, D and E1, see [Combat & aliens](../GAME_DESIGN.md#10-combat--aliens), [Upgrade stations](../GAME_DESIGN.md#upgrade-stations) and the armory in [Spaceship](../GAME_DESIGN.md#5-spaceship-hub)): the framework (a weapon composed of its feed, trigger, delivery, effects and parts as Resources), Harl, Brask, Dray, Pinner, Grindle, Quill, Tremor, Wick, Scald, Kith, Zenith, Fulgen, Nadir, Riven, Auger and Jag with three parts each, the heat feed, the chain, the gravity well, the chain of slashes ending in a heavy one, the thrust that drills and the held saw with its slow, the draw time, blueprints and building a weapon at the workbench; the armory's weapon wall and the workbench rack in rows by origin, for any number.

## The roster

- **18 weapons:** 12 ranged, 6 melee. Two to start with, then about three per planet (about 120 runs over 40 h, so a new one every 6–7 runs). Fewer melee weapons, since ranged ones have more ways to differ (feed, delivery, range), but every planet brings ranged and melee ones. The count is data: the armory, the workbench and the tests work for any number.
- **Three origins**, which shape their look and group them on the racks:
  - **Colony arms:** the militia's standard issue, plain and sturdy.
  - **Converted mining tools:** the prospectors' tradition; industrial, weathered, hazard paint.
  - **Expedition prototypes:** built by the lost expedition from signature ores and found along its trail; odd and glowing.
- **Names:** a short invented name per weapon (untranslated, like the ores and places), each with its own first letter, and a plain class word under it on the card (translated: "Harl — Assault rifle" / "Harl — Sturmgewehr"). The blaster becomes Harl, the assault rifle. Nadir and Zenith, the expedition's first and last prototype, are a pair on purpose.

| Name | Weapon (German) | Origin | How it plays | Good against |
|---|---|---|---|---|
| **Harl** | assault rifle (Sturmgewehr), today's blaster | colony | fast single shots, magazine | all-round |
| **Brask** | shotgun (Schrotflinte) | colony | pellet fan, shell by shell | close bursts |
| **Grindle** | rotary gun (Rotorkanone) | colony | spins up before firing, a huge belt, a long reload, walks slower while firing | swarms, sustained |
| **Quill** | rail rifle (Schienengewehr) | colony | hold to charge, release; a full charge pierces every alien in a line and shows its line while charging | armored aliens, aliens in a pass |
| **Pinner** | rivet pistol (Nietpistole) | colony | weak, semi-automatic; a battery that recharges, no ore | the ranged fallback when the ore runs out |
| **Scald** | thermal cutter (Schneidbrenner) | tool | short cone, continuous, sets aliens burning; heat | swarms up close |
| **Tremor** | seismic launcher (Seismikwerfer) | tool | lobs charges in an arc over rocks and cliffs, a blast on impact, few rounds | groups, behind cover |
| **Wick** | charge layer (Ladungsleger) | tool | places a few proximity charges on the ground | raiders on the way to the miners |
| **Fulgen** | arc caster (Bogenwerfer) | prototype | lightning to the nearest alien in a cone, jumping to aliens close to it; little aiming | swarms; VR and accessibility |
| **Kith** | mender (Heilstrahler) | prototype | a beam that heals teammates (and revives downed ones from 5 m, see [`coop-revive.md`](coop-revive.md)) and repairs miners, weak damage to aliens; heat | co-op support (solo: repairing miners) |
| **Nadir** | gravity projector (Gravitationswerfer) | prototype | a well that pulls aliens into one spot and holds them, then bursts; battery | setting up the other weapons |
| **Zenith** | star lance (Sternlanze) | prototype | a continuous piercing beam; heat; the campaign's last weapon | everything, at a price in rare ore |
| **Dray** | hammer (Hammer) | tool | a wide arc, several aliens at once | crowds |
| **Riven** | blade (Klinge) | tool | a fast, narrow combo; the third hit is a heavy slash | single fast aliens |
| **Auger** | drill lance (Bohrlanze) | tool | a 4 m thrust that pierces a line; holding drills into one target with rising damage | armored aliens |
| **Jag** | rock saw (Gesteinssäge) | tool | held, continuous, staggers what it touches | holding a choke point |
| **Clout** | power fist (Kraftfaust) | prototype | hold to charge a punch that throws aliens into others | knockback, crowd control |
| **Mantle** | shield (Schild) | prototype | blocks shots and spit in front, also for teammates behind; a bash | spitters, protecting miners |

- **Order over the campaign:** start: Harl, Dray. Torvane (and Lisk): Brask (the quartermaster's chain), Riven, Pinner. Vehra: Grindle, Wick, Clout. Cassor (and Mirr): Quill, Kith, Auger. Gaulm's moons: Tremor, Fulgen, Mantle. Skelde: Scald, Jag, Nadir. Zairen: Zenith. Early weapons are plain, later ones exotic and paid with rarer ores.

## Feeds

Every ranged weapon runs on ore, except the batteries; each feed has its own reload or rhythm and its own display on the weapon:

- **Magazine** (Harl, Quill, Tremor, Wick, Fulgen; built) and **single rounds** (Brask): as built (see [Ammo and reloading](../GAME_DESIGN.md#ammo-and-reloading)).
- **Belt** (Grindle, built): a big magazine with a long reload; the spin-up is its trigger; its drum is the display.
- **Heat** (Scald, Kith, Zenith; built): fires continuously from a fuel cell, which is its magazine (spares first, then refilled from ore). Heat builds while firing and stops it when full. **Venting** works like the timing reload: a press within the window vents at once, so the timing skill carries over; heat sets the rhythm, ore stays the cost.
- **Battery** (Pinner, Nadir; built): recharges by itself, no ore. Pinner as the weak fallback, Nadir because it deals little damage itself.

The spare magazine rules and skills apply to every weapon fed with ore (cells, belts, loads of shells).

## How they play together

- **Against the aliens:** weapons work with two alien values, **armor** and **stagger resistance** (see [`aliens.md`](aliens.md)). Effects instead of damage types: burn, shock (chain), knockback, pull, slow. No elemental weaknesses and nothing only one weapon can kill: each strain has weapons that are better against it, never required ones.
- **Solo and co-op:** no weapon is dead weight alone (Kith repairs miners, Mantle shields miners and sentries, Nadir sets up the player's own second weapon). Co-op combos (Nadir with Tremor, Mantle in front of Quill) are a bonus.
- **Telling them apart:** by silhouette and projectile (each its own shot shape, trail and impact). Ammo colors come from a warm palette (amber, orange, gold, warm white), shared by several weapons and never an ore's hue, so shots never read as ore; the blaster's cyan (Kyrite's color) becomes warm white. The suit ring shows every feed the same way (magazine fill, shells, heat, charge, battery; see [`player-display.md`](player-display.md)).
- **VR:** every weapon aims with one direction (mouse or stick on desktop, the hand in VR); none needs precise aim beyond the screen. Melee swings on the button in VR too, for now.

## Upgrades and getting them

- **Upgrade parts:** three per weapon at the workbench (built for every ranged weapon, Dray, Riven, Auger and Jag): **damage**, **capacity** (magazine, belt, battery, cell, heat; for melee: swing speed) and a **part of its own** (built: Pinner's recharge, Grindle's spin-up, Quill's charge time, Tremor's blast radius, Wick's charges out at once, Scald's burn, Kith's range (its heal rate in place of damage), Zenith's cooling, Fulgen's jumps, Nadir's well radius, Riven's stagger, Auger's drill ramp, Jag's width), for the coming weapons e.g. Mantle: block angle.
- **Getting them:** blueprints from quests (see [`quests.md`](quests.md)): colony arms and tools from the crew's quest chains, the six prototypes from the lost expedition's sites (story). Building one from its blueprint at the workbench for a fixed ore cost is built; later weapons cost the planet's signature ore, the prototypes also alloys (see [`refinery.md`](refinery.md)). In co-op everyone in the session gets the blueprint and builds it from their own hold (own holds: step 11 A). The debug overlay gives the blueprints until then.

## Loadout and switching

- **Draw time** (built, also Grindle's 0.8 s and switching cancelling Quill's charge).
- **Slots stay 2;** a third one comes later as a skill deep in a tree (rare ores), since choosing from many weapons is the point.

## Player animations for melee

Decided 2026-10-20, built right after step 10 E1, before E2: melee weapons need the player's arms to swing, not only the weapon model (ranged weapons don't). Upper-body attack clips in `assets/player/source/player_build.py` (a slash one way and back, an overhead blow, a thrust, a two-handed hold for the saw and the drill), played per attack by the delivery's stroke; the weapon-model motions stay as a small extra. E2's punch (Clout) and bash (Mantle) get their clips with them.

## Data and tests

The composition is built (feeds: magazine, single, battery, heat; triggers: held, per press, spin, charge, press to thrust and hold to drill; deliveries: projectile, also piercing, lobbed with a blast, placed charge, gravity well (pull and hold), cone, beam, chain, swing (also a chain ending in a heavy slash, and a held saw), thrust (also drilling); effects: damage (Fulgen's shock is its stagger), burn, heal, slow). Still to come with Clout and Mantle (step 10 E2): the delivery block and the effect knockback. The tests go over every weapon in `all_weapons.tres`: it attacks, reloads (vents, recharges), has a display, and its card fits in every language.
