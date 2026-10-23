"""Batch 8: Waypost Ostra (the orbital station): its rooms in two framings (cutaway iso, eye level) x 2 seeds,
plus the exterior, the deck overview and the station's people (4 seed variants each).

Usage: python tools/concepts/batch.py batch8 [subject ...]
"""

from batches.batch5 import HOUSE

STATION = (
    "inside Waypost Ostra, a crowded lived-in orbital colony station of industrial weathered human tech: heavy "
    "painted steel bulkheads with ribs and rounded frames, patched hull plates, cables and pipes along the walls, "
    "grated and plated metal floors with amber painted markings, stacked cargo containers, warm work lights and "
    "hanging lamps against the dark, colonists in worn work suits, large windows showing a dusty planet below and "
    "black space"
)
ISO = (
    "cutaway isometric view from a high camera looking down at 45 degrees, the ceiling and the two walls facing "
    "the camera removed so the whole room is visible like a diorama, the room large and spacious, a single space "
    "miner in a dark armored suit with a glowing collar band standing in it for scale"
)
EYE = "cinematic wide shot from eye level standing inside the room, deep perspective, volumetric haze"
PERSON = (
    "full body character concept, standing pose, three-quarter view from slightly above, plain dark background, "
    "realistic proportions, a worn practical outfit of a frontier space colonist"
)

ROOMS: dict[str, str] = {
    "hangar": (
        "the docking hangar, a huge industrial bay with a big boxy mining spaceship on landing skids held by heavy "
        "docking clamps, its rear loading ramp lowered onto the hangar deck, a giant closed pressure door to "
        "space behind it, gantry cranes, fuel lines, crates, amber warning lights, a wide passage leading on into "
        "the station"
    ),
    "concourse": (
        "the concourse, a big central hall two decks high, colonists walking and standing, small market stalls "
        "made from cargo containers with awnings and hand-painted signs, hanging cables and lamps, benches, a "
        "public notice board, wide openings to other rooms on all sides, a big window band high on one wall"
    ),
    "depot": (
        "the supply depot, a warehouse with tall shelving of crates and ore containers, a forklift, and at the front "
        "a heavy industrial ore exchange counter with three big funnel hoppers on top, ore chutes and scales, a "
        "small glowing holographic card floating above the counter, a depot master's desk with a terminal behind it"
    ),
    "council": (
        "the colony council office, a meeting room with a long worn table and mismatched chairs, wall screens with "
        "maps of the planets and supply charts, stacked paper and data slates, a colony flag, a big window onto the "
        "planet, calm warm light, more orderly than the rest of the station"
    ),
    "bar": (
        "a bar for prospector crews, a long scratched metal bar counter with stools, bottles on shelves behind it lit "
        "by warm amber light, booths with tired miners in worn suits, a dartboard and old mining posters, a "
        "porthole window, smoke haze, cozy and rough"
    ),
    "gallery": (
        "the observation gallery, a long curved room with a huge window wall looking down onto a dusty orange "
        "planet with storm bands and two small moons, railings along the glass, benches facing the view, dim "
        "interior lights so the planet glow lights the room"
    ),
}

STYLES: list[tuple[str, str]] = [
    ("iso1", f"{HOUSE}. {ISO}"),
    ("iso2", f"{HOUSE}. {ISO}"),
    ("eye1", f"{HOUSE}. {EYE}"),
    ("eye2", f"{HOUSE}. {EYE}"),
]

# These carry their own framing: seed-only variants
OWN: dict[str, str] = {
    "exterior": (
        f"{HOUSE}. Waypost Ostra, an orbital colony station in space above a dusty orange planet: a ring-less "
        "cluster of heavy industrial modules, a big central hall module, a hangar bay with an open glowing "
        "mouth, solar wings, antennas and cargo containers bolted on, patched hull plates, small lit windows, "
        "a boxy mining spaceship approaching the hangar, wide cinematic shot, the planet's limb glowing below"
    ),
    "deck": (
        f"{HOUSE}. Cutaway isometric diorama of the whole single deck of a compact orbital colony station seen "
        "from high above, roof removed: a big central hall in the middle with market stalls and colonists, "
        "around it a docking hangar with a boxy spaceship, a supply depot warehouse, a council office, a bar "
        "and a long observation gallery with a window wall, corridors and doors between them, amber floor "
        "signs, the station's outer hull edge around it all"
    ),
    "kade": (
        f"{HOUSE}. {PERSON}: Kade, the station's depot master, a broad-shouldered middle-aged man with a "
        "graying beard, heavy work overalls with a high-visibility amber stripe, a data slate on his belt, "
        "thick gloves, a gruff but fair look"
    ),
    "selin": (
        f"{HOUSE}. {PERSON}: Selin, a member of the colony council, a calm woman in her fifties with short dark "
        "hair, a long practical coat over a station uniform, a small colony pin, a tablet in her hand, tired "
        "but determined eyes"
    ),
    "rook": (
        f"{HOUSE}. {PERSON}: Rook, captain of a rival prospecting crew, a lean confident person in their "
        "thirties with a scar across the cheek, a scuffed armored mining suit with the helmet under one arm, "
        "custom paint and crew patches, a cocky grin"
    ),
    "nell": (
        f"{HOUSE}. {PERSON}: Nell, the station's bartender, a sturdy woman in her forties with tattooed forearms "
        "and a braid, an apron over a work shirt with rolled sleeves, a rag over her shoulder, a knowing look"
    ),
    "colonists": (
        f"{HOUSE}. Character lineup of six ordinary colonists of a frontier space station side by side, full "
        "body, plain dark background: a dockworker, a mechanic, an elderly man, a young courier, a stall vendor, "
        "a medic, all in worn practical clothes and work suits, varied ages and builds"
    ),
}

GROUPS = [
    (STYLES, {room: f"{STATION}. This room: {text}" for room, text in ROOMS.items()}, 8000),
    ([(f"v{i}", "") for i in range(1, 5)], OWN, 8100),
]
