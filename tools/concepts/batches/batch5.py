"""Batch 5: ship interior rooms in the house style, two framings (cutaway iso, eye level) x 2 seeds.

Usage: python tools/concepts/batch.py batch5 [subject ...]
"""

HOUSE = (
    "photorealistic AAA sci-fi game render, detailed weathered PBR materials with scratches, grime and worn paint, "
    "dark moody low-key lighting with a strong cool rim light outlining every silhouette, muted desaturated "
    "greys and browns, the only saturated colors are glowing cyan holograms and screens, amber floor markings "
    "and status lights"
)
SHIP = (
    "inside a huge industrial deep-space mining ship: heavy painted steel bulkheads with ribs and pipes, "
    "grated and plated metal floors, amber painted floor markings, the room's name painted on the floor by "
    "the door, small windows in the outer hull wall"
)
ISO = (
    "cutaway isometric view from a high camera looking down at 45 degrees, the ceiling and the two walls facing "
    "the camera removed so the whole room is visible like a diorama, a single space miner in a dark armored "
    "suit with a glowing collar band standing in it for scale"
)
EYE = "cinematic wide shot from eye level standing inside the room, deep perspective, volumetric haze"

STYLES: list[tuple[str, str]] = [
    ("iso1", f"{HOUSE}. {ISO}"),
    ("iso2", f"{HOUSE}. {ISO}"),
    ("eye1", f"{HOUSE}. {EYE}"),
    ("eye2", f"{HOUSE}. {EYE}"),
]

ROOMS: dict[str, str] = {
    "cockpit": (
        "the cockpit at the nose of the ship, two pilot seats before a wide curved console with switches and "
        "small glowing screens, a big heavy launch lever in the middle, a large slanted window looking out over "
        "the ship's nose onto a dark alien plain under a stormy sky"
    ),
    "bridge": (
        "the bridge, a large round holographic table in the middle projecting a glowing cyan hologram of a "
        "planet with orbit lines and moons, an amber light ring on the floor around the table, a comms station "
        "with screens against the wall, railings, dim overhead lamps"
    ),
    "cabin": (
        "a small cramped player crew cabin, a narrow bunk bed with a grey blanket built into the wall, a tall "
        "personal metal locker, a small wall terminal with a glowing screen, a porthole window, personal "
        "belongings, a warm reading lamp"
    ),
    "crewcabin": (
        "a lived-in crew cabin of a veteran crew member, a bunk bed, a small desk with tools and a coffee mug, "
        "photos and notes taped to the wall, a hanging work jacket, a porthole window, warm dim lamp light"
    ),
    "mess": (
        "the mess hall, long metal tables with benches bolted to the floor, a galley counter with a serving hatch "
        "and steaming pots, food trays, a coffee machine, a large window, hanging lamps over the tables"
    ),
    "medbay": (
        "the medical bay, a respawn cloning pod, a vertical glass tube filled with glowing liquid, two medical "
        "beds with scanner arms above them, cabinets with supplies, sterile pale light mixed with cyan readouts"
    ),
    "engine": (
        "the engine room, a massive reactor core with a glowing heart behind heavy shielding, thick pipes and "
        "cables running along the walls and ceiling, catwalks, valves and gauges, a maintenance console, steam "
        "and heat haze"
    ),
    "range": (
        "the shooting range, a long narrow hall, a firing line with a counter at the near end, a faintly glowing "
        "force field across the doorway, humanoid metal practice targets with hit marks at the far end, harsh "
        "strip lights, sound dampening panels on the walls"
    ),
    "armory": (
        "the armory, four tall numbered personal weapon lockers along the back wall with open doors, each with a "
        "colored light strip, rifles, a shotgun and a heavy hammer hanging inside, two lit weapon cradles below "
        "an amber 'LOADOUT' sign, a bench in the middle"
    ),
    "weapons": (
        "the weapon upgrade workshop, a heavy workbench with a blaster rifle clamped in a cradle under a robotic "
        "arm, its parts laid out, tool walls, a small glowing holographic card floating next to the rifle, "
        "crates of spare parts"
    ),
    "armor": (
        "the armor upgrade room, a big fitting frame holding an empty bulky armored spacesuit upright with "
        "mechanical arms around it, spare helmets and armor plates on racks, a small glowing holographic card "
        "beside the suit"
    ),
    "skills": (
        "the skills room, a circular holo emitter on the floor projecting a big glowing cyan constellation "
        "graph of linked points into the air, like a star map, dark room lit mostly by the hologram, a few "
        "benches around it"
    ),
    "miners": (
        "the miner workshop, a big automated ore mining machine on four mechanical legs with a glowing glass "
        "column standing on a maintenance pad, gantry crane above it, a spare drill head on the floor, tool "
        "racks, oil stains"
    ),
    "cargo": (
        "the double-height cargo bay at the tail, a wide loading ramp lowered at the rear opening onto a dusty "
        "alien plain with a reddish storm haze outside, stacked cargo crates and ore containers, a lift platform "
        "in a shaft with safety gates at the side, a gantry walkway along the upper deck, big warning lights"
    ),
    "corridor": (
        "the central corridor of the ship's deck, long and straight with doors to rooms on both sides, amber "
        "floor arrows pointing to the rooms ahead, at its end a lift lobby with a lift platform in a caged "
        "shaft, pipes and cable trays overhead, flickering lamps"
    ),
}

SUBJECTS: dict[str, str] = {room: f"{SHIP}. This room: {text}" for room, text in ROOMS.items()}

GROUPS = [(STYLES, SUBJECTS, 5000)]
