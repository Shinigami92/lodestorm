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
    "tamsin": {
        "name": "Tamsin",
        "role": "Pilot",
        "description": (
            "A woman in her late thirties, the pilot of a mining ship, talking to her crew over the ship's radio. "
            "Clear, steady mid-range voice, focused and practical, a veteran hauler pilot used to long flights in "
            "the dark. Warm but brisk, calm under pressure, with a slight edge of unease about the storms. Plain "
            "and conversational, not theatrical, not breathy or seductive. "
            "Native English speaker with a neutral accent."
        ),
        "lines": [
            (
                (
                    "There you are. I keep us flying, and every trip starts here at the navigator. "
                    "Come over to the holo table whenever you want to pick where we go next."
                ),
                (
                    "Da bist du ja. Ich halte uns in der Luft, und jede Reise beginnt hier am Navigator. "
                    "Komm an den Holotisch, wann immer du aussuchen willst, wohin es als Nächstes geht."
                ),
            ),
        ],
    },
    "kade": {
        "name": "Kade",
        "role": "Depot master",
        "description": (
            "A broad-shouldered man in his early fifties, the depot master of an orbital colony station, talking to "
            "a prospecting crew across the supply depot's counter. Solid, slightly rough baritone voice, lower "
            "mid-range, not deep or gravelly. Gruff but fair, organized and matter-of-fact, a man who keeps the books "
            "and knows every crate; friendly in a plain, unhurried way, never loud. Plain and conversational "
            "rather than narrating. Native English speaker with a neutral accent."
        ),
        "lines": [
            (
                (
                    "You must be the crew from the ship in the hangar. I'm Kade, and I run the supply depot. "
                    "Every crate that comes aboard this station passes my counter first."
                ),
                (
                    "Ihr seid sicher die Crew vom Schiff im Hangar. Ich bin Kade und leite das Versorgungsdepot. "
                    "Jede Kiste, die an Bord dieser Station kommt, geht zuerst über meinen Tresen."
                ),
            ),
            (
                (
                    "It's not a good rate, and it's not meant to be. "
                    "It's for when you're short of one ore and have far too much of another."
                ),
                (
                    "Das ist kein guter Kurs, und das soll er auch nicht sein. "
                    "Er ist für den Fall, dass dir ein Erz fehlt und du von einem anderen viel zu viel hast."
                ),
            ),
            (
                "Me? I keep the books. I know how many crates of anything we have, down to the last bolt.",
                "Ich? Ich führe die Bücher. Ich weiß, wie viele Kisten wir von allem haben, bis zur letzten Schraube.",
            ),
        ],
    },
    "selin": {
        "name": "Selin",
        "role": "Council member",
        "description": (
            "A woman in her early sixties, the long-serving head of an orbital colony's council and one of its first "
            "settlers, welcoming a prospecting crew at the council's long table. Mature, seasoned low alto voice with "
            "a little natural grain of age, calm and measured, clear and composed. Years of hard decisions have made "
            "her steady and a little weary, but determined. She chooses her words with care and speaks with the "
            "quiet authority of someone people have followed for a long time, warm but reserved. Plain and "
            "conversational, not giving a speech, not theatrical, not breathy or seductive. "
            "Native English speaker with a neutral accent."
        ),
        "lines": [
            (
                (
                    "Welcome to Waypost Ostra. I'm Selin, and I speak for the colony's council. "
                    "We're glad to have another prospecting crew in the system."
                ),
                (
                    "Willkommen auf Waypost Ostra. Ich bin Selin und spreche für den Rat der Kolonie. "
                    "Wir sind froh über jede weitere Prospektoren-Crew im System."
                ),
            ),
            (
                (
                    "Back then, we thought we'd be able to support ourselves within a few years. "
                    "That turned out to be a lot harder than any of us expected."
                ),
                (
                    "Damals dachten wir, wir könnten uns in ein paar Jahren selbst versorgen. "
                    "Das hat sich als viel schwerer herausgestellt, als wir alle erwartet hatten."
                ),
            ),
            (
                (
                    "People say I'm too careful with my words. Maybe they're right. "
                    "But on a station this small, a careless word travels fast."
                ),
                (
                    "Man sagt mir nach, ich wähle meine Worte zu vorsichtig. Vielleicht stimmt das. "
                    "Aber auf einer so kleinen Station spricht sich ein unbedachtes Wort schnell herum."
                ),
            ),
        ],
    },
}

# Round 1 renders this line with each voice-design take: long enough to hear the voice, in both languages later
ANCHOR_LINE_INDEX = 0
