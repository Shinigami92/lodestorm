# Aliens and the feel of combat (planned)

Decided 2026-10-17, built in M4 step 7 (see [`PLAN.md`](../PLAN.md)). All values **TBD (playtest)**; greybox bodies until the art pass. Built so far (step 7 A): strains and their attacks as data with the role on the alien, armor and stagger, hits that push and spray, the wind-up as the telegraph, the swarmer's pounce, the blaster at 8 shots a second and the cap on living aliens, with one strain, the swarmer, in three roles (guard, hunter, raider); see [Combat & aliens](../GAME_DESIGN.md#10-combat--aliens). This file keeps the rest.

## Strains and roles

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

## Where they live

- **Nests hatch by tier and biome:** each nest has a hatch table (data): which strains, in which roles, by the hive's escalation. A tier's new strains appear late in a run first, then from the start on the next planet.
- **Biome leanings:** each biome favors some strains (burrowers in the Dust flats and Salt pans, stalkers in the Overgrowth, darters around the cliffs of the Ash fields and Glass plains, mites everywhere), never exclusively, so no biome needs a particular weapon (see [`biomes.md`](biomes.md)).
- **Hard regions preview** one strain of the next tier, so the next planet isn't a wall.
- **Packs:** hunters come in packs, not one by one, from a recipe per tier (e.g. tier 3: four swarmers and a Brute, or two spitters and a Shrieker).
- **Tiers** also scale health, damage and nests (built, see Tiers in [Missions](../GAME_DESIGN.md#6-missions)).

## Pressure over a run

- **Miners draw them in:** each working miner raises its nearest nests' raider rate (+10 %, a miner on a signature ore +20 %), so a big mining site pays off but gets busy.
- **The end of a run:** during the storm's warning, the hive frenzies: aliens 15 % faster, hunters hatching at their highest rate. It pushes the way back without new rules.

## Telegraphs and feedback

- **Telegraphs on the ground:** acid glows in flight and shows where it lands as a ring on the ground; the Brute's charge shows its line on the ground (red dashed, see [`player-display.md`](player-display.md)). Each new strain's wind-up uses the built one (crouching or rearing, glands brightening), with its sound (see [`sfx.md`](sfx.md)).
- **Projectiles** tell the weapons apart (shape, trail, impact).
- **Death:** bloaters burst (the others collapse and sink as built).

## Limits

- **How many at once:** mites and darters count as a share towards the built cap (their `cap_share`). Alien numbers and health still scale with the player count in co-op (M7).
- **Colors:** every strain glows in the swarmer's yellow-green (acid included), which no ore uses; raiders and stalkers have darker chitin (see [Alien look](../GAME_DESIGN.md#alien-look-and-behavior-direction-for-the-art-pass)).
