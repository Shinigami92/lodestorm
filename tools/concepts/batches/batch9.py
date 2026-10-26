"""Batch 9: the game's logo for the boot splash and the boot screen: emblems without text (the name is set
in the game's font beside them) and full logos with the name, 4 seed variants each.

Usage: python tools/concepts/batch.py batch9 [subject ...]
"""

LOGO = (
    "game logo emblem, centered on a pure black background, flat front view, isolated, no text, no letters, "
    "clean readable silhouette that works small, dark realistic sci-fi, brushed gunmetal and dark steel, "
    "a strong cool rim light, the only saturated colors are a glowing cyan and a little amber, subtle glow"
)
WORDMARK = (
    'game title logo reading "LODESTORM" in bold, wide, squared industrial sci-fi capital letters, centered on '
    "a pure black background, flat front view, isolated, the letters brushed gunmetal with a thin glowing cyan "
    "edge, dark realistic sci-fi, a strong cool rim light, subtle glow"
)

EMBLEMS: dict[str, str] = {
    "crystal_vortex": (
        f"{LOGO}. A jagged faceted ore crystal glowing cyan from within at the center, wrapped by a tight "
        "swirling ring of storm clouds and dust spiralling around it, a few thin amber lightning arcs"
    ),
    "storm_eye": (
        f"{LOGO}. A circular emblem: the eye of a dust storm seen from above, spiral bands of dark cloud "
        "turning inward, at its calm center a small glowing cyan ore shard, a thin steel ring around it all"
    ),
    "drill_bit": (
        f"{LOGO}. A heavy mining drill bit pointing down, its stepped cone cutting into a glowing cyan ore "
        "vein, swirling dust and wind lines curling around the bit like a storm, inside a hexagonal steel frame"
    ),
    "monogram": (
        f"{LOGO}. A bold geometric letter L monogram cut from thick dark steel plate, a glowing cyan ore "
        "crystal set into its corner, a swirl of storm wind wrapping around it, inside a rounded square badge"
    ),
    "lodestone": (
        f"{LOGO}. A raw angular lodestone rock split open, glowing cyan veins inside, magnetic field lines "
        "curving around it in arcs that turn into a swirling storm, a few amber sparks"
    ),
}
WORDMARKS: dict[str, str] = {
    "wordmark_plain": WORDMARK,
    "wordmark_crystal": (
        f"{WORDMARK}, the O replaced by a glowing cyan faceted ore crystal inside a swirl of storm wind"
    ),
}

GROUPS = [
    ([(f"v{i}", "") for i in range(1, 5)], EMBLEMS, 9000),
    ([(f"v{i}", "") for i in range(1, 5)], WORDMARKS, 9100),
]
