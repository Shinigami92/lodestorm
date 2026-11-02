"""Batch 11: the four biomes still without their own look (Frost fields, Salt pans, Ash fields, Glass plains),
for the biome art pass: a game-view overview and a sheet of their scatter and features each, plus the Overgrowth's
giant growth walls. Four seeds per subject.

Usage: python tools/concepts/batch.py batch11 [subject ...]
"""

HOUSE = (
    "photorealistic AAA sci-fi game render, detailed weathered PBR materials, dark moody low-key lighting with a "
    "strong cool rim light outlining every silhouette, muted desaturated world, the only saturated colors are "
    "glowing ore, glowing eyes and lights"
)

ISO = "isometric view from a high camera looking down at 45 degrees"
SHEET = "game asset reference sheet, the props spread out side by side on plain dark ground, no people"

STYLES: list[tuple[str, str]] = [(f"s{i}", "") for i in range(1, 5)]

SUBJECTS: dict[str, str] = {
    "frost": (
        f"{HOUSE}. Subject: a frozen alien plain of wide flat ice sheets dusted with wind-packed snow, deep blue-black "
        "crevasses between them crossed by narrow natural snow bridges, a frozen lake of dark glossy ice with pale "
        "cracks, frost-coated jagged boulders, pale blue ice chunks, a small glowing cyan ore field, cold blue-grey "
        f"tones, {ISO}, game level overview."
    ),
    "frost_props": (
        f"{HOUSE}. Subject: alien frost field props: jagged dark boulders with snow caps and frost in their cracks, "
        "translucent pale blue ice chunks and ice blocks, a tilted ice pinnacle, a low wind-carved snow drift, frozen "
        f"dead shrub with ice crystals, scattered small ice shards and frosted pebbles, {SHEET}, {ISO}."
    ),
    "salt": (
        f"{HOUSE}. Subject: a vast flat alien salt pan, white-grey salt crust broken into polygonal plates with raised "
        "ridged edges, round sinkholes with dark still brine at their bottom, a long raised salt causeway between "
        "low pale rock walls, salt-encrusted boulders, small cubic salt crystal clusters, bleached bones, a small "
        f"glowing violet ore field, {ISO}, game level overview."
    ),
    "salt_props": (
        f"{HOUSE}. Subject: alien salt pan props: salt-crusted grey boulders, a tall eroded salt pillar, clusters of "
        "cubic halite crystals, a dried brittle shrub coated in salt, a bleached alien rib cage and skull, flat "
        f"broken salt crust plates, scattered pebbles, {SHEET}, {ISO}."
    ),
    "ash": (
        f"{HOUSE}. Subject: a volcanic alien ash field, dark grey ash ground with black basalt, sharp jagged ridges of "
        "black rock, glowing orange lava channels with a dark cooling crust floating on them, a narrow crossing of "
        "cooled black lava crust over the lava, smoking vents in scorched ground, charred dead tree stumps, a small "
        f"glowing green ore field, {ISO}, game level overview."
    ),
    "ash_props": (
        f"{HOUSE}. Subject: alien volcanic ash field props: black basalt boulders, a cluster of hexagonal basalt "
        "columns, porous dark red scoria rocks, a charred dead tree stump, a small cinder cone vent with glowing "
        f"cracks, ash-covered rubble, a close-up of a glowing lava surface with dark crust plates, {SHEET}, {ISO}."
    ),
    "glass": (
        f"{HOUSE}. Subject: an alien plain of ground vitrified by a star's flare, pale grey-teal glassy rock in flat "
        "terraces with low steps, fences of sharp translucent glass shards along the terrace edges, a garden of tall "
        "clustered glass spires, fields of glittering glass splinters, half-melted fused boulders with glossy "
        f"surfaces, a small glowing yellow ore field, {ISO}, game level overview."
    ),
    "glass_props": (
        f"{HOUSE}. Subject: alien glass plain props: a cluster of tall translucent pale teal glass spires, single "
        "sharp glass shard spikes, a melted half-vitrified boulder with a glossy dripping glass skin, a glass "
        f"fulgurite tube, a patch of small sharp glass splinters, smoky glass chunks, {SHEET}, {ISO}."
    ),
    "growth": (
        f"{HOUSE}. Subject: an alien overgrowth wall: a dense band of giant fungal stalks and thick tangled roots, "
        "tall fleshy tubes and broad mushroom caps up to eight meters high, olive and dark brown with pale fungal "
        "highlights, low mossy rock behind them, a narrow trail of dark soil in front, faint bioluminescent spots, "
        f"{ISO}, game level overview."
    ),
}

SIZE = 1024
GROUPS = [(STYLES, SUBJECTS, 11000)]
