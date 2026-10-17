# Voice-over (planned)

Decided 2026-10-17, built after the art pass (see [`PLAN.md`](../PLAN.md), M5). All values **TBD (playtest)**. What's wanted (see [Localization and voice](../GAME_DESIGN.md#localization-and-voice)): English voice-over from a free AI text-to-speech model running locally, lines generated ahead of time, a license that allows selling the game, distinct voices that aren't cloned from real people without their consent; subtitles as speech bubbles, as today. The audio basics (the buses and the volume settings) come earlier, with the sound effects (M4 step 7, see [`sfx.md`](sfx.md)).

## The spike

- **What it decides:** which model, how the voices are made, and the pipeline from a line to a sound in the game, proven on one NPC (Brannik, every line he has). The rest of the cast follows with the tool.
- **Candidates,** each checked again for the license of its code **and** its weights and for what it says about generated audio: **Chatterbox** (MIT; English, and a multilingual model with German; expressive, takes a short reference clip for the voice), **Kokoro** (Apache-2.0; small and fast, ships ready-made voices, English first), **Piper** (MIT engine; many voices including German, each voice with its own license; plain but light, the fallback). Earlier research ruled out XTTS-v2, F5 and Fish (non-commercial weights). The winner and the reason go into [`TECHNICAL.md`](../TECHNICAL.md), which later feeds Steam's AI disclosure (M8).
- **Voices without cloning real people:** no recordings of real people (also no public-domain readings: their readers never agreed to being cloned). Voices come from a model's own built-in or designed voices; where a model needs a reference clip, the clip is made by another model's synthetic voice, and each NPC's voice records where it came from (model, voice id, settings) next to its profile. About 15 voices in the end (8 crew, 4 station NPCs, a few spares), clearly apart in pitch, pace and timbre.
- **Picking by ear:** the spike renders the same five Brannik lines with each candidate and several voices, on a local listening page like the concept-image ranking page (play, stars, notes); the winner and Brannik's voice come from the ratings.

## In the game

- **Languages:** an English voice in every language at first, with the subtitles in the player's language. A separate voice language setting only if a German voice is ever good enough.
- **The pipeline:** a dev tool (`tools/voice.sh`, running the model locally like the Blender scripts; heavy on the GPU) reads every line from the dialogue data and renders one file per line and voice (Ogg Vorbis) into `assets/voice/<npc>/`, named by a hash of the English text and the voice, so a changed line gets a new file and stale files are listed for removal. Committed with Git LFS, not run in CI. Lines stay the English originals (the translation keys).
- **Playing it:** when a bubble shows a line, its file plays from the NPC (3D sound); moving on stops it and plays the next; a line without a file just shows the bubble, so missing audio never breaks anything. Radio lines play near the player through a radio filter (band-pass and a little static, an effect on a Radio bus, not baked into the files), so the same voice sounds different on the radio.
- **Settings:** a Voice and a Radio bus next to the earlier ones, their volumes in the settings terminal, and "Voice on/off".
- **Tests:** every voice file belongs to a current line (no orphans) and plays; a report (not a failure) of lines without audio, since the cast fills up over several steps.
- **AI-driven NPCs** stay a later, separate experiment (they share the GPU with rendering and need guardrails).
