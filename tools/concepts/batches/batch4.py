"""Batch 4: iterate on the batch-3 feedback, 4 seed variants per subject.

Usage: python tools/concepts/batch.py batch4 [subject ...]
"""

from batches.batch2 import STYLES as B2

B2S = dict(B2)
HOUSE = (
    "photorealistic AAA sci-fi game render, detailed weathered PBR materials, dark moody low-key lighting with a "
    "strong cool rim light outlining every silhouette, muted desaturated world in greys and browns, the only "
    "saturated colors are glowing ore, glowing eyes and lights"
)
ISO = "isometric view from a high camera looking down at 45 degrees"

# Subject prompts carry their own style; the "styles" are seed variants only.
STYLES: list[tuple[str, str]] = [(f"v{i}", "") for i in range(1, 5)]

MINER = (
    "a large heavy automated ore mining machine, twice the height of a person, standing on a glowing cyan ore "
    "crystal node on rocky alien ground, drill boring into the ground, a vertical glass column on its side half "
    "filled with glowing ore, a lamp on top, a small display, a small astronaut standing next to it for scale, "
    f"{ISO}, readable silhouette"
)

SUBJECTS: dict[str, str] = {
    "miner_real": f"{B2S['realistic']}. Subject: {MINER}.",
    "miner_glow": f"{B2S['glowaccent']}. Subject: {MINER}.",
    "player": (
        f"{B2S['rimlit']}. Subject: a space miner player character in a bulky armored spacesuit with a helmet and "
        "visor, a glowing light band around the collar, a backpack with glowing ore canisters, holding a blaster, "
        "full body standing on the ground, three-quarter view from slightly above, single character."
    ),
    "swarmer": (
        f"{HOUSE}. Subject: a lean, fast alien hunter beast the size of a large dog, running low on four clawed "
        "digitigrade legs, a long narrow head with a wide jaw full of teeth, two long scythe-like bone blades rising "
        "from its back and curving forward over its head, dark crimson chitin carapace plates over sinewy flesh, "
        f"small glowing yellow eyes, a pack of them sprinting over dusty rock, {ISO}."
    ),
    "brute": (
        f"{HOUSE}. Subject: a huge four-legged armored alien brute beast, the size of an elephant calf, built like "
        "a cross between a rhino and a beetle, massive overlapping chitin armor plates with ridges and spikes like "
        "layered plate armor, thick heavy legs, a low horned head with glowing yellow eyes, dark crimson and black, "
        "charging over dusty rock, three-quarter view from above, single game enemy."
    ),
    "nest": (
        f"{HOUSE}. Subject: a low, wide organic alien nest mound grown into the rocky ground, dark crimson chitin "
        "and sinew, a glowing yellow pulsing opening on top, the ground around it covered by a wet slimy living "
        f"layer with veins spreading outward, small alien bugs crawling out, {ISO}."
    ),
    "ores": (
        f"{HOUSE}. Subject: alien ore crystal formations on rough rocky ground in many variations: clusters of "
        "different shapes and sizes, crystals growing sideways out of rock faces and cliff walls, single big "
        "crystals and small scattered shards, three ore types glowing cyan, green and violet, each type with its "
        f"own distinct crystal shape, {ISO}, game asset reference."
    ),
    "overgrowth": (
        f"{HOUSE}. Subject: an alien landscape with olive green ground and gentle hills, funnel-shaped alien trees, "
        "round puffball bushes, grass, rough jagged weathered boulders with sharp edges, deep cracks and lichen, "
        f"a small glowing green ore field, {ISO}, game level overview."
    ),
    "shipext": (
        f"{HOUSE}. Subject: a huge landed mining spaceship, 100 meters long, resting on heavy landing skids instead "
        "of wheels on a rocky alien plain, long boxy industrial hull, the cockpit at the front nose, two big "
        "thrusters at the rear, a wide loading ramp lowered at the rear end between the thrusters, lit windows "
        f"along the hull, tiny astronauts near the ramp for scale, {ISO}."
    ),
}

GROUPS = [(STYLES, SUBJECTS, 4000)]
