"""Batch 3: one house style (realistic + rim light + glow accents) across new subjects.

Usage: python tools/concepts/batch.py batch3 [subject ...]
"""

HOUSE = (
    "photorealistic AAA sci-fi game render, detailed weathered PBR materials, dark moody low-key lighting with a "
    "strong cool rim light outlining every silhouette, muted desaturated world in greys and browns, the only "
    "saturated colors are glowing ore, glowing eyes and lights"
)

STYLES: list[tuple[str, str]] = [("house", HOUSE)]

ISO = "isometric view from a high camera looking down at 45 degrees"

SUBJECTS: dict[str, str] = {
    "miner": (
        "an automated ore mining machine standing on a glowing cyan ore crystal node on rocky alien ground, drill "
        "boring into the ground, a vertical glass column on its side half filled with glowing ore, a lamp on top, "
        f"a small display, {ISO}, single game asset, readable silhouette"
    ),
    "player": (
        "a space miner player character in a bulky armored spacesuit with a helmet and visor, a glowing light band "
        "around the collar, a backpack with glowing ore canisters, holding a blaster, full body standing on rocky "
        "ground, three-quarter view from slightly above, single character"
    ),
    "swarmer": (
        "a small fast alien swarmer, dog-sized, low beetle-like body of armored chitin plates over sinewy flesh, "
        "six short spiky legs, snapping mandibles, a cluster of glowing yellow eyes, dark crimson and black, a pack "
        f"of them scuttling over dusty rock, {ISO}"
    ),
    "nest": (
        "an organic alien nest grown into the rocky ground, a dark crimson mound of chitin and sinew with a glowing "
        "yellow pulsing mouth, the ground around it covered by a wet slimy living layer with veins, small alien "
        f"bugs crawling out, {ISO}"
    ),
    "ores": (
        "three alien ore crystal nodes side by side on dusty rocky ground: one glowing cyan, one glowing green, "
        f"one glowing violet, each a cluster of sharp crystals breaking out of the rock, {ISO}, game assets"
    ),
    "dustflats": (
        "a sandy alien desert landscape with high plateaus and steep cliffs, scattered boulders, tall spire-shaped "
        f"alien plants and dry shrubs, a small glowing cyan ore field, {ISO}, game level overview"
    ),
    "overgrowth": (
        "an alien landscape with olive green ground and gentle hills, funnel-shaped alien trees, round puffball "
        f"bushes, grass and mossy boulders, a small glowing green ore field, {ISO}, game level overview"
    ),
    "shipext": (
        "a large landed mining spaceship on landing gear on a rocky alien plain, long boxy industrial hull with a "
        f"cockpit at the nose and two thrusters at the tail, an open loading ramp at the back, lit windows, {ISO}"
    ),
    "shipint": (
        "the interior of a mining spaceship seen from above with the roof cut away: a two-deck layout with a bridge, "
        "a briefing room with a glowing holographic map table, corridors, a lift, crew cabins and a cargo bay, "
        f"industrial metal floors and amber guide markings, {ISO}"
    ),
    "brute": (
        "a large armored alien brute, the size of a bull, rhino-beetle-like body with thick overlapping chitin "
        "plates, heavy legs, a massive horned head with glowing yellow eyes, dark crimson and black, charging over "
        "dusty rock, three-quarter view from above, single game enemy"
    ),
    "spitter": (
        "an alien spitter, beetle-like body on six legs with a swollen glowing yellow-orange acid sac on its back, "
        "its head raised spitting a stream of glowing acid, chitin and sinew, dark crimson and black, on dusty rock, "
        "three-quarter view from above, single game enemy"
    ),
    "weapon": (
        "a product shot of only two sci-fi weapons lying on a workbench, nothing else in the picture: a chunky "
        "blaster rifle with a glowing ammo counter on its side and a heavy two-handed sci-fi mining hammer with a "
        "glowing power core in its head, three-quarter view from above, no people"
    ),
}

SIZE = 768
GROUPS = [(STYLES, SUBJECTS, 3000)]
