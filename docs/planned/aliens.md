# Aliens and the feel of combat (planned)

Decided 2026-10-17, built in M4 step 7 A–D (see [`PLAN.md`](../PLAN.md)): every strain below, the apex, the packs and biome leanings, armor, stagger and the telegraphs; see [Combat & aliens](../GAME_DESIGN.md#10-combat--aliens). This file keeps what's still open (the end of it); the roster stays for the whole picture.

## Strains and roles

- **11 strains and one apex,** two new ones per tier up to tier 5 and one on tier 6, so every planet brings something new to learn. The count is data: nests, packs and tests work for any number. Names are descriptive and translated, the way the crew would call them.

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
| 5 | **Stalker** | tall | see-through until it attacks (a shimmer, visible within 8 m and as a silhouette behind cliffs), its first strike from hiding hits hard; once seen, flesh hooks that slow; hit and run | arc caster, wide hits, sticking together | a hunched biped with scything talons and mouth tendrils, chameleon chitin |
| 6 | **Skimmer** | medium, flying | circles high out of reach of flat shots and spits straight acid bolts on the move | the target lock, range | a winged ray with a whip tail and a glowing throat sac |
| 3+ | **Ravager** (apex) | huge | at most one per region, roams or guards a rich site, announced by tremors; slams, charges, sheds swarmers | everything together; avoiding it is fine | the rare huge monster |

Besides the hunters, the nests' **guards and raiders are their own strains** (built in step 7 B, so a role shows in the body, not in a tint): the **warden** guards every nest on every tier (big, front-armored, a slam; more guard strains may come with later tiers), the **gnawer** is the first raider (tier 1, crushing jaws); later raider strains may come with later tiers.

Tier 6 brings one new strain, the skimmer; the rest of its danger comes from mixed packs of all of them, and the Ravager more often. The weapons named in the table are planned too (see [`weapons.md`](weapons.md)).

## Still open

- **The Ravager guarding a rich site:** it only roams so far; guarding the rich fields comes with them (step 13, [`risk-reward.md`](risk-reward.md)). Killing it rewards nothing yet: the quests' hunt goal will (step 15).
- **More guard and raider strains** with later tiers, if playtests ask for them (the hive takes any number).
- **Telegraph sounds:** each wind-up gets its sound with the sound effects (see [`sfx.md`](sfx.md)).
- **Projectiles** tell the weapons apart (shape, trail, impact), with the weapons (see [`weapons.md`](weapons.md)).
- **Co-op:** alien numbers and health scale with the player count (M7); a stalker's shimmer then shows per player (now: when any player is close).
- **Effects with the art pass:** the stalker's shimmer, the Ravager's dust and its swarmers climbing off its back are greybox (see M5 in [`PLAN.md`](../PLAN.md)).
