"""Batch 7: top-down plan maps of whole mission locations (the layout graph seen from straight above).

Two looks: the world rendered straight down (2 seeds) and a holographic tactical map (2 seeds).

Usage: python tools/concepts/batch.py batch7 [subject ...]
"""

PLAN = (
    "orthographic top-down view looking straight down from directly above, like a satellite image or a game "
    "level plan, no horizon, no perspective, the whole area fits in the frame, the walkable floor is clearly "
    "lower and lighter than the dark high rock around it"
)
RENDER = (
    "photorealistic AAA sci-fi game render, detailed weathered PBR materials, jagged cracked rocks, dark moody "
    "low-key lighting, muted desaturated greys and browns, the only saturated colors are small glowing ore "
    f"crystals and lights. {PLAN}"
)
HOLO = (
    "a glowing cyan holographic tactical terrain map projected over a dark table, thin contour lines, the "
    "walkable valleys and passes outlined brightly, the high rock dim, small amber icons for points of "
    f"interest, red icons for alien nests, a small ship icon at the landing site, clean readable sci-fi UI. {PLAN}"
)

STYLES: list[tuple[str, str]] = [
    ("render1", RENDER),
    ("render2", RENDER),
    ("holo1", HOLO),
    ("holo2", HOLO),
]

LAYOUTS: dict[str, str] = {
    "small_dust": (
        "a small mission area on a dusty desert planet: a landing site with a mining spaceship, five sandy "
        "basins of different sizes connected by narrow winding canyon passes cut between high flat-topped "
        "sandstone mesas, one loop and two short dead ends, glowing ore at the dead ends"
    ),
    "large_dust": (
        "a large mission area on a dusty desert planet: a landing site with a mining spaceship near one edge, "
        "about fourteen sandy basins connected by a branching network of narrow canyon passes between high "
        "flat-topped sandstone mesas, several loops, long dead ends far from the ship, a round meteor crater, "
        "glowing ore fields spread through the basins"
    ),
    "growth": (
        "a mission area on an overgrown alien planet: a landing clearing with a mining spaceship, mossy valleys "
        "connected by narrow gorges between steep dark forested rock ridges, a ring of valleys around a central "
        "ridge with side branches, a sunken hollow with alien nests at the far end, glowing green ore fields"
    ),
    "wide": (
        "a wide open mission area on a dusty desert plain: a landing site with a mining spaceship, very large "
        "flat basins joined by broad passes between low rock ridges, isolated mesas standing in the open, few "
        "dead ends, ore fields far apart"
    ),
    "setpieces": (
        "a mission area on a dusty desert planet with landmarks: a landing site with a mining spaceship, basins "
        "joined by canyon passes between mesas, a crashed spaceship wreck in one basin, an abandoned outpost of "
        "prefab modules in another, a round meteor crater at the far end, a lone high plateau with a natural "
        "ramp"
    ),
    "moon": (
        "a mission area on a barren grey airless moon: a landing site with a mining spaceship, flat crater floors "
        "connected by gaps broken through crater rims and long cracked rilles, overlapping craters of many sizes, "
        "glowing blue ore in a small deep crater"
    ),
}

SUBJECTS: dict[str, str] = {name: f"Level layout of a sci-fi mining game. {text}" for name, text in LAYOUTS.items()}

GROUPS = [(STYLES, SUBJECTS, 7000)]
