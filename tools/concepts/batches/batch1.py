"""Batch 1: 20 styles x the first subjects, to find the art direction.

Usage: python tools/concepts/batch.py batch1 [subject ...]
"""

STYLES: list[tuple[str, str]] = [
    (
        "painted",
        "stylized 3D game asset with hand-painted textures, soft painterly shading, warm studio light, worn painted edges",
    ),
    (
        "lowpoly",
        "flat-shaded low-poly 3D render, faceted geometry, no textures, solid colors, dramatic dusk light with long shadows",
    ),
    (
        "industrial",
        "semi-realistic stylized sci-fi game render, chunky heavy proportions, scuffed paint with hazard stripes, rim light, dust in the air",
    ),
    (
        "voxel",
        "voxel art 3D render, built from small cubes, crisp blocky shapes, soft ambient occlusion, isometric game look",
    ),
    (
        "clay",
        "claymation style 3D render, plasticine material with fingerprints and soft bumps, handmade stop-motion look, soft lighting",
    ),
    (
        "realistic",
        "photorealistic AAA sci-fi game render, detailed PBR materials, physically based lighting, cinematic, unreal engine quality",
    ),
    (
        "miniature",
        "painted tabletop wargaming miniature on a small round base, tilt-shift macro photo, shallow depth of field, hand-painted acrylic details",
    ),
    (
        "ps1",
        "retro 1990s PlayStation 1 game style, very low polygon count, low resolution pixelated textures, vertex lighting, slight dithering",
    ),
    (
        "vinyl",
        "designer vinyl toy look, smooth rounded forms, soft pastel colors, glossy plastic, minimal details, product photo on a plain backdrop",
    ),
    (
        "grimdark",
        "dark gritty grimdark sci-fi render, heavy weathering, rust, grime and scratches, moody low-key lighting, desaturated palette",
    ),
    (
        "neon",
        "neon synthwave sci-fi render, dark scene with glowing emissive magenta and cyan accents, bloom, reflective surfaces",
    ),
    (
        "watercolor",
        "soft painterly 3D render with watercolor-like textures, gentle pastel light, dreamy cozy atmosphere",
    ),
    (
        "mecha",
        "crisp hard-surface mecha design render, clean panel lines, precise mechanical detail, white and orange armor plating, studio lighting",
    ),
    (
        "papercraft",
        "papercraft style, made from folded and cut colored paper, visible paper grain and creases, soft shadows, handcrafted diorama",
    ),
    (
        "heroshooter",
        "stylized PBR hero-shooter game style, exaggerated clean shapes, rich hand-crafted materials, vibrant colors, polished AAA look",
    ),
    (
        "biopunk",
        "biopunk aesthetic, organic and technological forms grown together, fleshy tubes, chitin and glowing veins, wet surfaces, eerie light",
    ),
    (
        "dieselpunk",
        "dieselpunk style, riveted steel and brass, pipes, gauges and exhaust stacks, oil stains, warm amber lighting",
    ),
    (
        "atompunk",
        "1950s atompunk retro-futurism, chrome fins, rounded streamlined shapes, candy-colored enamel paint, optimistic space age design",
    ),
    (
        "geometric",
        "minimalist geometric low-poly with smooth color gradients, elegant simple shapes, soft pastel palette, calm ambient light",
    ),
    (
        "mobile",
        "polished mobile strategy game style, bright saturated colors, chunky readable shapes, glossy highlights, soft shadows",
    ),
]

SUBJECTS: dict[str, str] = {
    "miner": (
        "an automated ore mining machine standing on a glowing cyan ore crystal node on rocky alien ground, "
        "drill boring into the ground, a vertical glass column on its side half filled with glowing ore, "
        "a lamp on top, a small display, isometric view from above, single game asset, readable silhouette"
    ),
    "alien": (
        "a hostile alien swarm creature, insect- and reptile-like beast with chitin plates over sinewy flesh, "
        "six legs, claws, mandibles and teeth, glowing eyes, crimson and dark colors, low crouching attack pose "
        "on dusty alien ground, three-quarter view from above, single game enemy, clear readable silhouette"
    ),
    "player": (
        "a space miner player character in a bulky armored spacesuit with a helmet and visor, "
        "a light band around the collar, a backpack with glowing ore canisters, holding a blaster, "
        "full body standing pose, three-quarter view from slightly above, single character, plain background"
    ),
    "weapon": (
        "a sci-fi weapon set for a space miner: a chunky blaster rifle with a glowing ammo indicator "
        "and a heavy melee mining tool, displayed side by side as game props, three-quarter view, plain background"
    ),
}

GROUPS = [(STYLES, SUBJECTS, 1000)]
