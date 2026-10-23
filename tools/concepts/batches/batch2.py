"""Batch 2: variations of the top batch-1 styles (realistic, grimdark, biopunk), plus a game scene.

Usage: python tools/concepts/batch.py batch2 [subject ...]
"""

STYLES: list[tuple[str, str]] = [
    (
        "realistic",
        "photorealistic AAA sci-fi game render, detailed PBR materials, physically based lighting, cinematic, unreal engine quality",
    ),
    (
        "grimdark",
        "dark gritty grimdark sci-fi render, heavy weathering, rust, grime and scratches, moody low-key lighting, desaturated palette",
    ),
    (
        "glowaccent",
        "photorealistic sci-fi render, muted desaturated world in greys and browns, the only saturated colors are glowing ore, glowing eyes and lights, high contrast, very readable",
    ),
    (
        "stylizedreal",
        "stylized realism game art: realistic PBR materials and weathering, but slightly exaggerated chunky proportions and bold simple shapes that read from far away",
    ),
    (
        "usedfuture",
        "used-future sci-fi like practical props from late 1970s and 1980s science fiction films, worn and grimy, utilitarian, kitbashed mechanical details",
    ),
    (
        "rimlit",
        "dark cinematic sci-fi render, low-key lighting with a strong cool rim light outlining every silhouette, volumetric dust in the air",
    ),
    (
        "realmecha",
        "realistic hard-surface sci-fi design, white and orange armor panels with scuffs, decals and panel lines, weathered industrial design, studio lighting",
    ),
    (
        "desertsun",
        "realistic sci-fi render under a harsh bright alien sun, sun-bleached paint, dust everywhere, crisp strong shadows, warm sandy palette",
    ),
    (
        "realbiopunk",
        "realistic biopunk sci-fi, technology fused with organic chitin and sinew, wet glossy surfaces, bioluminescent veins, dark moody light",
    ),
    (
        "scalemodel",
        "photo of a highly detailed practical scale model made for film effects work, real painted materials, studio lighting, standing directly on sculpted terrain",
    ),
    (
        "grimglow",
        "grimdark sci-fi, heavy rust and grime, dark palette, with glowing ore and emissive lamps as strong color accents",
    ),
    (
        "military",
        "gritty military sci-fi, olive drab and gunmetal, stenciled markings and hazard stripes, rugged realistic materials, overcast daylight",
    ),
]

SUBJECTS: dict[str, str] = {
    "miner": (
        "an automated ore mining machine standing on a glowing cyan ore crystal node on rocky alien ground, "
        "drill boring into the ground, a vertical glass column on its side half filled with glowing ore, "
        "a lamp on top, a small display, isometric view from above, single game asset, readable silhouette"
    ),
    "alien": (
        "a hostile alien swarm creature with a low, wide body close to the ground, like a cross between a tick, "
        "a scorpion and a beetle: armored chitin plates over sinewy flesh, eight short spiky legs, big claws and "
        "mandibles, a short blunt head with a cluster of glowing yellow eyes, no tail, dark crimson and black, "
        "scuttling forward on dusty alien ground, three-quarter view from above, single game enemy, clear silhouette"
    ),
    "player": (
        "a space miner player character in a bulky armored spacesuit with a helmet and visor, "
        "a light band around the collar, a backpack with glowing ore canisters, holding a blaster, "
        "full body standing on the ground, three-quarter view from slightly above, single character, plain background"
    ),
    "weapon": (
        "a product shot of only two sci-fi weapons lying on a workbench, nothing else in the picture: "
        "a chunky blaster rifle with a glowing ammo counter on its side and a heavy two-handed mining hammer, "
        "three-quarter view from above, no people"
    ),
    "scene": (
        "an isometric game screenshot from a high camera looking down at 45 degrees: a small player character in a "
        "spacesuit connected by a glowing hose to an ore mining machine on a glowing cyan ore node, a swarm of small "
        "dark crimson alien bugs approaching across a rocky alien plateau, boulders and cliffs, a dark dust storm "
        "building on the horizon, a landed spaceship with an open ramp nearby, every element small and readable"
    ),
}

GROUPS = [(STYLES, SUBJECTS, 2000)]
