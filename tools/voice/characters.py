"""The voice spike's cast: who each character is (for voice design) and the lines every candidate renders.

The descriptions are drafted from the characters' dialogue; they describe a made-up voice, never a real person's.
Lines are copied from the dialogue (English) and locale/de.po (German).
"""

CHARACTERS: dict[str, dict] = {
    "brannik": {
        "name": "Brannik",
        "role": "Quartermaster",
        "description": (
            "A man in his early sixties, the old quartermaster of a mining ship, talking to a crew member across "
            "the armory counter. Deep, weathered, slightly gravelly voice, worn by years aboard. Calm and grounded, "
            "never loud, plain and conversational rather than narrating. Practical and protective, with a dry, "
            "understated sense of humor. Native English speaker with a neutral accent."
        ),
        "lines": [
            (
                (
                    "Good, you're here. Before the next mission, let me go over the armory with you. "
                    "Keeping your gear and your ammo in order is my job."
                ),
                (
                    "Gut, dass du da bist. Lass uns vor der nächsten Mission kurz die Waffenkammer durchgehen. "
                    "Ich sorge dafür, dass deine Ausrüstung und deine Munition in Ordnung sind."
                ),
            ),
            (
                (
                    "During a mission, you only have the weapons you carry. "
                    "So choose wisely, or we'll be welcoming you in the medical bay."
                ),
                (
                    "Während einer Mission hast du nur die Waffen zur Verfügung, die du bei dir trägst. "
                    "Wähle also mit Bedacht, sonst müssen wir dich auf der Krankenstation begrüßen."
                ),
            ),
            (
                (
                    "If you have questions about ammo or reloading, just ask me. "
                    "Better here than out there with a swarm on your back."
                ),
                (
                    "Wenn du Fragen zu Munition oder zum Nachladen hast, frag einfach mich. "
                    "Besser hier als draußen, wenn dir ein Schwarm im Nacken sitzt."
                ),
            ),
            (
                (
                    "But careful with Harl: reloading throws away the rounds still left in the magazine. "
                    "So don't reload a half-full magazine just out of habit."
                ),
                (
                    "Aber Vorsicht bei Harl: Das Nachladen wirft die Munition weg, die noch im Magazin ist. "
                    "Lade ein halbvolles Magazin also nicht einfach aus Gewohnheit nach."
                ),
            ),
            (
                (
                    "Weapons only work inside the range, and a force field in the doorway stops every shot. "
                    "Nothing leaves that room."
                ),
                (
                    "Waffen funktionieren nur im Schießstand selbst, und ein Kraftfeld in der Tür hält jeden Schuss auf. "
                    "Aus diesem Raum kommt nichts heraus."
                ),
            ),
        ],
    },
    "nell": {
        "name": "Nell",
        "role": "Bartender",
        "description": (
            "A woman in her early thirties who runs the only bar on an orbital station, talking to a regular across "
            "the counter. Warm, slightly husky alto voice, clear, natural and present. Relaxed and friendly in a "
            "low-key way: open, not secretive or mysterious, and she doesn't perform or try to win anyone over. "
            "Dry, quiet humor. "
            "Native English speaker with a neutral accent."
        ),
        "lines": [
            (
                (
                    "Welcome to the only bar in orbit around Torvane. I'm Nell. "
                    "It's nothing fancy, but the drinks are cold and the chairs hardly wobble."
                ),
                (
                    "Willkommen in der einzigen Bar im Orbit um Torvane. Ich bin Nell. "
                    "Hier ist nichts Besonderes, aber die Getränke sind kalt, und die Stühle wackeln kaum."
                ),
            ),
            (
                (
                    "This place belongs to whoever needs it. Crews meet here, colonists come to forget their work "
                    "for an hour, and the council pretends it never drinks here."
                ),
                (
                    "Dieser Ort gehört allen, die ihn brauchen. Crews treffen sich hier, Leute aus der Kolonie vergessen "
                    "für eine Stunde ihre Arbeit, und der Rat tut so, als würde er hier nie etwas trinken."
                ),
            ),
            (
                "People tell me things they'd never tell the council. I keep most of it to myself. Most of it.",
                (
                    "Die Leute erzählen mir Dinge, die sie dem Rat nie erzählen würden. "
                    "Das meiste behalte ich für mich. Das meiste."
                ),
            ),
            (
                (
                    "Mossgrave is bad. Deep inside it, there's another one of those old camps with a blinking beacon. "
                    "Same pod, same silence."
                ),
                (
                    "Mossgrave ist übel. Tief darin steht noch so ein altes Lager mit einem blinkenden Funkfeuer. "
                    "Dieselbe Kapsel, dieselbe Stille."
                ),
            ),
            (
                (
                    "On Mirr, there's only one place to land: Quiet Scar. It has a meteorite crater, and the crews say "
                    "it's quieter there than anywhere else. They don't trust it."
                ),
                (
                    "Auf Mirr gibt es nur einen Ort zum Landen: Quiet Scar. Dort liegt ein Meteoritenkrater, und die "
                    "Crews sagen, es sei dort ruhiger als irgendwo sonst. Sie trauen dem Frieden nicht."
                ),
            ),
        ],
    },
}

# Round 1 renders this line with each voice-design take: long enough to hear the voice, in both languages later
ANCHOR_LINE_INDEX = 0
