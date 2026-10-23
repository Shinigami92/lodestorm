"""Batch 6: mission locations built from map parts (layout graph, areas, corridors, points of interest).

Two framings: the in-game iso camera (2 seeds) and a high aerial overview (2 seeds).

Usage: python tools/concepts/batch.py batch6 [subject ...]
"""

HOUSE = (
    "photorealistic AAA sci-fi game render, detailed weathered PBR materials, jagged cracked rocks, dark moody "
    "low-key lighting with a strong cool rim light outlining every silhouette, muted desaturated world in greys "
    "and browns, the only saturated colors are glowing ore crystals, glowing alien eyes and lights"
)
ISO = (
    "isometric game view from a high camera looking down at 35 degrees, rotated 45 degrees, like a top-down "
    "action game, a single tiny space miner in a dark armored suit with a glowing collar band for scale"
)
AERIAL = (
    "aerial overview from very high above, almost straight down, like a game level map, the whole area visible, "
    "tiny figures"
)

STYLES: list[tuple[str, str]] = [
    ("iso1", f"{HOUSE}. {ISO}"),
    ("iso2", f"{HOUSE}. {ISO}"),
    ("aerial1", f"{HOUSE}. {AERIAL}"),
    ("aerial2", f"{HOUSE}. {AERIAL}"),
]

DUST = (
    "on a dusty alien desert planet: sandy ground with a cracked crust, layered sandstone cliffs and high "
    "plateaus, boulders, rubble, thorny spire plants and dry shrubs"
)
GROWTH = (
    "on an overgrown alien planet: dark soil under olive moss, rounded hills and mossy rock ridges, fleshy tube "
    "plants, mushrooms, puffball fungi and fronds"
)

PARTS: dict[str, str] = {
    "layout_dust": (
        f"a whole mission area {DUST}: a landed mining spaceship on a flat landing site, from there several "
        "winding canyon passes lead between high impassable rock mesas to open sandy basins, the passes branch "
        "and loop, small glowing cyan ore fields in the basins, a glowing violet ore vein deep in a dead end "
        "canyon, dark crimson alien nests in a hollow, the area enclosed by mountains"
    ),
    "layout_growth": (
        f"a whole mission area {GROWTH}: a landed mining spaceship in a clearing, mossy valleys connected by "
        "narrow gorges between steep forested ridges that cannot be climbed, the valleys form a loop with side "
        "branches, small glowing green ore fields, dark crimson alien nests in a far hollow"
    ),
    "layout_wide": (
        f"a wide open mission area {DUST}: a landed mining spaceship on a broad plain, large flat basins joined "
        "by wide passes between low rock ridges and isolated mesas, long sight lines, small glowing ore fields "
        "scattered far apart"
    ),
    "landing": (
        f"the landing site {DUST}: a large boxy mining spaceship on landing skids on a flat cleared pad of "
        "packed sand, its loading ramp lowered at the rear, two exits lead away between low cliffs into "
        "passes, a small glowing cyan ore field close to the ramp"
    ),
    "basin": (
        f"an open basin {DUST}: a wide flat sandy bowl ringed by tall layered cliffs, three narrow passes open "
        "into it from different sides, scattered boulders as cover, two small glowing cyan ore fields, a few "
        "small alien creatures at the far edge"
    ),
    "canyon": (
        f"a narrow winding canyon pass {DUST}, about ten meters wide between steep layered sandstone walls, "
        "rubble and scree at the foot of the walls, it bends out of sight, the miner walking through it"
    ),
    "crossroads": (
        f"a crossroads {GROWTH}: a small mossy clearing where four narrow gorges meet between steep rock ridges, "
        "a big lone boulder in the middle, a faint path worn into the moss"
    ),
    "orepocket": (
        f"a dead end ore pocket {DUST}: a short canyon ending in a small enclosed hollow, a rich cluster of large "
        "glowing violet ore crystals breaking out of the rock wall and the ground, the violet glow lighting the "
        "cliffs around it"
    ),
    "nesthollow": (
        f"an alien nest hollow {GROWTH}: a sunken bowl in the ground, two dark crimson organic nest mounds with "
        "glowing yellow mouths, the ground around them covered by a wet slimy living layer with veins, small "
        "alien swarmers crawling out, a single narrow way in"
    ),
    "plateau": (
        f"a plateau with a ramp {DUST}: a high flat mesa rising above the lowland with sheer cliffs on all sides "
        "except one long natural ramp of rock leading up, a glowing cyan ore field on top, a lookout over the area"
    ),
    "crater": (
        f"a fresh meteor impact crater {DUST}: a round bowl with a raised rim of broken rock, scorched ground, a "
        "smoking glowing orange-hot meteorite in the middle with bright ore crystals growing out of it"
    ),
    "wreck": (
        f"a crashed spaceship wreck {GROWTH}: a broken hull half buried in the ground, torn metal plates, moss "
        "growing over it, a supply crate with a blinking amber light next to it, cables hanging out"
    ),
    "outpost": (
        f"an abandoned mining outpost {DUST}: a few prefab modules and a small landing pad, a broken comms "
        "antenna, a fence with gaps, sand drifted against the walls, a dim flickering lamp, crates and an old "
        "rusty mining machine"
    ),
    "expedition": (
        f"the last camp of a lost expedition {GROWTH}: a torn tent, an old beacon with a faint blinking amber "
        "light, scattered equipment and a helmet on the ground, overgrown, under an overhanging rock ridge"
    ),
}

SUBJECTS: dict[str, str] = {name: f"Mission location of a sci-fi mining game. {text}" for name, text in PARTS.items()}

GROUPS = [(STYLES, SUBJECTS, 6000)]
