"""Batch 10: the ship's crew (local/crew-looks-round-1.md), each in batch 8's framing for people, 4 seed variants.

Usage: python tools/concepts/batch.py batch10 [subject ...]
"""

from batches.batch5 import HOUSE

PERSON = (
    "full body character concept, standing pose, three-quarter view from slightly above, plain dark background, "
    "realistic proportions, single character, worn practical shipboard work clothes of a crew member aboard a "
    "mining spaceship, no armor, a thin glowing light band around the collar, a small round crew patch on the "
    "left shoulder showing a cyan crystal in a ring of storm clouds"
)

CREW: dict[str, str] = {
    "brannik": (
        "Brannik, the ship's quartermaster, a broad heavy man in his early sixties, a bit soft now, light weathered "
        "skin with deep lines, clean-shaven, close-cropped gray-white hair, a steady protective look, a dark olive "
        "padded armorer's vest with magazine pouches over a charcoal work shirt, a key ring and a data slate "
        "clipped to the belt, dark work trousers, heavy boots, a violet glowing collar band"
    ),
    "tamsin": (
        "Tamsin, the ship's pilot, a lean woman in her late thirties, light freckled skin, auburn hair tied back in "
        "a low practical bun, focused with a trace of worry, a fitted worn dark navy flight jacket with a high "
        "collar over a grey flight suit, a headset with a microphone boom, fingerless flight gloves, a pen and a "
        "small checklist slate in a sleeve pocket, a blue glowing collar band"
    ),
    "okoro": (
        "Okoro, the ship's engineer, a tall upright man of about fifty, dark brown skin, a shaved head, a short "
        "beard with gray in it, proud and absorbed, rust-brown engineering coveralls with the top half tied around "
        "the waist over a grey thermal undershirt, a heavy tool belt, a welding visor flipped up on his head, burn "
        "marks on the sleeves, an orange glowing collar band"
    ),
    "ilse": (
        "Ilse, the ship's medic, a thin upright woman in her mid-fifties, pale skin, sharp skeptical eyes, reading "
        "glasses on a cord, ash-blond hair going gray in a low knot, a pale grey-white high-collared medical tunic "
        "with a white cross on each shoulder, a dark utility vest with medical pouches, a scanner on her hip, "
        "gloves tucked in the belt, a white glowing collar band"
    ),
    "dace": (
        "Dace, the ship's gunsmith, a wiry man in his mid-thirties, medium brown skin, stubble, black hair with "
        "shaved sides and short on top, thoughtful, soot on his forearms and an old burn scar on one hand, a heavy "
        "scorched leather apron over a dark henley shirt with rolled sleeves, protective goggles pushed up on his "
        "forehead, a small tool roll on the belt, a red glowing collar band"
    ),
    "wren": (
        "Wren, the ship's suit technician, a small quick young woman in her early twenties, light olive skin, an "
        "open curious cheerful face, short choppy black hair with teal-dyed tips, a fitted light-grey technician "
        "jumpsuit with many small pockets, sleeves pushed up, a glowing display strapped to her left forearm, a "
        "coil of thin cable on one shoulder, a teal glowing collar band"
    ),
    "hollis": (
        "Hollis, the ship's miner mechanic and the oldest prospector in the system, a wiry slightly stooped man in "
        "his late sixties, deeply tanned leathery skin, white stubble, long thin gray hair tied back, gruff but "
        "kind eyes, a faded heavy canvas work jacket over old prospector's suit trousers with knee pads, a scuffed "
        "hard hat with a headlamp, grease on his hands, a rag in a back pocket, a green glowing collar band"
    ),
    "fenna": (
        "Fenna, the ship's cook, a sturdy round-faced woman in her mid-forties, warm brown skin, dark curly hair "
        "under a short cap, a calm listening smile, a double-breasted off-white cook's jacket with the sleeves "
        "rolled, a long dark apron, a towel through the apron string, a pink glowing collar band"
    ),
}

GROUPS = [
    ([(f"v{i}", "") for i in range(1, 5)], {name: f"{HOUSE}. {PERSON}: {text}" for name, text in CREW.items()}, 10000),
]

# Shown on the rating page beside each subject
LABELS = {
    "brannik": "Quartermaster",
    "tamsin": "Pilot",
    "okoro": "Engineer",
    "ilse": "Medic",
    "dace": "Gunsmith",
    "wren": "Suit tech",
    "hollis": "Miner mechanic",
    "fenna": "Cook",
}
