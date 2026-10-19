# Aliens and the feel of combat (planned)

Decided 2026-10-17, built in M4 step 7 (see [`PLAN.md`](../PLAN.md)). All values **TBD (playtest)**; greybox bodies until the art pass. Built so far (step 7 A): strains and their attacks as data with the role on the alien, armor and stagger, hits that push and spray, the wind-up as the telegraph, the swarmer's pounce, the blaster at 8 shots a second and the cap on living aliens, with one strain, the swarmer, in three roles (guard, hunter, raider); step 7 B: tiers 1–2 (the mite, the spitter, the burrower, modeled), the packs, which strains hatch where by tier (new strains late in a run, the preview in hard regions) and the first biome leanings; step 7 C: tiers 3–4 (the brute with its charge, the shrieker, the bloater, the tender, modeled), miners drawing raiders and the hive's frenzy; see [Combat & aliens](../GAME_DESIGN.md#10-combat--aliens). This file keeps the rest; the roster below lists the built strains too, for the whole picture.

## Strains and roles

- **10 strains and one apex,** two new ones per tier, so every planet brings something new to learn. The count is data: nests, packs and tests work for any number. Names are descriptive and translated, the way the crew would call them.

| Tier | Strain | Size | How it fights | Weak to | Look |
|---|---|---|---|---|---|
| 1 | **Swarmer** | medium | a runner with a short pounce (4 m) when close | anything | as modeled |
| 1 | **Mite** | tiny | packs of 6–10, 10 HP, a quick bite; one hit kills | wide hits (hammer, shotgun, thermal cutter, arc caster) | a knee-high tick with a glowing back |
| 2 | **Spitter** | medium | keeps 10–14 m away and lobs acid that leaves a burning puddle for a few seconds; flees when approached | range, the shield, charging at it | a beetle with a glowing acid sac |
| 2 | **Burrower** | medium | travels underground (a ripple in the ground, can't be hit), surfaces under its target with a bite | standing still is the danger; hit it while it's up | a flat, shovel-headed digger |
| 3 | **Brute** | big | armored front plates (high armor and stagger resistance), a soft back; a telegraphed charge in a line | flanking, piercing (rail rifle, drill lance), heavy hits | a rhino-beetle with horns |
| 3 | **Shrieker** | medium | stays behind the pack and screams: aliens nearby speed up and more come; flees | focus fire, range | a long neck with a glowing throat sac |
| 4 | **Bloater** | big, slow | bursts next to a player or on death into an acid cloud that hurts aliens too; a hunter, never at miners | killing it at range, near other aliens | a fat grub on stubby legs, its back a swollen bladder |
| 4 | **Tender** | medium | heals and hardens aliens near it (a pulsing link); stays back | focus fire | glowing gland clusters and tendrils |
| 5 | **Darter** | small, flying | winged packs that fly low over cliffs and rock (no paths) and dive at players | arc caster, shotgun, the target lock | translucent wings, a sting |
| 5 | **Stalker** | medium | see-through until it attacks (a shimmer, visible within 8 m and as a silhouette behind cliffs), ambushes from cover | arc caster, wide hits, sticking together | chameleon chitin |
| 3+ | **Ravager** (apex) | huge | at most one per region, roams or guards a rich site, announced by tremors; slams, charges, sheds swarmers | everything together; avoiding it is fine | the rare huge monster |

Besides the hunters, the nests' **guards and raiders are their own strains** (built in step 7 B, so a role shows in the body, not in a tint): the **warden** guards every nest on every tier (big, front-armored, a slam; more guard strains may come with later tiers), the **gnawer** is the first raider (tier 1, crushing jaws); later raider strains may come with later tiers.

Tier 6 brings no new strain: its danger comes from mixed packs of all of them, and the Ravager more often. The weapons named in the table are planned too (see [`weapons.md`](weapons.md)).

## Where they live

- **Biome leanings** still to set with their strains: stalkers in the Overgrowth, darters around the cliffs of the Ash fields and Glass plains (see [`biomes.md`](biomes.md)).
- **Packs** for tier 5, added with its strains (tiers 3–4 have theirs).
- **Tiers** also scale health, damage and nests (built, see Tiers in [Missions](../GAME_DESIGN.md#6-missions)).

## Telegraphs and feedback

- **Telegraphs:** each new strain's wind-up uses the built ones (crouching or rearing, glands brightening; on the ground red dashed, like the brute's lane), with its sound (see [`sfx.md`](sfx.md)).
- **Projectiles** tell the weapons apart (shape, trail, impact).

## Limits

- **How many at once:** darters count as a share towards the cap, like the mites (their `cap_share`). Alien numbers and health still scale with the player count in co-op (M7).
- **Colors:** every strain glows in the swarmer's yellow-green (acid included), which no ore uses; stalkers have darker chitin (see [Alien look](../GAME_DESIGN.md#alien-look-and-behavior-direction-for-the-art-pass)).
