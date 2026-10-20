# Sound effects (planned)

Decided 2026-10-17. The audio setup and the sounds of the weapons, the player, the aliens and nests, mining, the mission and the biomes' hazards are built (M4 step 9 B, see [Sound](../GAME_DESIGN.md#sound) and [`TECHNICAL.md`](../TECHNICAL.md#4-asset-pipeline), Sound effects); this is what's left, without a step of its own yet. All values **TBD (playtest)**. Around it: the dark, realistic look (human tech industrial and weathered, the hive organic and wet, see [Art direction](../GAME_DESIGN.md#art-direction)); the voice-over comes after the art pass (see [`voice.md`](voice.md)).

## Making the rest

- **Recordings where synthesis isn't convincing:** likely the aliens' wet chittering (and the shots or the hammer, if their synthesized takes don't hold up by ear). Raw material from CC0 libraries (Kenney's audio packs, Freesound filtered to CC0, OpenGameArt CC0), processed by the build's recipes (layered with synthesized parts, pitched, filtered, trimmed). Freesound downloads need the owner's API key (an env var). AI-generated sounds may replace placeholders later, only from a model whose license allows selling the game (many audio models' weights are non-commercial or capped); the manifest's `made_by` names the model, which is also what Steam's AI content disclosure needs.
- **Replacing the placeholders:** every built sound is a placeholder; a better one (synthesized again, recorded or AI-generated) replaces its files under the same names (see TECHNICAL, Sound effects).
- **Credits:** the credits page gets the authors of CC-BY recordings, generated from the manifest, with the first one used.
- **Long sounds:** WAV like the rest (the loops carry their loop points in the file); Ogg Vorbis (and an encoder for the build) only once music or minute-long ambience needs it.
- **Menu sounds:** B1's takes (open, close, highlight, confirm, deny) were dropped after listening (2026-10-20), with the Interface bus and its slider; the menus stay silent until they get their own round (what should sound at all, and how).
- **Death:** two rounds of synthesized takes didn't work ("does not feel like a death sound", then "horrible"); the player dies silently until a new approach (e.g. a recording of a body and armor falling, processed by the scripts).
- **Ore** only hums softly, when it gets a sound.

## Still to come

Other surfaces' steps (snow, salt, ash), the aliens' steps, the ship's ambience, doors and lifts, and the sounds of the new strains and weapons come with their own steps or the art pass. Music gets its own round later.
