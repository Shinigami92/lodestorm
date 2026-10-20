# Sound effects (planned)

Decided 2026-10-17. The audio setup and the weapons' and the player's sounds are built (M4 step 9 B1, see [Sound](../GAME_DESIGN.md#sound) and [`TECHNICAL.md`](../TECHNICAL.md#4-asset-pipeline), Sound effects); what's left comes with PR B2 (see [`PLAN.md`](../PLAN.md)). All values **TBD (playtest)**. Around it: the dark, realistic look (human tech industrial and weathered, the hive organic and wet, see [Art direction](../GAME_DESIGN.md#art-direction)); alien telegraphs get a sound (see [`aliens.md`](aliens.md)); the voice-over comes after the art pass (see [`voice.md`](voice.md)).

## Making the rest

- **Recordings where synthesis isn't convincing:** likely the aliens' wet chittering (and the shots or the hammer, if their synthesized takes don't hold up by ear). Raw material from CC0 libraries (Kenney's audio packs, Freesound filtered to CC0, OpenGameArt CC0), processed by the build's recipes (layered with synthesized parts, pitched, filtered, trimmed). Freesound downloads need the owner's API key (an env var). AI-generated sounds may replace placeholders later, only from a model whose license allows selling the game (many audio models' weights are non-commercial or capped); the manifest's `made_by` names the model, which is also what Steam's AI content disclosure needs.
- **Replacing the placeholders:** every built sound is a placeholder; a better one (synthesized again, recorded or AI-generated) replaces its files under the same names (see TECHNICAL, Sound effects).
- **Credits:** the credits page gets the authors of CC-BY recordings, generated from the manifest, with the first one used.
- **Loops and long sounds** (the drill, the hose, the storm): WAV with loop points in the `.import`, like the rest; Ogg Vorbis (and an encoder for the build) only once music or minute-long ambience needs it.
- **Menu sounds:** B1's takes (open, close, highlight, confirm, deny) were dropped after listening (2026-10-20), with the Interface bus and its slider; the menus stay silent until they get their own round (what should sound at all, and how).
- **Death:** two rounds of synthesized takes didn't work ("does not feel like a death sound", then "horrible"); the player dies silently until a new approach (e.g. a recording of a body and armor falling, processed by the scripts).
- **The hive's style:** wet, clicking and chittering; the storm a deep roar with grit; ore only hums softly.

## The sounds of B2

- **Aliens:** the swarmer's chitter (idle), attack, hit (flesh), death; the nest's pulse growing with the escalation, a hatch; the telegraphs (a wind-up sound per heavy attack). A limit per sound (e.g. at most 4 swarmer attacks at once).
- **Mining:** placing a miner, its drill loop, the full chime, the hose's flow, the breakdown alarm, repairing.
- **Mission:** the ramp, the countdown's last-minute beeps, the storm building (ambience, on the Ambience bus) and hitting; the storm warning is a critical cue.
- **Biomes:** the vents' rumble (1.5 s, rising) and burst (the Ash fields' hazard), the shards' crunch underfoot (the Glass plains' hazard), the mud's squelch underfoot (the Overgrowth's hazard): the steps on shards and in mud swap their sound (`PlayerSounds` picks it per step).

Other surfaces' steps (snow, salt, ash), the aliens' steps, the ship's ambience, doors and lifts, and the sounds of the new strains and weapons come with their own steps or the art pass. Music gets its own round later.
