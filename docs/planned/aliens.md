# Aliens and the feel of combat (planned)

Decided 2026-10-17, built in M4 step 7 (see [`PLAN.md`](../PLAN.md)). All values **TBD (playtest)**; greybox bodies until the art pass. Today there is one strain, the swarmer, in three roles (guard, hunter, raider), see [Combat & aliens](../GAME_DESIGN.md#10-combat--aliens).

## Strains and roles

- **Two things:** a **strain** is the body (how it moves and fights), a **role** is what it goes for (guard: waits at its nest; hunter: the nearest player; raider: the nearest working miner). Most strains can take any role; raiders keep their darker chitin, so the role still reads at a glance. In the data, a strain is a Resource (body, values, attacks) and the role sits on the alien, so a new strain is data plus a scene.
- **10 strains and one apex,** two new ones per tier, so every planet brings something new to learn. The count is data: nests, packs and tests work for any number. Names are descriptive and translated, the way the crew would call them.

| Tier | Strain | Size | How it fights | Weak to | Look |
|---|---|---|---|---|---|
| 1 | **Swarmer** | medium | a runner with a short pounce (4 m) when close | anything | as modeled |
| 1 | **Mite** | tiny | packs of 6–10, 10 HP, a quick bite; one hit kills | wide hits (hammer, shotgun, thermal cutter, arc caster) | a knee-high tick with a glowing back |
| 2 | **Spitter** | medium | keeps 10–14 m away and lobs acid that leaves a burning puddle for a few seconds; flees when approached | range, the shield, charging at it | a beetle with a glowing acid sac |
| 2 | **Burrower** | medium | travels underground (a ripple in the ground, can't be hit), surfaces under its target with a bite; prefers raiding | standing still is the danger; hit it while it's up | a flat, shovel-headed digger |
| 3 | **Brute** | big | armored front plates (high armor and stagger resistance), a soft back; a telegraphed charge in a line | flanking, piercing (rail rifle, drill lance), heavy hits | a rhino-beetle with horns |
| 3 | **Shrieker** | medium | stays behind the pack and screams: aliens nearby speed up and more come; flees | focus fire, range | a long neck with a glowing throat sac |
| 4 | **Bloater** | big, slow | bursts on contact or death into an acid cloud that hurts aliens too; prefers raiding | killing it at range, near other aliens | a swollen sac on thin legs |
| 4 | **Tender** | medium | heals and hardens aliens near it (a pulsing link); stays back | focus fire | glowing gland clusters and tendrils |
| 5 | **Darter** | small, flying | winged packs that fly low over cliffs and rock (no paths) and dive at players | arc caster, shotgun, the target lock | translucent wings, a sting |
| 5 | **Stalker** | medium | see-through until it attacks (a shimmer, visible within 8 m and as a silhouette behind cliffs), ambushes from cover | arc caster, wide hits, sticking together | chameleon chitin |
| 3+ | **Ravager** (apex) | huge | at most one per region, roams or guards a rich site, announced by tremors; slams, charges, sheds swarmers | everything together; avoiding it is fine | the rare huge monster |

Tier 6 brings no new strain: its danger comes from mixed packs of all of them, and the Ravager more often. The weapons named in the table are planned too (see [`weapons.md`](weapons.md)).

## Armor and stagger

The values the weapons work with:

- **Armor:** a flat reduction per hit; at least 25 % of the damage always gets through, so no alien is immune. Many small hits (the rotary gun) suffer, heavy hits (the rail rifle, the hammer) don't. The Brute's armor is only on its front.
- **Stagger:** each hit adds stagger by weapon; past the strain's threshold it's staggered (0.5 s, its attack is interrupted). Mites and swarmers stagger easily, the Brute and the Ravager barely.
- **Readable without numbers:** a hit on armor throws grey sparks and chips, a hit on flesh glowing ichor.

## Swarmer and blaster

The swarmer runs 5.2 m/s (still slower than the player's 6, so running away works but isn't free) and pounces 4 m when within 6 m, after crouching for 0.4 s. The blaster fires 8 shots a second instead of 6 (same damage). Hunters keep chasing as now; the others give up beyond their chase range.

## Where they live

- **Nests hatch by tier and biome:** each nest has a hatch table (data): which strains, in which roles, by the hive's escalation. A tier's new strains appear late in a run first, then from the start on the next planet.
- **Biome leanings:** each biome favors some strains (burrowers in the Dust flats and Salt pans, stalkers in the Overgrowth, darters around the cliffs of the Ash fields and Glass plains, mites everywhere), never exclusively, so no biome needs a particular weapon (see [`biomes.md`](biomes.md)).
- **Hard regions preview** one strain of the next tier, so the next planet isn't a wall.
- **Packs:** hunters come in packs, not one by one, from a recipe per tier (e.g. tier 3: four swarmers and a Brute, or two spitters and a Shrieker).
- **Tiers** also scale health, damage and nests (see [`opening-planets.md`](opening-planets.md)).

## Pressure over a run

- **Miners draw them in:** each working miner raises its nearest nests' raider rate (+10 %, a miner on a signature ore +20 %), so a big mining site pays off but gets busy.
- **The end of a run:** during the storm's warning, the hive frenzies: aliens 15 % faster, hunters hatching at their highest rate. It pushes the way back without new rules.

## Telegraphs and hit feedback

- **Telegraphs:** every heavy attack has a wind-up readable from the isometric camera and in VR (glands brighten, the body crouches or rears up, 0.4–0.8 s), with a sound (see [`sfx.md`](sfx.md)). Acid glows in flight and shows where it lands as a ring on the ground; the Brute's charge shows its line on the ground (red dashed, see [`player-display.md`](player-display.md)).
- **Aliens hit:** the white flash, ichor or sparks, a small push back by weapon and a short stagger animation.
- **Projectiles** tell the weapons apart (shape, trail, impact).
- **The player hit:** the collar flashes as now, and a short red mark on the suit ring points to where the hit came from (in the world, no HUD; see [`player-display.md`](player-display.md)); the screen shake stays small (none in VR).
- **Death:** collapse, splatter, sinking into the ground as now; bloaters burst.
- No hit-stop (co-op and VR don't take it well).

## Limits

- **How many at once:** a cap on living aliens (greybox 60 on desktop, lower in VR), mites and darters counting as a fraction; nests wait while the cap is reached. Alien numbers and health still scale with the player count in co-op.
- **No drops:** aliens drop nothing; ore only comes from mining. Killing is about safety, not loot, so the miners stay central. The Ravager guards a rich site instead.
- **Colors:** every strain glows in the swarmer's yellow-green (acid included), which no ore uses; raiders and stalkers have darker chitin (see [Alien look](../GAME_DESIGN.md#alien-look-and-behavior-direction-for-the-art-pass)).
