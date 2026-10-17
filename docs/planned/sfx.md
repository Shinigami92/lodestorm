# Sound effects (planned)

Decided 2026-10-17, built in M4 step 7 as PRs E1 and E2 (see [`PLAN.md`](../PLAN.md)). All values **TBD (playtest)**. Today the game has no audio at all. Around it: the dark, realistic look (human tech industrial and weathered, the hive organic and wet, see [Art direction](../GAME_DESIGN.md#art-direction)); the timing reload's window gets a sound cue (needed for VR and accessibility); alien telegraphs get a sound (see [`aliens.md`](aliens.md)); the voice-over comes after the art pass (see [`voice.md`](voice.md)).

## Making the sounds

- **Synthesized by our own scripts:** the sounds are built in code (Python, in the repo, like the Blender scripts build the models): oscillators, noise, envelopes, filters, layered and pitched into each sound, deterministic (fixed seeds), so a rerun gives the same files and every sound can be rebuilt or tuned any time. They're entirely the project's own, with no license questions. Clicks, beeps, hums, alarms, motors, the hose's flow and the storm's roar synthesize well.
- **CC0 recordings where synthesis isn't convincing:** likely the gunshots, the hammer's impact and the aliens' wet chittering. Raw material from CC0 libraries (Kenney's audio packs, Freesound filtered to CC0, OpenGameArt CC0), processed by the same scripts (layered with synthesized parts, pitched, filtered, trimmed). CC-BY 4.0 is allowed too, with a credit; never NC, ND or SA licenses (they clash with selling the game). Freesound downloads need the owner's API key (an env var). Local AI audio models: not now, their weights' licenses are mostly non-commercial or capped.
- **Placeholders by design:** a sound can be replaced by a better one under the same name, so nothing in the scenes changes.
- **License tracking:** every recorded raw file has an entry in a manifest next to it (source URL, author, license); a test fails on a game sound whose recorded sources aren't all in the manifest with an allowed license. Credits for CC-BY are generated from it.

## Files

`assets/audio/source/` holds the scripts, the raw recordings and the manifest (with a `.gdignore`, like the Blender sources); `assets/audio/sfx/<group>/` the built sounds. Short sounds (up to about 2 s) as 16-bit mono WAV (cheap to play often), loops and long ones as Ogg Vorbis, all in Git LFS. A build script rebuilds every sound from its recipe.

## Playing them

- **Variation:** every sound that repeats has 3–5 variants and a small random pitch (±5 %), through Godot's `AudioStreamRandomizer`, so shots and hits never sound like a loop.
- **Where the ear is:** the listener sits at the player (not at the camera 40 m away), turned like the camera, so left and right match the screen and the falloff fits what's on screen. World sounds are 3D (from the gun, the alien, the miner); menu sounds are flat. In co-op each player hears from their own player; VR (M6) puts the ears at the head (see [`vr-view.md`](vr-view.md)).
- **When it gets busy:** a limit per sound (e.g. at most 4 swarmer attacks at once, the rest skipped), farther sounds dropped first. Critical cues never get cut and duck the rest a little: the timing window's tick, a hit taken, low health, the storm warning.
- **Playable muted:** nothing is told only by sound; everything a sound says is also shown in the world.
- **Buses and settings:** Master → **Effects**, **Ambience**, **Interface** (later Voice, Radio and Music); a volume each for Master, Effects, Ambience and Interface in the settings (the pause panel and the settings terminal, see [`menu-pause.md`](menu-pause.md)).
- **Style:** weighty and real, no cartoon or chiptune: human gear clanks, hisses and hums (industrial, worn), weapons punchy but not arcade, the hive wet, clicking and chittering, the storm a deep roar with grit. Quiet by default: ore and menus only hum softly.
- **Picking by ear:** a local listening page (like the concept-image ranking page) with 2–3 takes per sound; the rest are built in the direction of the favorites.

## The first sounds

About 30:

- **Weapons:** blaster shot, shotgun shot, hammer swing and hit, empty click, reload start / shell in / magazine in, the timing window's tick, timed success and miss.
- **Player:** hit taken, low health (a slow pulse below a quarter), death, dash.
- **Aliens:** the swarmer's chitter (idle), attack, hit (flesh), death; the nest's pulse growing with the escalation, a hatch.
- **Mining:** placing a miner, its drill loop, the full chime, the hose's flow, the breakdown alarm, repairing.
- **Mission:** the ramp, the countdown's last-minute beeps, the storm building (ambience) and hitting.
- **Interface:** a station opening and closing, highlight, confirm, deny.

Footsteps, the ship's ambience, doors and lifts, and the sounds of the new strains and weapons come with their own steps or the art pass. Music gets its own round later.
